# zktls-react-native

React Native bridge for the [zkTLS native SDK](https://github.com/Cr3dentials/zktls-sdk). It exposes
the SDK's six verbs to a React Native app: the native SDK does the cryptography, this package is the
thin bridge that lets JavaScript drive it. Turbo Module, New Architecture, one API on both platforms.

## Install

Not on npm yet: `npm install github:Cr3dentials/zktls-react-native`. React Native 0.80+, Android
minSdk 24, iOS 14+. The Android app currently builds with JDK 17; iOS needs Xcode.

## The native SDK

The bridge links the compiled SDK, not its source, and consumes it from a local build until it is
published. Build it from [Cr3dentials/zktls-sdk](https://github.com/Cr3dentials/zktls-sdk):
`:sdk:publishReleasePublicationToMavenLocal` puts the AAR in the local Maven cache, which this package
resolves as `io.github.cr3dentials:zktls-sdk` through `mavenLocal()`; `build-ios.sh` produces the
Swift package the app's Podfile points at as a local `ZktlsSDK` pod. Switch to the published
coordinate once it lands, with no bridge change.

## The six verbs

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

The Android bridge is verified against the real SDK, and its round-trips run on device; the iOS bridge
is written but not yet built on a Mac. `example/` is a runnable harness whose "Test bridge" button
exercises the round-trips that need no live backend.
