package com.zktlsreactnative

import ai.zktls.sdk.Claim
import ai.zktls.sdk.LoginDisclosure
import ai.zktls.sdk.Phase
import ai.zktls.sdk.PlatformStatus
import ai.zktls.sdk.ProofReport
import ai.zktls.sdk.SessionConfig
import ai.zktls.sdk.VerifyOutcome
import ai.zktls.sdk.ZktlsTheme
import android.content.Context
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.WritableMap

// Converts between React Native's maps and the native SDK's types. The SDK
// validates config values itself (for example baseUrl must be https), so a
// missing field here is read as empty rather than guarded again.
fun readSessionConfig(map: ReadableMap): SessionConfig = SessionConfig(
  baseUrl = map.getString("baseUrl") ?: "",
  appCredential = map.getString("appCredential") ?: "",
  userIdHash = map.getString("userIdHash") ?: "",
  profileId = map.getString("profileId") ?: "",
  policyId = map.getString("policyId") ?: "",
  idempotencyKey = map.getString("idempotencyKey") ?: "",
  clientRegion = map.getString("clientRegion") ?: "",
  networkKey = map.getString("networkKey") ?: "",
  trustBundleJson = map.getString("trustBundleJson") ?: "",
  trustBundleUrl = if (map.hasKey("trustBundleUrl")) map.getString("trustBundleUrl") ?: "" else "",
  trustOperatorKey = map.getString("trustOperatorKey") ?: "",
  policyBundleJson = map.getString("policyBundleJson") ?: "",
  policyBundleDigest = map.getString("policyBundleDigest") ?: "",
)

// Builds the consent screen's text. A field left out on the JS side reads as
// empty here.
// A field left out keeps the SDK's standard text for the login's cookie domains.
fun readDisclosure(map: ReadableMap, domains: List<String>): LoginDisclosure {
  val standard = LoginDisclosure.standard(domains)
  return LoginDisclosure(
    title = map.getString("title") ?: standard.title,
    message = map.getString("message") ?: standard.message,
    accept = map.getString("accept") ?: standard.accept,
    decline = map.getString("decline") ?: standard.decline,
  )
}

// configure given a value it cannot use; rejected as InvalidArgument, with a
// message naming the field. iOS rejects the same values with the same message.
class InvalidArgumentException(message: String) : IllegalArgumentException(message)

// Exactly "#RRGGBB" or "#AARRGGBB", hex digits in either case.
private val hexColor = Regex("#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})")

// The ARGB color int of a "#RRGGBB" (opaque) or "#AARRGGBB" color, or null for
// anything else, color names included.
fun parseHexColor(value: String): Int? {
  if (!hexColor.matches(value)) return null
  val digits = value.substring(1)
  val argb = digits.toLong(16)
  return (if (digits.length == 6) argb or 0xFF000000L else argb).toInt()
}

// The screens' theme. A color is "#RRGGBB" or "#AARRGGBB"; the logo is a
// drawable's name in the app. A field left out keeps the SDK's default, so an
// empty map is the SDK's own look. A color in any other form throws.
fun readTheme(context: Context, map: ReadableMap?): ZktlsTheme {
  if (map == null) return ZktlsTheme()
  fun color(field: String): Int? {
    if (!map.hasKey(field) || map.isNull(field)) return null
    val value = if (map.getType(field) == ReadableType.String) map.getString(field) else null
    return value?.let { parseHexColor(it) }
      ?: throw InvalidArgumentException("theme.$field must be #RRGGBB or #AARRGGBB")
  }
  val logo = map.getString("logo")?.let {
    context.resources.getIdentifier(it, "drawable", context.packageName).takeIf { id -> id != 0 }
  }
  return ZktlsTheme(accent = color("accent"), background = color("background"), text = color("text"), logo = logo)
}

// The screens' words, by key. A null value is left out, as iOS receives none;
// any other value that is not a string throws, as on iOS.
fun readStrings(map: ReadableMap?): Map<String, String> {
  if (map == null) return emptyMap()
  val out = mutableMapOf<String, String>()
  val keys = map.keySetIterator()
  while (keys.hasNextKey()) {
    val key = keys.nextKey()
    val type = map.getType(key)
    if (type == ReadableType.Null) continue
    val value = if (type == ReadableType.String) map.getString(key) else null
    out[key] = value ?: throw InvalidArgumentException("strings[\"$key\"] must be a string")
  }
  return out
}

// The native Phase, lowercased to the strings the JS Phase union uses.
fun phaseToString(phase: Phase): String = when (phase) {
  Phase.LOGGING_IN -> "loggingIn"
  Phase.COLLECTING -> "collecting"
  Phase.ATTESTING -> "attesting"
  Phase.DETACHED -> "detached"
  Phase.ALLOCATING -> "allocating"
  Phase.CAPTURING -> "capturing"
  Phase.CAPTURED -> "captured"
  Phase.PROVING -> "proving"
  Phase.PROVED -> "proved"
  Phase.CLAIMING -> "claiming"
  Phase.DONE -> "done"
  Phase.FAILED -> "failed"
}

// The u64 fields cross as strings: JS numbers lose integer precision above
// 2^53, so the JS side re-parses ULong.toString()'s exact decimal.
fun writeProofReport(report: ProofReport): WritableMap = Arguments.createMap().apply {
  putBoolean("accepted", report.accepted)
  putString("verdict", report.verdict)
  putString("nullifierHex", report.nullifierHex)
  putString("encodedClaim", report.encodedClaim)
  putString("proveMs", report.proveMs.toString())
  putString("sentBytes", report.sentBytes.toString())
  putString("receivedBytes", report.receivedBytes.toString())
}

fun writeClaim(claim: Claim): WritableMap = Arguments.createMap().apply {
  putString("nullifierHex", claim.nullifierHex)
  putString("profileId", claim.profileId)
  putString("policyId", claim.policyId)
  putString("signatureHex", claim.signatureHex)
  putString("encoded", claim.encoded)
  putInt("verifierEpoch", claim.verifierEpoch.toInt())
  putString("issuedAt", claim.issuedAt.toString())
  putString("expiresAt", claim.expiresAt.toString())
  val outputsArr = Arguments.createArray()
  for (output in claim.outputs) {
    outputsArr.pushMap(writeTypedOutput(output))
  }
  putArray("outputs", outputsArr)
}

fun writeTypedOutput(output: ai.zktls.sdk.TypedOutput): WritableMap = Arguments.createMap().apply {
  putString("name", output.name)
  putString("valueJson", output.valueJson)
}

// The native PlatformStatus, lowercased to the strings the JS union uses.
fun statusToString(status: PlatformStatus): String = when (status) {
  PlatformStatus.DONE -> "done"
  PlatformStatus.FAILED -> "failed"
  PlatformStatus.NOT_STARTED -> "notStarted"
}

fun writeVerifyOutcome(outcome: VerifyOutcome): WritableMap = Arguments.createMap().apply {
  putString("verificationId", outcome.verificationId)
  val platforms = Arguments.createArray()
  for (p in outcome.platforms) {
    platforms.pushMap(Arguments.createMap().apply {
      putString("platform", p.platform)
      putString("status", statusToString(p.status))
      if (p.reason != null) putString("reason", p.reason) else putNull("reason")
    })
  }
  putArray("platforms", platforms)
}
