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
    Task {
      // Registered before the id is handed back so no early phase is missed.
      await client.onProgress { [weak self] phase, percent in
        self?.onProgress?(sessionId, ZktlsBridge.phaseToString(phase), Int(percent))
      }
      lock.lock(); sessions[sessionId] = client; lock.unlock()
      completion(sessionId, nil)
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
        completion(ZktlsBridge.writeProofReport(report), nil)
      } catch {
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
    lock.lock(); sessions.removeValue(forKey: sessionId); lock.unlock()
    completion(nil)
  }

  // MARK: - Login presenter

  @MainActor
  private static func makePresenter(_ disclosure: NSDictionary?) -> WebViewLoginPresenter? {
    guard let vc = topViewController() else { return nil }
    if let disclosure = disclosure {
      return WebViewLoginPresenter(presentingFrom: vc) { _ in readDisclosure(disclosure) }
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

  private static func readDisclosure(_ d: NSDictionary) -> LoginDisclosure {
    func s(_ k: String) -> String { d[k] as? String ?? "" }
    return LoginDisclosure(
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
