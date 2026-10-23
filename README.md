# zktls-react-native

Prove a fact from a user's own account, such as a completed payment, without the account data leaving
their phone, or run a platform pack, from a React Native app. This package is a thin bridge over the
[zkTLS SDK](https://github.com/Cr3dentials/zktls-sdk-releases): the native SDK does the work, and
JavaScript drives it through one API on both platforms.

| | iOS | Android |
|---|---|---|
| Minimum OS | React Native's minimum, and at least iOS 14.0 for the SDK | Android 7.0 (API 24) |
| The native SDK | The `ZktlsSDK` pod, from [zktls-sdk-releases](https://github.com/Cr3dentials/zktls-sdk-releases) | `xyz.cr3dentials:zktls-sdk:1.0.0`, from Maven Central |

The SDK's own guides hold the details this page links to: start with its
[partner integration checklist](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/partner-checklist.md).

## Requirements

React Native 0.80 or later, with the New Architecture: the bridge is a Turbo Module. Android 7.0 (API 24)
or later. On iOS, the SDK needs iOS 14.0 or later.

## Install

```sh
npm install @cr3dentials-org/zktls-react-native
```

Android needs nothing more: Gradle fetches the SDK from Maven Central. On iOS the SDK's releases repository
is its own CocoaPods spec source, and CocoaPods takes a pod from the first source that has it, so list it
first in your `Podfile`, then run `pod install`:

```ruby
source 'https://github.com/Cr3dentials/zktls-sdk-releases.git'
source 'https://cdn.cocoapods.org/'
```

## What you need from us

The same as for a native app: your app credential, the profile and policy ids, the front door URL
(`baseUrl`), the trust bundle's URL and the operator key to pin, and the policy bundle's URL and digest.
Pin the keys in your app, fetch the bundles yourself, and pass the trust bundle's URL as
`trustBundleUrl`. The SDK's iOS guide explains why
([what you need from us](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/integration-ios.md#what-you-need-from-us)).

## Build the session's configuration

One `SessionConfig` per session the user starts, with the native SDK's fields and rules: see the
[field table](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/integration-ios.md#build-the-sessions-configuration).
`idempotencyKey` is new for every session, and `networkKey` never leaves the device.

```ts
const config: SessionConfig = {
  baseUrl: frontDoor, appCredential: credential, userIdHash: hash(userId),
  profileId, policyId,
  idempotencyKey: uuid(), // new for every session
  clientRegion: country ?? '', networkKey: 'default',
  trustBundleJson: trustBundle, trustBundleUrl, trustOperatorKey: operatorKey,
  policyBundleJson: policyBundle, policyBundleDigest,
};
```

## Run a session

```ts
import { ZktlsClient, type ZktlsError } from '@cr3dentials-org/zktls-react-native';

async function prove(config: SessionConfig) {
  const client = await ZktlsClient.create(config); // one client per session the user starts
  const progress = client.onProgress((e) => setProgress(e.phase, e.percent));
  try {
    await client.login(); // the disclosure, then the page
    await client.capture();
    const report = await client.prove();
    if (!report.accepted) return show(`Not proven: ${report.verdict}`);
    const claim = await client.claim(); // verified against the trust bundle
    await send(claim.encoded); // your backend verifies it again
  } catch (e) {
    show(message(e as ZktlsError)); // never retry automatically
  } finally {
    progress.remove();
    await client.dispose(); // every path
  }
}
```

`setProgress`, `show`, `send` and `message` are yours. The bridge keeps the session alive in the
background itself: you start no lifecycle or service.

## The claim, and your backend

`claim()` returns a `Claim` the SDK has verified against the trust bundle. Your backend cannot trust the
app, so send it `claim.encoded` and have it verify the claim itself:
[verifying a claim on your backend](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/backend-verification.md).
`issuedAt`, `expiresAt` and the proof report's byte counts are strings: JavaScript numbers lose
precision above 2^53.

## Platform packs

`ZktlsClient.createTree()` makes a client for platform packs, and `runTree(config, disclosure)` runs one:
the SDK shows your disclosure, opens the platform's own sign-in page and collects in the page. The data
reaches your backend at the run's `resultUrl`, posted by the SDK or, for a pack that attests, by the
attester; the app gets a `TreeSummary` with each source's counts only. A tree client has no
`SessionConfig`, so the proof verbs on it fail.

```ts
const client = await ZktlsClient.createTree();
try {
  const summary = await client.runTree(config, disclosure); // config: a TreeRunConfig your backend issued
} finally {
  await client.dispose();
}
```

Your backend creates the run and receives its result:
[platform packs and runTree](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/integration-packs.md)
and [receiving a tree run's result](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/backend-tree-results.md).

## Things to know

- **The disclosure.** `login()` shows the SDK's standard disclosure before the page, every time. Pass
  `login({ title, message, accept, decline })` to translate it; a field you leave out keeps the standard
  text. Keep every fact the standard text states
  ([store review](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/store-review.md)).
- **The witness never reaches your code.** It stays in the native SDK, as do the cookies and every other
  handle: JavaScript only ever holds a session id.
- **Cancelling.** `cancel()` ends the verb in flight with `Cancelled`, and closes the login page if it is
  open. Call `dispose()` on every path, so the native client is released.
- **Background.** The bridge does what the SDK's guides ask of a native app. After `login`, and while a
  pack's run is with the attester, it follows Wi-Fi and cellular handovers and keeps the session alive
  when the user leaves the app: a short foreground service on Android, background time on iOS. When
  Android or iOS ends that time, the session is cancelled. A capture that fails with `SessionLost` keeps
  it, since another capture recovers it.
- **The notification.** On Android that service shows a notification reading "Verifying", in a channel
  named "Verification". Define `zktls_session_notification_title`, `zktls_session_channel_name` and the
  drawable `zktls_session_notification_icon` in your app's resources to translate or rebrand it.
- **One session at a time.** Android's service holds one session. A second session that starts while the
  first holds it goes on without it.
- **Cookies and web storage.** On Android the login clears the process's cookies, web storage and
  WebView cache before and after, so do not run a login while your own WebViews' cookies matter.
- **Errors.** A failed verb rejects with an `Error` whose `code` is an `SdkErrorCode`
  ([errors](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/errors.md)). For
  `Transport` and `Policy`, `message` carries the SDK's text. `Internal` is a fault inside the SDK that
  was not one of its errors: report it.
- **Logging.** Log error codes and that text only. Never log a `SessionConfig`: it holds the app credential.

## Before you submit

Work through the SDK's
[partner integration checklist](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/partner-checklist.md):
privacy answers, export compliance, the foreground service, and a test account for review.

## The example app

`example/` runs on both platforms. Its "Test bridge" button exercises the round-trips that need no live
backend. Its "Run a platform pack" button runs a pack against a lab once `example/src/labSettings.ts` is
filled from pack-lab's `tree.json`; that file is committed empty and holds a credential once filled, so
never commit it filled.

## Versions

Releases follow [Semantic Versioning](https://semver.org/). The bridge depends on the SDK `~> 1.0`.

## License

[Apache-2.0](LICENSE). The SDK's own license and the open-source notices of its compiled core are in the
[zktls-sdk-releases](https://github.com/Cr3dentials/zktls-sdk-releases) repository.
