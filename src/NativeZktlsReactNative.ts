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

// One per tree run. All strings; mirrors the native TreeRunConfig field for field.
export interface TreeRunConfig {
  baseUrl: string;
  appCredential: string;
  userIdHash: string;
  idempotencyKey: string;
  clientRegion: string;
  networkKey: string;
  platformId: string;
  trustBundleJson: string;
  trustBundleUrl?: string;
  trustOperatorKey: string;
  policyBundleJson: string;
  policyBundleDigest: string;
  relyingPartyNonceHex: string;
  resultUrl: string;
  resultToken: string;
  paramsJson: string;
}

// The consent screen shown before the platform's pages open. All required.
export interface TreeDisclosure {
  title: string;
  message: string;
  accept: string;
  decline: string;
}

export interface TreeSource {
  storeAs: string;
  evidence: string; // 'observed' | 'attested'
  rows: string; // u64
  pages: number; // u32
  bytes: string; // u64
  complete: boolean;
}

export interface TreeSummary {
  succeeded: boolean;
  error: string;
  sources: TreeSource[];
  claim?: Claim | null;
  apiCalls: number; // u32
  durationMs: string; // u64
  delivered: boolean;
  deliveryError: string;
  resultBytes: string; // u64
  isolation: string;
  handedOff: boolean;
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

  // Builds a native ZktlsClient() for tree runs and returns its session id.
  createTree(): Promise<string>;

  // Shows the disclosure, then runs the platform's pack in the SDK's WebView.
  runTree(
    sessionId: string,
    config: TreeRunConfig,
    disclosure: TreeDisclosure
  ): Promise<TreeSummary>;

  // Cancels the verb in flight and closes the login page if open.
  cancel(sessionId: string): void;

  // Releases the native client. Call on every terminal path so it is not leaked.
  dispose(sessionId: string): Promise<void>;

  // Every phase change of every live session. Filter by sessionId on the JS side.
  readonly onProgress: CodegenTypes.EventEmitter<ProgressEvent>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('ZktlsReactNative');
