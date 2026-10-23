package com.zktlsreactnative

import ai.zktls.sdk.Claim
import ai.zktls.sdk.LoginDisclosure
import ai.zktls.sdk.Phase
import ai.zktls.sdk.ProofReport
import ai.zktls.sdk.SessionConfig
import ai.zktls.sdk.SourceEvidence
import ai.zktls.sdk.TreeDisclosure
import ai.zktls.sdk.TreeRunConfig
import ai.zktls.sdk.TreeSource
import ai.zktls.sdk.TreeSummary
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

fun readTreeRunConfig(map: ReadableMap): TreeRunConfig = TreeRunConfig(
  baseUrl = map.getString("baseUrl") ?: "",
  appCredential = map.getString("appCredential") ?: "",
  userIdHash = map.getString("userIdHash") ?: "",
  idempotencyKey = map.getString("idempotencyKey") ?: "",
  clientRegion = map.getString("clientRegion") ?: "",
  networkKey = map.getString("networkKey") ?: "",
  platformId = map.getString("platformId") ?: "",
  trustBundleJson = map.getString("trustBundleJson") ?: "",
  trustBundleUrl = if (map.hasKey("trustBundleUrl")) map.getString("trustBundleUrl") ?: "" else "",
  trustOperatorKey = map.getString("trustOperatorKey") ?: "",
  policyBundleJson = map.getString("policyBundleJson") ?: "",
  policyBundleDigest = map.getString("policyBundleDigest") ?: "",
  relyingPartyNonceHex = map.getString("relyingPartyNonceHex") ?: "",
  resultUrl = map.getString("resultUrl") ?: "",
  resultToken = map.getString("resultToken") ?: "",
  paramsJson = map.getString("paramsJson") ?: "",
)

fun readTreeDisclosure(map: ReadableMap): TreeDisclosure = TreeDisclosure(
  title = map.getString("title") ?: "",
  message = map.getString("message") ?: "",
  accept = map.getString("accept") ?: "",
  decline = map.getString("decline") ?: "",
)

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

fun writeTreeSummary(s: TreeSummary): WritableMap = Arguments.createMap().apply {
  putBoolean("succeeded", s.succeeded)
  putString("error", s.error)
  val sourcesArr = Arguments.createArray()
  for (source in s.sources) {
    sourcesArr.pushMap(writeTreeSource(source))
  }
  putArray("sources", sourcesArr)
  val claim = s.claim
  if (claim != null) putMap("claim", writeClaim(claim)) else putNull("claim")
  putInt("apiCalls", s.apiCalls.toInt())
  putString("durationMs", s.durationMs.toString())
  putBoolean("delivered", s.delivered)
  putString("deliveryError", s.deliveryError)
  putString("resultBytes", s.resultBytes.toString())
  putString("isolation", s.isolation)
  putBoolean("handedOff", s.handedOff)
}

fun writeTreeSource(source: TreeSource): WritableMap = Arguments.createMap().apply {
  putString("storeAs", source.storeAs)
  putString("evidence", when (source.evidence) {
    SourceEvidence.OBSERVED -> "observed"
    SourceEvidence.ATTESTED -> "attested"
  })
  putString("rows", source.rows.toString())
  putInt("pages", source.pages.toInt())
  putString("bytes", source.bytes.toString())
  putBoolean("complete", source.complete)
}
