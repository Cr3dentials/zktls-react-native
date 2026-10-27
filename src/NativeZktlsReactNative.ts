import type { TurboModule, CodegenTypes } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

// This is the codegen spec: only types the RN codegen understands (objects as
// interfaces, arrays, string/number/boolean, Promise, EventEmitter). Richer
// types (the Phase union, error codes) live in the public API in index.tsx,
// which wraps this. u64 values are strings so no precision is lost across the
// bridge; u32 and percent stay numbers.

// One per session. All strings; mirrors the native SessionConfig field for field.
export interface SessionConfig {
  baseUrl: string;
  appCredential: string;
  userIdHash: string;
  profileId: string;
  policyId: string;
  idempotencyKey: string;
  clientRegion: string;
  networkKey: string;
  trustBundleJson: string;
  // Optional: where the SDK refetches the trust bundle once when an enclave's key is not listed yet.
  trustBundleUrl?: string;
  trustOperatorKey: string;
  policyBundleJson: string;
  policyBundleDigest: string;
}

// The consent screen shown before the login page. Every field optional: any
// left out keeps the SDK's standard text for the profile's domains.
export interface Disclosure {
  title?: string;
  message?: string;
  accept?: string;
  decline?: string;
}

export interface TypedOutput {
  name: string;
  valueJson: string;
}

export interface Claim {
  outputs: TypedOutput[];
  nullifierHex: string;
  profileId: string;
  policyId: string;
  verifierEpoch: number; // u32
  issuedAt: string; // u64 unix seconds
  expiresAt: string; // u64 unix seconds
  signatureHex: string;
  encoded: string;
}

export interface ProofReport {
  accepted: boolean;
  verdict: string;
  nullifierHex: string;
  encodedClaim: string;
  proveMs: string; // u64
  sentBytes: string; // u64
  receivedBytes: string; // u64
}

// The look of the SDK's own screens, for configure; the native SDK's name. Every
// field optional: one left out keeps the SDK's default. Colors are "#RRGGBB" or
// "#AARRGGBB" (hex digits in either case); anything else rejects configure with
// InvalidArgument. logo names an image in the app, an Android drawable or an iOS
// asset.
export interface ZktlsTheme {
  accent?: string;
  background?: string;
  text?: string;
  logo?: string;
}

// How one platform ended. status is 'done', 'failed' or 'notStarted'; reason is
// set for a failure.
export interface PlatformOutcome {
  platform: string;
  status: string;
  reason?: string | null;
}

// What verify returns: never the platform's data, which goes to your server in a
// signed webhook.
export interface VerifyOutcome {
  verificationId: string;
  platforms: PlatformOutcome[];
}

// phase is one of the Phase strings (see index.tsx); percent is 0..100.
export interface ProgressEvent {
  sessionId: string;
  phase: string;
  percent: number;
}

export interface Spec extends TurboModule {
  // Sets the app's publishable key, zk_live_... or zk_test_..., and the look and
  // words of the SDK's screens. strings maps a screen string's key to its text.
  // index.tsx always passes a theme object: on iOS an absent struct argument
  // reaches the module as a null reference.
  configure(
    appKey: string,
    theme?: ZktlsTheme,
    strings?: CodegenTypes.UnsafeObject
  ): Promise<void>;

  // Verifies the platforms (our ids, run in this order) for one user, under the
  // app's reference, with the SDK's own screens over the current activity or
  // view controller. Resolves once the user leaves the flow.
  verify(platforms: string[], reference: string): Promise<VerifyOutcome>;

  // As verify, for the platforms and reference a token from your server carries.
  verifyToken(token: string): Promise<VerifyOutcome>;

  // Builds a native ZktlsClient(config) and returns its session id. Every other
  // call is keyed by that id; the native side keeps the client and its handles.
  create(config: SessionConfig): Promise<string>;

  // Shows the disclosure, then the profile's login page in the SDK's WebView,
  // and keeps the resulting cookies natively. index.tsx always passes a
  // disclosure object, for the reason configure's theme is always passed.
  login(sessionId: string, disclosure?: Disclosure): Promise<void>;

  capture(sessionId: string): Promise<void>;
  prove(sessionId: string): Promise<ProofReport>;
  claim(sessionId: string): Promise<Claim>;

  // Cancels the verb in flight and closes the login page if open.
  cancel(sessionId: string): void;

  // Releases the native client. Call on every terminal path so it is not leaked.
  dispose(sessionId: string): Promise<void>;

  // Every phase change of every live session. Filter by sessionId on the JS side.
  readonly onProgress: CodegenTypes.EventEmitter<ProgressEvent>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('ZktlsReactNative');
