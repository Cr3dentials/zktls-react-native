// The example's settings. appKey is your app's publishable key from Cr3dentials,
// read from example/verify.json, {"app_key": "zk_test_..."}, which git ignores so
// a key never lands in source. A zk_test_ key runs only the demo platform,
// zktls-demo (any user name, the password demo), and works on simulators and
// emulators.
function appKey(): string {
  try {
    return require('../verify.json').app_key ?? '';
  } catch {
    return '';
  }
}

export const settings = {
  appKey: appKey(),
  platforms: ['zktls-demo'],
};
