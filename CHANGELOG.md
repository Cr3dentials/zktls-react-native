# Changelog

## 2.0.0

The first public release, on the zkTLS SDK 2.0.1 or later within 2.x. Version 2 of the bridge wraps
version 2 of the SDK.

- `Zktls.configure(appKey, theme?, strings?)` once, then `Zktls.verify(platforms, reference)` or
  `Zktls.verifyToken(token)` per user, resolving with a `VerifyOutcome`. The theme is a `ZktlsTheme`, the
  native SDK's name: colors are exactly `#RRGGBB` or `#AARRGGBB`, and the logo an image's name in the app.
- The `Refused` error code, with the reason in `refusal`.
- The `InvalidArgument` error code: `configure` given a color in another form, or a screen string that is not
  a string, rejects with it on both platforms and changes nothing.
- A `verify` in flight ends with `Cancelled` when the module goes away, as on a JavaScript reload.
- An Expo config plugin: `plugins: ["@cr3dentials-org/zktls-react-native"]` writes the SDK's pod source into
  the Podfile on `expo prebuild`.
- The proof flow: `ZktlsClient.create`, then `login`, `capture`, `prove` and `claim`, with `onProgress`,
  `cancel` and `dispose`. A proof session survives the user leaving the app and a Wi-Fi to cellular
  handover: the bridge runs the SDK's lifecycle, and on Android its foreground service.
- A login disclosure field left out keeps the SDK's standard text.
- Licensed Apache-2.0.
