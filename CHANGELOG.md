# Changelog

## 2.0.0

The first public release, on the zkTLS SDK 2.0.1 or later within 2.x. Version 2 of the bridge wraps
version 2 of the SDK.

- `Zktls.configure(appKey, theme?, strings?)` once, then `Zktls.verify(platforms, reference)` or
  `Zktls.verifyToken(token)` per user, resolving with a `VerifyOutcome`. Theme colors are hex strings and
  the logo an image's name in the app.
- The `Refused` error code, with the reason in `refusal`.
- The proof flow: `ZktlsClient.create`, then `login`, `capture`, `prove` and `claim`, with `onProgress`,
  `cancel` and `dispose`. A proof session survives the user leaving the app and a Wi-Fi to cellular
  handover: the bridge runs the SDK's lifecycle, and on Android its foreground service.
- A login disclosure field left out keeps the SDK's standard text.
- Licensed Apache-2.0.
