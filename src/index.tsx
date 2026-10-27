import Native from './NativeZktlsReactNative';
import type {
  SessionConfig,
  Disclosure,
  Claim,
  TypedOutput,
  ProofReport,
  ZktlsTheme,
  PlatformOutcome as NativePlatformOutcome,
  VerifyOutcome as NativeVerifyOutcome,
} from './NativeZktlsReactNative';

export type {
  SessionConfig,
  Disclosure,
  Claim,
  TypedOutput,
  ProofReport,
  ZktlsTheme,
};

// The native PlatformStatus, lowercased.
export type PlatformStatus = 'done' | 'failed' | 'notStarted';

export interface PlatformOutcome extends Omit<NativePlatformOutcome, 'status'> {
  status: PlatformStatus;
}

export interface VerifyOutcome extends Omit<NativeVerifyOutcome, 'platforms'> {
  platforms: PlatformOutcome[];
}

// The native Phase enum, lowercased. Carried as a string across the bridge and
// narrowed to this union here. A proof session reports the proof phases; the
// others are the native enum's too.
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

// The native SdkError/SdkException variants, and two of the bridge's own. A
// rejected call carries one of these as `code`; for Transport, Policy and
// Refused, `message` carries the SDK's text. InvalidArgument is configure given
// a theme color or a screen string it cannot use; its message names the field.
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
  | 'Refused'
  | 'InvalidArgument'
  | 'Internal';

export interface ZktlsError extends Error {
  code: SdkErrorCode;
  // For Refused: why the verification did not start, such as
  // 'device_not_verified' or 'app_key_invalid'.
  refusal?: string;
}

// A Refused rejection carries its refusal code in userInfo.
function withRefusal(e: unknown): never {
  const err = e as ZktlsError & { userInfo?: { refusal?: string } };
  if (err && err.code === 'Refused') err.refusal = err.userInfo?.refusal;
  throw err;
}

// The SDK: configure once, when the app starts, then verify per user. verify
// shows the SDK's own screens, runs each platform, and resolves with how each
// platform ended; your server gets the data in signed webhooks.
export const Zktls = {
  configure(
    appKey: string,
    theme?: ZktlsTheme,
    strings?: Record<string, string>
  ): Promise<void> {
    // Always an object: iOS reads an absent theme through a null reference.
    return Native.configure(appKey, theme ?? {}, strings);
  },

  verify(platforms: string[], reference: string): Promise<VerifyOutcome> {
    return (
      Native.verify(platforms, reference) as Promise<VerifyOutcome>
    ).catch(withRefusal);
  },

  verifyToken(token: string): Promise<VerifyOutcome> {
    return (Native.verifyToken(token) as Promise<VerifyOutcome>).catch(
      withRefusal
    );
  },
};

// The listener handle onProgress returns; call remove() to stop listening.
export interface Subscription {
  remove(): void;
}

// One instance per proof session, mirroring the native ZktlsClient. The native
// side owns the real client and its opaque handles; this holds only the session
// id. The flow is login -> capture -> prove -> claim; the SDK never retries and
// neither should you. Call dispose() on every terminal path.
export class ZktlsClient {
  private constructor(public readonly sessionId: string) {}

  static async create(config: SessionConfig): Promise<ZktlsClient> {
    const sessionId = await Native.create(config);
    return new ZktlsClient(sessionId);
  }

  login(disclosure?: Disclosure): Promise<void> {
    // Always an object, as configure's theme: an empty one keeps the standard text.
    return Native.login(this.sessionId, disclosure ?? {});
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
