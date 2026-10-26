# zktls-react-native

Verify your users' accounts from a React Native app with the [Cr3dentials zkTLS SDK](https://docs.cr3dentials.xyz/sdk/overview):
`Zktls.configure` once, at launch, and `Zktls.verify` per user. The SDK shows its own screens, opens each
platform's sign-in page, and has each result read and signed by a Cr3dentials attester; your server gets
the results in signed webhooks, never through your app. This package is a thin bridge: the native SDK
does the work, and JavaScript drives it through one API on both platforms.

| | iOS | Android |
|---|---|---|
| Minimum OS | React Native's minimum, and at least iOS 14.0 for the SDK | Android 7.0 (API 24) |
| The native SDK | The `ZktlsSDK` pod 2.0.1 or later, from [zktls-sdk-releases](https://github.com/Cr3dentials/zktls-sdk-releases) | `xyz.cr3dentials:zktls-sdk:2.0.1`, from Maven Central |

The SDK's guide holds the details this page links to: start with its
[overview](https://docs.cr3dentials.xyz/sdk/overview).

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

Your app's publishable key, `zk_live_…` or `zk_test_…`, and the platform ids you verify. A test key works on
simulators and emulators and runs only the demo platform, `zktls-demo` (any user name, the password
`demo`). The SDK's guide explains both ([overview](https://docs.cr3dentials.xyz/sdk/overview)).

## Verify a user

```ts
import { Zktls, type ZktlsError } from '@cr3dentials-org/zktls-react-native';

// Once, when your app starts.
await Zktls.configure('zk_test_…');

// Per user. The reference is a value your server already knows, such as a user or order id: every
// webhook carries it.
try {
  const outcome = await Zktls.verify(['zktls-demo'], 'order_8f3k2');
  for (const p of outcome.platforms) {
    console.log(p.platform, p.status, p.reason); // 'done', 'failed' or 'notStarted'
  }
} catch (e) {
  const err = e as ZktlsError;
  if (err.code === 'Refused') {
    // The verification did not start; the SDK has already shown the user why.
    console.log(err.refusal, err.message); // such as 'device_not_verified'
  }
}
```

`verify` resolves once the user leaves the flow, with a `VerifyOutcome`: its `verificationId` and, per
platform, its `status` and, for a failure, a `reason`. It carries no data from the platform: your server
gets one signed `platform.finished` webhook per platform the user started, and one `verification.finished`
when every platform has ended ([webhooks](https://docs.cr3dentials.xyz/essentials/webhooks)).
`Zktls.verifyToken(token)` runs the platforms and the reference your server set with
`POST /partner/verification-tokens`.

On Android, `verify` shows its screens over the current activity, which must stay in front until it
resolves. On iOS, over the key window's top-most view controller.

## The look of the SDK's screens

`configure` takes a theme and the screens' words:

```ts
await Zktls.configure(
  'zk_live_…',
  { accent: '#1E66F5', background: '#FFFFFF', text: '#111111', logo: 'brand_logo' },
  { 'intro.title': 'Verify your accounts' } // any screen string, by key
);
```

Colors are `#RRGGBB` or `#AARRGGBB`. `logo` names an image in your app: an Android drawable, an iOS
asset. A field you leave out keeps the SDK's default. The string keys are the SDK's own, such as `intro.title` or
`disclosure.body`, the same on both platforms; keep the words in braces, such as `{platform}`, which the SDK
fills in ([iOS](https://docs.cr3dentials.xyz/sdk/ios), [Android](https://docs.cr3dentials.xyz/sdk/android)).

## Prove a fact

The SDK's proof flow is here too, for a policy and profile we set up with you: `ZktlsClient.create(config)`,
then `login`, `capture`, `prove` and `claim`. The user's account data never leaves the phone; the claim
carries only the proven outputs, signed by the verifier.

```ts
const client = await ZktlsClient.create(config); // a SessionConfig, per session
const progress = client.onProgress((e) => setProgress(e.phase, e.percent));
try {
  await client.login(); // the disclosure, then the page
  await client.capture();
  const report = await client.prove();
  if (report.accepted) {
    const claim = await client.claim(); // verified against the trust bundle
    await send(claim.encoded); // your backend verifies it again
  }
} finally {
  progress.remove();
  await client.dispose(); // every path
}
```

`SessionConfig` has the native SDK's fields and rules
([field table](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/integration-ios.md#build-the-sessions-configuration)),
and your backend verifies the claim itself
([verifying a claim](https://github.com/Cr3dentials/zktls-sdk-releases/blob/main/docs/backend-verification.md)).
`issuedAt`, `expiresAt` and the proof report's byte counts are strings: JavaScript numbers lose precision
above 2^53.

## Things to know

- **One verification at a time.** A `verify` called while another runs waits for it to finish.
- **Background.** `verify` keeps itself alive when the user leaves your app. For a proof session, the bridge
  does what the SDK's guides ask of a native app: after `login` it follows Wi-Fi and cellular handovers and
  keeps the session alive, with a short foreground service on Android and background time on iOS.
- **The notification.** On Android the foreground service shows a notification reading "Verifying". Define
  `zktls_session_notification_title`, `zktls_session_channel_name` and the drawable
  `zktls_session_notification_icon` in your app's resources to translate or rebrand it.
- **The disclosure.** A proof session's `login()` shows the SDK's standard disclosure before the page. Pass
  `login({ title, message, accept, decline })` to translate it; a field you leave out keeps the standard text.
- **Errors.** A failed call rejects with an `Error` whose `code` is an `SdkErrorCode`
  ([errors](https://docs.cr3dentials.xyz/sdk/errors)). For `Refused`, `refusal` holds the reason, such as
  `device_not_verified` or `app_key_invalid`. For `Transport`, `Policy` and `Refused`, `message` carries
  the SDK's text. `Internal` is a fault inside the SDK that was not one of its errors: report it.
- **Logging.** Never log your app key in production builds, or a `SessionConfig`: it holds the app
  credential.

## Before you submit

Work through the SDK's [release checklist](https://docs.cr3dentials.xyz/sdk/release-checklist): your app's
registration with us, the device checks, privacy answers, and a test account for review.

## The example app

`example/` runs on both platforms. Its "Test bridge" button exercises the proof-flow round-trips that need no
live backend. Its "Verify" button runs `verify` once `example/src/settings.ts` holds an app key; that file is
committed empty, so never commit it with a real key.

## Versions

Releases follow [Semantic Versioning](https://semver.org/). Version 2 of the bridge wraps version 2 of the
SDK: it depends on 2.0.1 or later, within 2.x.

## License

[Apache-2.0](LICENSE). The SDK's own license and the open-source notices of its compiled core are in the
[zktls-sdk-releases](https://github.com/Cr3dentials/zktls-sdk-releases) repository.
