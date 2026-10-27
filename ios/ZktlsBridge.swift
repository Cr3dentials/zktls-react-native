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
  // The verifications in flight, so invalidate can cancel them.
  private var verifications: [UUID: Task<Void, Never>] = [:]
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

  // The SDK's facade: configure once, then verify per user. verify shows the
  // SDK's own screens over the key window's top view controller and holds its
  // own background time, so it needs none of the proof sessions' lifecycle here.
  // A theme color or a screen string it cannot use rejects with InvalidArgument
  // and leaves the SDK's configuration as it was.
  @objc public func configure(
    _ appKey: String,
    theme: NSDictionary?,
    strings: NSDictionary?,
    completion: @escaping (NSError?) -> Void
  ) {
    Task { @MainActor in
      do {
        let sdkTheme = try ZktlsBridge.readTheme(theme)
        let sdkStrings = try ZktlsBridge.readStrings(strings)
        Zktls.configure(appKey: appKey, theme: sdkTheme, strings: sdkStrings)
        completion(nil)
      } catch {
        completion(error as NSError)
      }
    }
  }

  @objc public func verify(
    _ platforms: [String],
    reference: String,
    completion: @escaping (NSDictionary?, NSError?) -> Void
  ) {
    runVerification(completion) { try await Zktls.verify(platforms, reference: reference) }
  }

  @objc public func verifyToken(_ token: String, completion: @escaping (NSDictionary?, NSError?) -> Void) {
    runVerification(completion) { try await Zktls.verify(token: token) }
  }

  // Cancels every verification in flight, when the module goes away: the SDK
  // takes its screens down and each one's promise rejects with Cancelled.
  @objc public func invalidate() {
    lock.lock()
    let running = Array(verifications.values)
    verifications.removeAll()
    lock.unlock()
    running.forEach { $0.cancel() }
  }

  // Runs one verification on the main actor, kept until it ends so invalidate
  // can cancel it.
  private func runVerification(
    _ completion: @escaping (NSDictionary?, NSError?) -> Void,
    _ run: @escaping @MainActor () async throws -> VerifyOutcome
  ) {
    let id = UUID()
    lock.lock()
    defer { lock.unlock() }
    verifications[id] = Task { @MainActor [weak self] in
      do {
        let outcome = try await run()
        completion(ZktlsBridge.writeVerifyOutcome(outcome), nil)
      } catch {
        completion(nil, ZktlsBridge.mapError(error))
      }
      self?.verificationEnded(id)
    }
  }

  private func verificationEnded(_ id: UUID) {
    lock.lock()
    verifications.removeValue(forKey: id)
    lock.unlock()
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

  // The screens' theme. A color is "#RRGGBB" or "#AARRGGBB"; the logo is an
  // image asset's name in the app. A field left out keeps the SDK's default, so
  // an empty dictionary is the SDK's own look. A color in any other form throws.
  @MainActor
  private static func readTheme(_ d: NSDictionary?) throws -> ZktlsTheme {
    var theme = ZktlsTheme()
    guard let d = d else { return theme }
    if let c = try themeColor(d, "accent") { theme.accent = c }
    if let c = try themeColor(d, "background") { theme.background = c }
    if let c = try themeColor(d, "text") { theme.text = c }
    if let name = d["logo"] as? String { theme.logo = UIImage(named: name) }
    return theme
  }

  // The theme's color `field`, nil when it is left out. Android rejects the same
  // values with the same message.
  private static func themeColor(_ d: NSDictionary, _ field: String) throws -> UIColor? {
    guard let value = d[field], !(value is NSNull) else { return nil }
    guard let hex = value as? String, let c = color(hex) else {
      throw zktlsError("InvalidArgument", "theme.\(field) must be #RRGGBB or #AARRGGBB")
    }
    return c
  }

  // Exactly "#RRGGBB" (opaque) or "#AARRGGBB", hex digits in either case; nil
  // for anything else, color names included.
  private static func color(_ hex: String) -> UIColor? {
    guard hex.hasPrefix("#") else { return nil }
    let digits = hex.dropFirst()
    guard digits.count == 6 || digits.count == 8,
      digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
      let v = UInt32(digits, radix: 16)
    else { return nil }
    let argb = digits.count == 6 ? (0xFF00_0000 | v) : v
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }

  // The screens' words, by key. A null value is left out; any other value that
  // is not a string throws, as on Android.
  private static func readStrings(_ d: NSDictionary?) throws -> [String: String] {
    var out: [String: String] = [:]
    guard let d = d else { return out }
    for (key, value) in d {
      guard let k = key as? String, !(value is NSNull) else { continue }
      guard let v = value as? String else {
        throw zktlsError("InvalidArgument", "strings[\"\(k)\"] must be a string")
      }
      out[k] = v
    }
    return out
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

  // A platform's reason is nil unless it failed; NSNull crosses as JS null.
  private static func writeVerifyOutcome(_ o: VerifyOutcome) -> NSDictionary {
    return [
      "verificationId": o.verificationId,
      "platforms": o.platforms.map { p -> NSDictionary in
        let status: String
        switch p.status {
        case .done: status = "done"
        case .failed: status = "failed"
        case .notStarted: status = "notStarted"
        }
        return [
          "platform": p.platform,
          "status": status,
          "reason": p.reason.map { $0 as Any } ?? NSNull(),
        ]
      },
    ]
  }

  // MARK: - Errors

  // Maps every SdkError to the code JS matches on (see SdkErrorCode in
  // index.tsx). Transport, Policy and Refused carry their text; anything else is
  // Internal. The bridge's own InvalidArgument is made by zktlsError directly.
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
    case .Refused(let code, let message): return zktlsError("Refused", message, refusal: code)
    }
  }

  private static func internalError(_ message: String) -> NSError {
    return zktlsError("Internal", message)
  }

  // The .mm reads userInfo["code"] for the JS error code and userInfo["text"]
  // for the Transport/Policy/Refused/InvalidArgument message; React Native hands userInfo to
  // JS, where index.tsx reads a Refused error's userInfo["refusal"].
  private static func zktlsError(_ code: String, _ text: String?, refusal: String? = nil) -> NSError {
    var info: [String: Any] = ["code": code]
    if let text = text { info["text"] = text }
    if let refusal = refusal { info["refusal"] = refusal }
    return NSError(domain: "Zktls", code: 0, userInfo: info)
  }
}
