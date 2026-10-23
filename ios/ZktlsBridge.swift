import Foundation
import UIKit
import ZktlsSDK

// The substantive iOS bridge. The Obj-C++ module (ZktlsReactNative.mm) is a thin
// forwarder to this; keeping the logic in Swift lets it call the SDK's async
// actor API directly. Mirrors the Android module: one ZktlsClient per session,
// keyed by a generated sessionId, with the opaque handles never leaving here.
//
// Methods take completion handlers rather than being async, because Obj-C cannot
// call Swift async functions directly. Results and errors are JSON-safe so the
// .mm can resolve or reject a promise with them.
@objc public class ZktlsBridge: NSObject {
  private var sessions: [String: ZktlsClient] = [:]
  // One lifecycle per session, on the client's own handle, as the SDK's sample
  // wires it: it holds background time and follows network changes.
  private var lifecycles: [String: ZkTlsLifecycle] = [:]
  private let lock = NSLock()

  // Set by the .mm to receive progress. Args: sessionId, phase string, percent.
  @objc public var onProgress: ((String, String, Int) -> Void)?

  private func client(_ sessionId: String) -> ZktlsClient? {
    lock.lock(); defer { lock.unlock() }
    return sessions[sessionId]
  }

  @objc public func create(
    _ config: NSDictionary,
    completion: @escaping (String?, NSError?) -> Void
  ) {
    let client = ZktlsClient(config: ZktlsBridge.readSessionConfig(config))
    let sessionId = UUID().uuidString
    Task { @MainActor in
      // Registered before the id is handed back so no early phase is missed.
      await client.onProgress { [weak self] phase, percent in
        self?.onProgress?(sessionId, ZktlsBridge.phaseToString(phase), Int(percent))
      }
      register(sessionId, client)
      completion(sessionId, nil)
    }
  }

  // A client for platform packs. It shares the session registry, so cancel and
  // dispose work on it as on any session.
  @objc public func createTree(completion: @escaping (String?, NSError?) -> Void) {
    let client = ZktlsClient()
    let sessionId = UUID().uuidString
    Task { @MainActor in
      await client.onProgress { [weak self] phase, percent in
        // A pack that attests uploads to the attester: hold background time until
        // runTree returns.
        if phase == .attesting { self?.hold(sessionId) }
        self?.onProgress?(sessionId, ZktlsBridge.phaseToString(phase), Int(percent))
      }
      register(sessionId, client)
      completion(sessionId, nil)
    }
  }

  @objc public func runTree(
    _ sessionId: String,
    config: NSDictionary,
    disclosure: NSDictionary,
    completion: @escaping (NSDictionary?, NSError?) -> Void
  ) {
    guard let client = client(sessionId) else {
      return completion(nil, ZktlsBridge.internalError("unknown session"))
    }
    let treeConfig = ZktlsBridge.readTreeRunConfig(config)
    let treeDisclosure = ZktlsBridge.readTreeDisclosure(disclosure)
    Task { @MainActor in
      guard let vc = ZktlsBridge.topViewController() else {
        return completion(nil, ZktlsBridge.internalError("no view controller for the tree WebView"))
      }
      let host = TreeWebViewHost(presentingFrom: vc, disclosure: treeDisclosure)
      defer { release(sessionId) }
      do {
        let summary = try await client.runTree(config: treeConfig, host: host)
        completion(ZktlsBridge.writeTreeSummary(summary), nil)
      } catch {
        completion(nil, ZktlsBridge.mapError(error))
      }
    }
  }

  @objc public func login(
    _ sessionId: String,
    disclosure: NSDictionary?,
    completion: @escaping (NSError?) -> Void
  ) {
    guard let client = client(sessionId) else {
      return completion(ZktlsBridge.internalError("unknown session"))
    }
    Task { @MainActor in
      guard let presenter = ZktlsBridge.makePresenter(disclosure) else {
        return completion(ZktlsBridge.internalError("no view controller for the login WebView"))
      }
      do {
        _ = try await client.login(host: presenter)
        // Only now, since the login page is the user's to take time over. Capture
        // and proof then survive the user leaving the app or changing network.
        hold(sessionId)
        completion(nil)
      } catch {
        completion(ZktlsBridge.mapError(error))
      }
    }
  }

  @objc public func capture(_ sessionId: String, completion: @escaping (NSError?) -> Void) {
    guard let client = client(sessionId) else {
      return completion(ZktlsBridge.internalError("unknown session"))
    }
    Task {
      do {
        _ = try await client.capture()
        completion(nil)
      } catch {
        // SessionLost keeps the login: its recovery is another capture.
        if case .SessionLost? = error as? SdkError {} else { release(sessionId) }
        completion(ZktlsBridge.mapError(error))
      }
    }
  }

