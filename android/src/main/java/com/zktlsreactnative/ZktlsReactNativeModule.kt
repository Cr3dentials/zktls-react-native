package com.zktlsreactnative

import ai.zktls.sdk.LoginDisclosure
import ai.zktls.sdk.SdkException
import ai.zktls.sdk.WebViewLoginPresenter
import ai.zktls.sdk.Zktls
import ai.zktls.sdk.ZkTlsLifecycle
import ai.zktls.sdk.ZkTlsSessionService
import ai.zktls.sdk.ZktlsClient
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// The native side owns one ZktlsClient per session, keyed by a sessionId this
// module generates. JS only ever holds that id (see index.tsx); the opaque
// handles never cross the bridge. The flow is login -> capture -> prove ->
// claim, serialized inside the native client.
class ZktlsReactNativeModule(private val reactContext: ReactApplicationContext) :
  NativeZktlsReactNativeSpec(reactContext) {

  private val sessions = ConcurrentHashMap<String, ZktlsClient>()
  // One lifecycle per session, on the client's own handle, as the SDK's sample
  // wires it: it follows network changes and, with the foreground service, keeps
  // a session alive when the user leaves the app.
  private val lifecycles = ConcurrentHashMap<String, ZkTlsLifecycle>()
  // ZkTlsSessionService has a single slot: the session that started it owns it,
  // and a later session goes on without the service rather than take it over.
  private val serviceOwner = AtomicReference<String?>(null)
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  override fun getName(): String = NAME

  override fun create(config: ReadableMap, promise: Promise) {
    try {
      val client = ZktlsClient(readSessionConfig(config))
      val sessionId = UUID.randomUUID().toString()
      // Registered before the id is handed back so no early phase is missed.
      client.onProgress { phase, percent -> emitProgress(sessionId, phase, percent) }
      lifecycles[sessionId] = ZkTlsLifecycle(reactContext, client.lifecycleHandle)
      sessions[sessionId] = client
      promise.resolve(sessionId)
    } catch (e: Throwable) {
      rejectSdk(promise, e)
    }
  }

  // The SDK's facade: configure once, then verify per user. verify shows the
  // SDK's own screens over the current activity and keeps its session alive
  // itself, so it needs none of the proof sessions' lifecycle here.
  override fun configure(appKey: String, theme: ReadableMap?, strings: ReadableMap?, promise: Promise) {
    try {
      Zktls.configure(appKey, readTheme(reactContext, theme), readStrings(strings))
      promise.resolve(null)
    } catch (e: Throwable) {
      rejectSdk(promise, e)
    }
  }

  override fun verify(platforms: ReadableArray, reference: String, promise: Promise) {
    val activity = reactContext.currentActivity
      ?: return promise.reject("Internal", "no current activity for the SDK's screens")
    val ids = (0 until platforms.size()).mapNotNull { platforms.getString(it) }
    scope.launch {
      try {
        promise.resolve(writeVerifyOutcome(Zktls.verify(activity, ids, reference)))
      } catch (e: Throwable) {
        rejectSdk(promise, e)
      }
    }
  }

  override fun verifyToken(token: String, promise: Promise) {
    val activity = reactContext.currentActivity
      ?: return promise.reject("Internal", "no current activity for the SDK's screens")
    scope.launch {
      try {
        promise.resolve(writeVerifyOutcome(Zktls.verify(activity, token)))
      } catch (e: Throwable) {
        rejectSdk(promise, e)
      }
    }
  }

  override fun login(sessionId: String, disclosure: ReadableMap?, promise: Promise) {
    val client = sessions[sessionId] ?: return promise.reject("Internal", "unknown session")
    val activity = reactContext.currentActivity
      ?: return promise.reject("Internal", "no current activity for the login WebView")
    // The presenter shows the disclosure, then the login page, on the UI thread.
    // Falls back to the SDK's standard disclosure when none is given.
    val presenter = if (disclosure != null) {
      WebViewLoginPresenter(activity) { domains -> readDisclosure(disclosure, domains) }
    } else {
      WebViewLoginPresenter(activity)
    }
    scope.launch {
      try {
        client.login(presenter)
        // Only now, since the login page is the user's to take time over. Capture
        // and proof then survive the user leaving the app or changing network.
        hold(sessionId)
        promise.resolve(null)
      } catch (e: Throwable) {
        rejectSdk(promise, e)
      }
    }
  }

  override fun capture(sessionId: String, promise: Promise) {
    val client = sessions[sessionId] ?: return promise.reject("Internal", "unknown session")
    scope.launch {
      try {
        client.capture()
        promise.resolve(null)
      } catch (e: Throwable) {
        // SessionLost keeps the login: its recovery is another capture.
        if (e !is SdkException.SessionLost) release(sessionId)
        rejectSdk(promise, e)
      }
    }
  }

  override fun prove(sessionId: String, promise: Promise) {
    val client = sessions[sessionId] ?: return promise.reject("Internal", "unknown session")
    scope.launch {
      try {
        val report = client.prove()
        // A rejected proof ends the session: there is no claim to fetch.
        if (!report.accepted) release(sessionId)
        promise.resolve(writeProofReport(report))
      } catch (e: Throwable) {
        release(sessionId)
        rejectSdk(promise, e)
      }
    }
  }

  override fun claim(sessionId: String, promise: Promise) {
    val client = sessions[sessionId] ?: return promise.reject("Internal", "unknown session")
    scope.launch {
      try {
        promise.resolve(writeClaim(client.claim()))
      } catch (e: Throwable) {
        rejectSdk(promise, e)
      } finally {
        release(sessionId)
      }
    }
  }

  // Synchronous on purpose: it must reach a verb in flight, so it is not queued
  // behind one. Safe if the session is already gone.
  override fun cancel(sessionId: String) {
    sessions[sessionId]?.cancel()
  }

  // Drops the client so its native handles are released. Not a native verb; the
  // bridge needs it so clients are not kept forever.
  override fun dispose(sessionId: String, promise: Promise) {
    release(sessionId)
    lifecycles.remove(sessionId)
    sessions.remove(sessionId)
    promise.resolve(null)
  }

  // Starts following the network and the foreground service for a session. On the
  // main thread. From API 31 a background start throws: the session then goes on
  // without the service.
  private fun hold(sessionId: String) {
    val client = sessions[sessionId] ?: return
    val lifecycle = lifecycles[sessionId] ?: return
    lifecycle.begin()
    if (!serviceOwner.compareAndSet(null, sessionId)) return
    try {
      ZkTlsSessionService.start(reactContext, lifecycle) { client.cancel() }
    } catch (e: IllegalStateException) {
      // ForegroundServiceStartNotAllowedException: the app is in the background.
      // start set the slot before it threw, so clear it.
      serviceOwner.set(null)
      ZkTlsSessionService.stop(reactContext)
    }
  }

  // Ends what hold started. Idempotent, so every exit may call it.
  private fun release(sessionId: String) {
    lifecycles[sessionId]?.end()
    if (serviceOwner.compareAndSet(sessionId, null)) ZkTlsSessionService.stop(reactContext)
  }

  // Builds the progress payload and hands it to the codegen emitter generated
  // from the onProgress EventEmitter in the spec.
  private fun emitProgress(sessionId: String, phase: ai.zktls.sdk.Phase, percent: UByte) {
    val payload = Arguments.createMap().apply {
      putString("sessionId", sessionId)
      putString("phase", phaseToString(phase))
      putInt("percent", percent.toInt())
    }
    emitOnProgress(payload)
  }

  // Maps every SdkException variant to the code JS matches on (see SdkErrorCode
  // in index.tsx). Transport, Policy and Refused carry their text, as does the
  // bridge's own InvalidArgument; anything else is a fault to report as Internal.
  private fun rejectSdk(promise: Promise, e: Throwable) {
    when (e) {
      is SdkException.NotLoggedIn -> promise.reject("NotLoggedIn", "NotLoggedIn", e)
      is SdkException.SessionLost -> promise.reject("SessionLost", "SessionLost", e)
      is SdkException.Cancelled -> promise.reject("Cancelled", "Cancelled", e)
      is SdkException.WrongEvidence -> promise.reject("WrongEvidence", "WrongEvidence", e)
      is SdkException.Truncated -> promise.reject("Truncated", "Truncated", e)
      is SdkException.ExtraResponse -> promise.reject("ExtraResponse", "ExtraResponse", e)
      is SdkException.Reordered -> promise.reject("Reordered", "Reordered", e)
      is SdkException.LimitExceeded -> promise.reject("LimitExceeded", "LimitExceeded", e)
      is SdkException.InsufficientMemory -> promise.reject("InsufficientMemory", "InsufficientMemory", e)
      is SdkException.Transport -> promise.reject("Transport", e.v1, e)
      is SdkException.Policy -> promise.reject("Policy", e.v1, e)
      // The refusal code (device_not_verified, app_key_invalid, ...) reaches JS
      // as userInfo.refusal.
      is SdkException.Refused -> promise.reject(
        "Refused",
        e.message,
        e,
        Arguments.createMap().apply { putString("refusal", e.code) },
      )
      is InvalidArgumentException -> promise.reject("InvalidArgument", e.message, e)
      else -> promise.reject("Internal", e.message ?: "internal error", e)
    }
  }

  companion object {
    const val NAME = NativeZktlsReactNativeSpec.NAME
  }
}
