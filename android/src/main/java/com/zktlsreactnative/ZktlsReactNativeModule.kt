package com.zktlsreactnative

import ai.zktls.sdk.LoginDisclosure
import ai.zktls.sdk.SdkException
import ai.zktls.sdk.WebViewLoginPresenter
import ai.zktls.sdk.ZktlsClient
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
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
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  override fun getName(): String = NAME

  override fun create(config: ReadableMap, promise: Promise) {
    try {
      val client = ZktlsClient(readSessionConfig(config))
      val sessionId = UUID.randomUUID().toString()
      // Registered before the id is handed back so no early phase is missed.
      client.onProgress { phase, percent -> emitProgress(sessionId, phase, percent) }
      sessions[sessionId] = client
      promise.resolve(sessionId)
    } catch (e: Throwable) {
      rejectSdk(promise, e)
    }
  }

  override fun login(sessionId: String, disclosure: ReadableMap?, promise: Promise) {
    val client = sessions[sessionId] ?: return promise.reject("Internal", "unknown session")
    val activity = reactContext.currentActivity
      ?: return promise.reject("Internal", "no current activity for the login WebView")
    // The presenter shows the disclosure, then the login page, on the UI thread.
    // Falls back to the SDK's standard disclosure when none is given.
    val presenter = if (disclosure != null) {
      WebViewLoginPresenter(activity) { readDisclosure(disclosure) }
    } else {
      WebViewLoginPresenter(activity)
    }
    scope.launch {
      try {
        client.login(presenter)
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
        rejectSdk(promise, e)
      }
    }
  }

  override fun prove(sessionId: String, promise: Promise) {
    val client = sessions[sessionId] ?: return promise.reject("Internal", "unknown session")
    scope.launch {
      try {
        promise.resolve(writeProofReport(client.prove()))
      } catch (e: Throwable) {
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
    sessions.remove(sessionId)
    promise.resolve(null)
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
  // in index.tsx). Transport and Policy carry their text; anything else is a
  // fault to report as Internal.
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
      else -> promise.reject("Internal", e.message ?: "internal error", e)
    }
  }

  companion object {
    const val NAME = NativeZktlsReactNativeSpec.NAME
  }
}
