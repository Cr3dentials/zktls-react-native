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

// phase is one of the Phase strings (see index.tsx); percent is 0..100.
export interface ProgressEvent {
  sessionId: string;
  phase: string;
  percent: number;
}

export interface Spec extends TurboModule {
  // Builds a native ZktlsClient(config) and returns its session id. Every other
  // call is keyed by that id; the native side keeps the client and its handles.
  create(config: SessionConfig): Promise<string>;

  // Shows the disclosure, then the profile's login page in the SDK's WebView,
  // and keeps the resulting cookies natively.
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