  @objc public func prove(
    _ sessionId: String,
    completion: @escaping (NSDictionary?, NSError?) -> Void
  ) {
    guard let client = client(sessionId) else {
      return completion(nil, ZktlsBridge.internalError("unknown session"))
    }
    Task {
      do {
        let report = try await client.prove()
        // A rejected proof ends the session: there is no claim to fetch.
        if !report.accepted { release(sessionId) }
        completion(ZktlsBridge.writeProofReport(report), nil)
      } catch {
        release(sessionId)
        completion(nil, ZktlsBridge.mapError(error))
      }
    }
  }

  @objc public func claim(
    _ sessionId: String,
    completion: @escaping (NSDictionary?, NSError?) -> Void
  ) {
    guard let client = client(sessionId) else {
      return completion(nil, ZktlsBridge.internalError("unknown session"))
    }
    Task {
      defer { release(sessionId) }
      do {
        let claim = try await client.claim()
        completion(ZktlsBridge.writeClaim(claim), nil)
      } catch {
        completion(nil, ZktlsBridge.mapError(error))
      }
    }
  }

  // Synchronous on purpose: it must reach a verb in flight. cancel() is
  // nonisolated on the client, so no await.
  @objc public func cancel(_ sessionId: String) {
    client(sessionId)?.cancel()
  }

  // Drops the client so its native handles are released.
  @objc public func dispose(_ sessionId: String, completion: @escaping (NSError?) -> Void) {
    release(sessionId)
    lock.lock()
    sessions.removeValue(forKey: sessionId)
    lifecycles.removeValue(forKey: sessionId)
    lock.unlock()
    completion(nil)
  }

  // MARK: - Session lifecycle

  // UIApplication is main-actor state, so the lifecycle is made there.
  @MainActor
  private func register(_ sessionId: String, _ client: ZktlsClient) {
    let lifecycle = ZkTlsLifecycle(host: UIApplication.shared, handle: client.lifecycleHandle)
    lifecycle.onExpiry = { client.cancel() }  // iOS ended our background time
    lock.lock()
    sessions[sessionId] = client
    lifecycles[sessionId] = lifecycle
    lock.unlock()
  }

  // Idempotent, like the lifecycle's own begin and end.
  private func hold(_ sessionId: String) {
    lock.lock(); let lifecycle = lifecycles[sessionId]; lock.unlock()
    lifecycle?.begin()
  }

  private func release(_ sessionId: String) {
    lock.lock(); let lifecycle = lifecycles[sessionId]; lock.unlock()
    lifecycle?.end()
  }

  // MARK: - Login presenter

  @MainActor
  private static func makePresenter(_ disclosure: NSDictionary?) -> WebViewLoginPresenter? {
    guard let vc = topViewController() else { return nil }
    if let disclosure = disclosure {
      return WebViewLoginPresenter(presentingFrom: vc) { domains in readDisclosure(disclosure, domains) }
    }
    return WebViewLoginPresenter(presentingFrom: vc)
  }

  @MainActor
  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first
    let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: - Conversions

  private static func readSessionConfig(_ d: NSDictionary) -> SessionConfig {
    func s(_ k: String) -> String { d[k] as? String ?? "" }
    return SessionConfig(
      baseUrl: s("baseUrl"),
      appCredential: s("appCredential"),
      userIdHash: s("userIdHash"),
      profileId: s("profileId"),
      policyId: s("policyId"),
      idempotencyKey: s("idempotencyKey"),
      clientRegion: s("clientRegion"),
      networkKey: s("networkKey"),
      trustBundleJson: s("trustBundleJson"),
      trustBundleUrl: s("trustBundleUrl"),
      trustOperatorKey: s("trustOperatorKey"),
      policyBundleJson: s("policyBundleJson"),
      policyBundleDigest: s("policyBundleDigest")
    )
  }

  // A field left out keeps the SDK's standard text for the login's cookie domains.
  private static func readDisclosure(_ d: NSDictionary, _ domains: [String]) -> LoginDisclosure {
    var disclosure = LoginDisclosure.standard(domains: domains)
    if let v = d["title"] as? String { disclosure.title = v }
    if let v = d["message"] as? String { disclosure.message = v }
    if let v = d["accept"] as? String { disclosure.accept = v }
    if let v = d["decline"] as? String { disclosure.decline = v }
    return disclosure
  }

  private static func readTreeRunConfig(_ d: NSDictionary) -> TreeRunConfig {
    func s(_ k: String) -> String { d[k] as? String ?? "" }
    return TreeRunConfig(
      baseUrl: s("baseUrl"),
      appCredential: s("appCredential"),
      userIdHash: s("userIdHash"),
      idempotencyKey: s("idempotencyKey"),
      clientRegion: s("clientRegion"),
      networkKey: s("networkKey"),
      platformId: s("platformId"),
      trustBundleJson: s("trustBundleJson"),
      trustBundleUrl: s("trustBundleUrl"),
      trustOperatorKey: s("trustOperatorKey"),
      policyBundleJson: s("policyBundleJson"),
      policyBundleDigest: s("policyBundleDigest"),
      relyingPartyNonceHex: s("relyingPartyNonceHex"),
      resultUrl: s("resultUrl"),
      resultToken: s("resultToken"),
      paramsJson: s("paramsJson")
    )
  }

