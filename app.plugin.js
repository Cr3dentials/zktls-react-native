// The Expo config plugin: add "@cr3dentials/zktls-react-native" to `plugins`
// in app.json, then run `npx expo prebuild`. On iOS it lists the SDK's releases
// repository, then the CocoaPods CDN, as the Podfile's sources: the ZktlsSDK pod
// comes from the first, and CocoaPods takes a pod from the first source that has
// it. Android needs nothing: Gradle fetches the SDK from Maven Central.
//
// It depends on nothing, not even @expo/config-plugins: it is the dangerous mod
// that Expo's withDangerousMod makes, written out (do this, then run the mods
// added before it), so it works with whichever expo the app has.
const fs = require('fs');
const path = require('path');

const RELEASES = 'https://github.com/Cr3dentials/zktls-sdk-releases.git';
const CDN = 'https://cdn.cocoapods.org/';

// A source URL without its trailing slash or ".git", so either spelling counts.
function normalize(url) {
  return url.replace(/\/+$/, '').replace(/\.git$/, '');
}

// The index of the Podfile line `source '<url>'`, or -1; any URL when url is null.
function sourceLine(lines, url) {
  return lines.findIndex((line) => {
    const m = line.match(/^\s*source\s+(['"])(.+?)\1/);
    return m !== null && (url === null || normalize(m[2]) === normalize(url));
  });
}

// The Podfile with both sources, the releases repository first. Idempotent: a
// source already listed, in either spelling, is left where it is.
function addPodSources(podfile) {
  const lines = podfile.split('\n');
  if (sourceLine(lines, RELEASES) === -1) {
    const first = sourceLine(lines, null);
    lines.splice(first === -1 ? 0 : first, 0, `source '${RELEASES}'`);
  }
  if (sourceLine(lines, CDN) === -1) {
    lines.splice(sourceLine(lines, RELEASES) + 1, 0, `source '${CDN}'`);
  }
  return lines.join('\n');
}

function withZktlsPodSources(config) {
  config.mods = config.mods || {};
  config.mods.ios = config.mods.ios || {};
  const next = config.mods.ios.dangerous;
  config.mods.ios.dangerous = async (modConfig) => {
    const podfile = path.join(
      modConfig.modRequest.platformProjectRoot,
      'Podfile'
    );
    const contents = await fs.promises.readFile(podfile, 'utf8');
    const updated = addPodSources(contents);
    if (updated !== contents) await fs.promises.writeFile(podfile, updated);
    return next ? next(modConfig) : modConfig;
  };
  return config;
}

module.exports = withZktlsPodSources;
module.exports.addPodSources = addPodSources;
