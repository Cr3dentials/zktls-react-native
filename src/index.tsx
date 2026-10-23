import Native from './NativeZktlsReactNative';
import type {
  SessionConfig,
  Disclosure,
  Claim,
  TypedOutput,
  ProofReport,
  TreeRunConfig,
  TreeDisclosure,
  TreeSource as NativeTreeSource,
  TreeSummary as NativeTreeSummary,
} from './NativeZktlsReactNative';

export type {
  SessionConfig,
  Disclosure,
  Claim,
  TypedOutput,
  ProofReport,
  TreeRunConfig,
  TreeDisclosure,
};

// The native SourceEvidence, lowercased: observed in the page, or attested.
export type SourceEvidence = 'observed' | 'attested';

export interface TreeSource extends Omit<NativeTreeSource, 'evidence'> {
  evidence: SourceEvidence;
}

export interface TreeSummary extends Omit<NativeTreeSummary, 'sources'> {
  sources: TreeSource[];
}

// The native Phase enum, lowercased. Carried as a string across the bridge and
// narrowed to this union here.
export type Phase =
  | 'loggingIn'
  | 'collecting'
  | 'attesting'
  | 'detached'
  | 'allocating'
  | 'capturing'
  | 'captured'
  | 'proving'
  | 'proved'
  | 'claiming'
  | 'done'
  | 'failed';

export interface ProgressEvent {
  sessionId: string;
  phase: Phase;
  percent: number;
}

// The native SdkError/SdkException variants. A rejected verb carries one of
// these as `code`; for Transport and Policy, `message` carries the SDK's text.
// Internal is a fault inside the SDK that was not an SdkError.
export type SdkErrorCode =
  | 'NotLoggedIn'
  | 'SessionLost'
  | 'Cancelled'
  | 'WrongEvidence'
  | 'Truncated'
  | 'ExtraResponse'
  | 'Reordered'
  | 'LimitExceeded'
  | 'InsufficientMemory'
  | 'Transport'
  | 'Policy'
  | 'Internal';

export interface ZktlsError extends Error {
  code: SdkErrorCode;
}

// The listener handle onProgress returns; call remove() to stop listening.
export interface Subscription {
  remove(): void;
}

// One instance per session, mirroring the native ZktlsClient. The native side
// owns the real client and its opaque handles; this holds only the session id.
// The flow is login -> capture -> prove -> claim, or a single runTree on a client
// from createTree(); the SDK never retries and neither should you. Call
// dispose() on every terminal path.
export class ZktlsClient {
  private constructor(public readonly sessionId: string) {}

  static async create(config: SessionConfig): Promise<ZktlsClient> {
    const sessionId = await Native.create(config);
    return new ZktlsClient(sessionId);
  }

  // A client for platform packs: no SessionConfig, each run takes its own config.
  static async createTree(): Promise<ZktlsClient> {
    const sessionId = await Native.createTree();
    return new ZktlsClient(sessionId);
  }

  login(disclosure?: Disclosure): Promise<void> {
    return Native.login(this.sessionId, disclosure);
  }

  capture(): Promise<void> {
    return Native.capture(this.sessionId);
  }

  prove(): Promise<ProofReport> {
    return Native.prove(this.sessionId);
  }

  claim(): Promise<Claim> {
    return Native.claim(this.sessionId);
  }

  // The app gets a summary only; the data goes to config.resultUrl.
  runTree(
    config: TreeRunConfig,
    disclosure: TreeDisclosure
  ): Promise<TreeSummary> {
    return Native.runTree(
      this.sessionId,
      config,
      disclosure
    ) as Promise<TreeSummary>;
  }

  cancel(): void {
    Native.cancel(this.sessionId);
  }

  dispose(): Promise<void> {
    return Native.dispose(this.sessionId);
  }

  // Fires for this session's phase changes only. Events for other sessions are
  // filtered out here.
  onProgress(listener: (event: ProgressEvent) => void): Subscription {
    return Native.onProgress((event) => {
      if (event.sessionId !== this.sessionId) return;
      listener({
        sessionId: event.sessionId,
        phase: event.phase as Phase,
        percent: event.percent,
      });
    });
  }
}
