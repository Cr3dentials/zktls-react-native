import Native from './NativeZktlsReactNative';
import type {
  SessionConfig,
  Disclosure,
  Claim,
  TypedOutput,
  ProofReport,
} from './NativeZktlsReactNative';

export type { SessionConfig, Disclosure, Claim, TypedOutput, ProofReport };

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
// these as `code`; Transport and Policy also carry `text`. Internal is a fault
// inside the SDK that was not an SdkError.
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
  text?: string;
}

// The listener handle onProgress returns; call remove() to stop listening.
export interface Subscription {
  remove(): void;
}

// One instance per session, mirroring the native ZktlsClient. The native side
// owns the real client and its opaque handles; this holds only the session id.
// The flow is login -> capture -> prove -> claim; the SDK never retries and
// neither should you. Call dispose() on every terminal path.
export class ZktlsClient {
  private constructor(public readonly sessionId: string) {}

  static async create(config: SessionConfig): Promise<ZktlsClient> {
    const sessionId = await Native.create(config);
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
