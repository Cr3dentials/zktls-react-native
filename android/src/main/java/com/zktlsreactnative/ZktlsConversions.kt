package com.zktlsreactnative

import ai.zktls.sdk.Claim
import ai.zktls.sdk.LoginDisclosure
import ai.zktls.sdk.Phase
import ai.zktls.sdk.ProofReport
import ai.zktls.sdk.SessionConfig
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReadableMap
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
  trustOperatorKey = map.getString("trustOperatorKey") ?: "",
  policyBundleJson = map.getString("policyBundleJson") ?: "",
  policyBundleDigest = map.getString("policyBundleDigest") ?: "",
)

// Builds the consent screen's text. A field left out on the JS side reads as
// empty here.
fun readDisclosure(map: ReadableMap): LoginDisclosure = LoginDisclosure(
  title = map.getString("title") ?: "",
  message = map.getString("message") ?: "",
  accept = map.getString("accept") ?: "",
  decline = map.getString("decline") ?: "",
)

// The native Phase, lowercased to the strings the JS Phase union uses.
fun phaseToString(phase: Phase): String = when (phase) {
  Phase.loggingIn -> "loggingIn"
  Phase.allocating -> "allocating"
  Phase.capturing -> "capturing"
  Phase.captured -> "captured"
  Phase.proving -> "proving"
  Phase.proved -> "proved"
  Phase.claiming -> "claiming"
  Phase.done -> "done"
  Phase.failed -> "failed"
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