  private static func readTreeDisclosure(_ d: NSDictionary) -> TreeDisclosure {
    func s(_ k: String) -> String { d[k] as? String ?? "" }
    return TreeDisclosure(
      title: s("title"),
      message: s("message"),
      accept: s("accept"),
      decline: s("decline")
    )
  }

  private static func phaseToString(_ phase: Phase) -> String {
    switch phase {
    case .loggingIn: return "loggingIn"
    case .collecting: return "collecting"
    case .attesting: return "attesting"
    case .detached: return "detached"
    case .allocating: return "allocating"
    case .capturing: return "capturing"
    case .captured: return "captured"
    case .proving: return "proving"
    case .proved: return "proved"
    case .claiming: return "claiming"
    case .done: return "done"
    case .failed: return "failed"
    }
  }

  // The u64 fields cross as strings: JS numbers lose integer precision above
  // 2^53, so the JS side re-parses the exact decimal.
  private static func writeProofReport(_ r: ProofReport) -> NSDictionary {
    return [
      "accepted": r.accepted,
      "verdict": r.verdict,
      "nullifierHex": r.nullifierHex,
      "encodedClaim": r.encodedClaim,
      "proveMs": String(r.proveMs),
      "sentBytes": String(r.sentBytes),
      "receivedBytes": String(r.receivedBytes),
    ]
  }

  private static func writeClaim(_ c: Claim) -> NSDictionary {
    return [
      "outputs": c.outputs.map { writeTypedOutput($0) },
      "nullifierHex": c.nullifierHex,
      "profileId": c.profileId,
      "policyId": c.policyId,
      "verifierEpoch": Int(c.verifierEpoch),
      "issuedAt": String(c.issuedAt),
      "expiresAt": String(c.expiresAt),
      "signatureHex": c.signatureHex,
      "encoded": c.encoded,
    ]
  }

  private static func writeTypedOutput(_ o: TypedOutput) -> NSDictionary {
    return ["name": o.name, "valueJson": o.valueJson]
  }

  // claim is always null: the attester posts a pack's claim to the backend
  // itself. NSNull crosses as JS null.
  private static func writeTreeSummary(_ s: TreeSummary) -> NSDictionary {
    let claim: Any
    if let c = s.claim { claim = writeClaim(c) } else { claim = NSNull() }
    return [
      "succeeded": s.succeeded,
      "error": s.error,
      "sources": s.sources.map { writeTreeSource($0) },
      "claim": claim,
      "apiCalls": Int(s.apiCalls),
      "durationMs": String(s.durationMs),
      "delivered": s.delivered,
      "deliveryError": s.deliveryError,
      "resultBytes": String(s.resultBytes),
      "isolation": s.isolation,
      "handedOff": s.handedOff,
    ]
  }

  private static func writeTreeSource(_ t: TreeSource) -> NSDictionary {
    let evidence: String
    switch t.evidence {
    case .observed: evidence = "observed"
    case .attested: evidence = "attested"
    }
    return [
      "storeAs": t.storeAs,
      "evidence": evidence,
      "rows": String(t.rows),
      "pages": Int(t.pages),
      "bytes": String(t.bytes),
      "complete": t.complete,
    ]
  }

  // MARK: - Errors

  // Maps every SdkError to the code JS matches on (see SdkErrorCode in
  // index.tsx). Transport and Policy carry their text; anything else is Internal.
  private static func mapError(_ error: Error) -> NSError {
    guard let e = error as? SdkError else {
      return zktlsError("Internal", (error as NSError).localizedDescription)
    }
    switch e {
    case .NotLoggedIn: return zktlsError("NotLoggedIn", nil)
    case .SessionLost: return zktlsError("SessionLost", nil)
    case .Cancelled: return zktlsError("Cancelled", nil)
    case .WrongEvidence: return zktlsError("WrongEvidence", nil)
    case .Truncated: return zktlsError("Truncated", nil)
    case .ExtraResponse: return zktlsError("ExtraResponse", nil)
    case .Reordered: return zktlsError("Reordered", nil)
    case .LimitExceeded: return zktlsError("LimitExceeded", nil)
    case .InsufficientMemory: return zktlsError("InsufficientMemory", nil)
    case .Transport(let text): return zktlsError("Transport", text)
    case .Policy(let text): return zktlsError("Policy", text)
    }
  }

  private static func internalError(_ message: String) -> NSError {
    return zktlsError("Internal", message)
  }

  // The .mm reads userInfo["code"] for the JS error code and userInfo["text"]
  // for the Transport/Policy message.
  private static func zktlsError(_ code: String, _ text: String?) -> NSError {
    var info: [String: Any] = ["code": code]
    if let text = text { info["text"] = text }
    return NSError(domain: "Zktls", code: 0, userInfo: info)
  }
}
