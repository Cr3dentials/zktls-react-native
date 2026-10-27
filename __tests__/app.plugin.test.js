// The Expo config plugin's Podfile transform and its mod. Run with `yarn test`
// (node's own test runner; no dependencies).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const withZktlsPodSources = require('../app.plugin');
const { addPodSources } = withZktlsPodSources;

const RELEASES =
  "source 'https://github.com/Cr3dentials/zktls-sdk-releases.git'";
const CDN = "source 'https://cdn.cocoapods.org/'";

// The top of the Podfile expo prebuild writes, which lists no source.
const EXPO_PODFILE = [
  'require File.join(File.dirname(`node --print "require.resolve(\'expo/package.json\')"`), "scripts/autolinking")',
  "platform :ios, '15.1'",
  '',
  "target 'App' do",
  '  use_expo_modules!',
  'end',
  '',
].join('\n');

test('adds both sources, the releases repository first', () => {
  const out = addPodSources(EXPO_PODFILE);
  assert.equal(out, `${RELEASES}\n${CDN}\n${EXPO_PODFILE}`);
});

test('is idempotent', () => {
  const once = addPodSources(EXPO_PODFILE);
  assert.equal(addPodSources(once), once);
});

test('puts the releases repository before a source already listed', () => {
  const podfile = `${CDN}\n${EXPO_PODFILE}`;
  assert.equal(addPodSources(podfile), `${RELEASES}\n${CDN}\n${EXPO_PODFILE}`);
});

test('adds the CDN after the releases repository when only it is listed', () => {
  const podfile = `source "https://github.com/Cr3dentials/zktls-sdk-releases"\n${EXPO_PODFILE}`;
  assert.equal(
    addPodSources(podfile),
    `source "https://github.com/Cr3dentials/zktls-sdk-releases"\n${CDN}\n${EXPO_PODFILE}`
  );
});

test('the mod edits ios/Podfile, then runs the mods added before it', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'zktls-plugin-'));
  const podfile = path.join(root, 'Podfile');
  fs.writeFileSync(podfile, EXPO_PODFILE);
  let ranEarlier = false;
  const config = withZktlsPodSources({
    name: 'app',
    mods: {
      ios: {
        dangerous: async (c) => {
          ranEarlier = true;
          return c;
        },
      },
    },
  });
  const modRequest = { platformProjectRoot: root, platform: 'ios' };
  await config.mods.ios.dangerous({ ...config, modRequest });
  assert.equal(
    fs.readFileSync(podfile, 'utf8'),
    `${RELEASES}\n${CDN}\n${EXPO_PODFILE}`
  );
  assert.equal(ranEarlier, true);
  fs.rmSync(root, { recursive: true, force: true });
});
