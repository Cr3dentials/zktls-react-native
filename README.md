# zktls-react-native

React Native bridge for the [zkTLS native SDK](https://github.com/Cr3dentials/zktls-sdk). It exposes
the SDK's API to a React Native app: the native SDK does the cryptography, this package is the
thin bridge that lets JavaScript drive it. Turbo Module, New Architecture, one API on both platforms.

## Install

Not on npm yet: `npm install github:Cr3dentials/zktls-react-native`. React Native 0.80+, Android
minSdk 24, iOS 14+. The Android app currently builds with JDK 17; iOS needs Xcode.

## The native SDK

The bridge links the compiled SDK, not its source: `xyz.cr3dentials:zktls-sdk:1.0.0` from Maven Central
for Android, and the `ZktlsSDK` pod from [zktls-sdk-releases](https://github.com/Cr3dentials/zktls-sdk-releases)
for iOS. That repository is its own CocoaPods spec source, so an app's `Podfile` lists it first:

```ruby
source 'https://github.com/Cr3dentials/zktls-sdk-releases.git'
source 'https://cdn.cocoapods.org/'
```

## Proving a fact

`ZktlsClient` mirrors the SDK's facade: `create`, `login`, `capture`, `prove`, `claim`, `onProgress`,
`cancel`, `dispose`. `create` takes a `SessionConfig` (baseUrl, appCredential, the trust and policy
bundles and their pins, an idempotencyKey new for every session) and returns a client keyed by a
session id; the opaque handles never cross the bridge, and login runs the SDK's native WebView.

```ts
const client = await ZktlsClient.create(config);
const progress = client.onProgress((e) => console.log(e.phase, e.percent));
try {
  await client.login();
  await client.capture();
  const report = await client.prove();
  if (report.accepted) {
    const claim = await client.claim(); // your backend verifies claim.encoded again
  }
} finally {
  progress.remove();
  await client.dispose();
}
```

A failed verb rejects with a `code` (an `SdkErrorCode`); `Transport` and `Policy` carry text. The SDK
never retries, and neither should the app.

On Android a session shows the SDK's foreground-service notification while it is protected: from
`login` to the end of the proof, and while a pack's run is with the attester. Its text and icon are the
SDK's resources, which an app can override.

Both bridges are verified against the real SDK: the round-trips run on an Android device and an iOS
simulator. `example/` is a runnable harness whose "Test bridge" button exercises the round-trips that
need no live backend, and whose "Run a platform pack" button runs a pack against a lab configured in
`example/src/labSettings.ts`.

## Platform packs

`ZktlsClient.createTree()` makes a client for platform packs, and `runTree(config, disclosure)` runs one:
the SDK shows the disclosure, opens the platform's sign-in page in its WebView and collects in the page.
The data reaches your backend at the run's `resultUrl`, posted by the SDK or, for a pack that attests, by
the attester; the app gets a `TreeSummary` with each source's counts only.

```ts
const client = await ZktlsClient.createTree();
try {
  const summary = await client.runTree(config, disclosure); // config: a TreeRunConfig
} finally {
  await client.dispose();
}
```
