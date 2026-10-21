import { useRef, useState } from 'react';
import {
  Text,
  View,
  StyleSheet,
  Button,
  ScrollView,
  Pressable,
} from 'react-native';
import {
  ZktlsClient,
  type SessionConfig,
  type TreeDisclosure,
  type TreeSummary,
} from 'zktls-react-native';
import { labSettings } from './labSettings';

// Placeholder configuration. Fill these from your backend before a real run:
// baseUrl, appCredential, the trust and policy bundles, and their pins. The flow
// below is the real API; it will only complete once these are real and the
// native SDK binary is wired in.
const DEMO_CONFIG: SessionConfig = {
  baseUrl: 'https://example.invalid',
  appCredential: '',
  userIdHash: '',
  profileId: '',
  policyId: '',
  idempotencyKey: '',
  clientRegion: '',
  networkKey: 'default',
  trustBundleJson: '',
  trustBundleUrl: '',
  trustOperatorKey: '',
  policyBundleJson: '',
  policyBundleDigest: '',
};

// Your disclosure, in your words: the SDK shows it before the platform's pages
// open, and opens nothing if the user declines.
function disclosure(platformId: string): TreeDisclosure {
  return {
    title: 'Connect your account',
    message:
      `The app opens ${platformId}'s own sign-in page. You sign in there yourself; the app never sees ` +
      'your password. After you sign in, the app reads the data this check needs from your account on this device.',
    accept: 'Continue',
    decline: 'Not now',
  };
}

// What the app learns from a run: how it ended and each source's counts, never the data.
function describe(s: TreeSummary): string[] {
  const lines = [s.succeeded ? 'Collected' : `Not collected: ${s.error}`];
  for (const src of s.sources) {
    lines.push(`${src.storeAs}: ${src.rows} rows, ${src.pages} pages`);
  }
  const result = s.handedOff
    ? 'handed to the attester, which posts the result'
    : s.delivered
      ? 'result delivered'
      : `result not delivered: ${s.deliveryError}`;
  lines.push(`${Math.floor(Number(s.durationMs) / 1000)} s; ${result}`);
  return lines;
}

// Your backend's call for a run: it returns the run's result URL and token.
async function issueRun(platformId: string) {
  const res = await fetch(labSettings.runsUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${labSettings.appCredential}`,
    },
    body: JSON.stringify({ platform_id: platformId }),
  });
  if (res.status !== 200)
    throw new Error(`the runs URL answered ${res.status}`);
  const j = (await res.json()) as {
    result_url: string;
    result_token: string;
    params?: object;
  };
  return {
    resultUrl: j.result_url,
    resultToken: j.result_token,
    paramsJson: j.params ? JSON.stringify(j.params) : '',
  };
}

// Read only by a pack that attests; '' when the URL is unset.
async function fetchText(url: string): Promise<string> {
  if (!url) return '';
  const res = await fetch(url);
  if (res.status !== 200) throw new Error(`${url} answered ${res.status}`);
  return res.text();
}

function randomId(): string {
  const hex = () => Math.floor(Math.random() * 0x100000000).toString(16);
  return `${Date.now().toString(16)}-${hex()}-${hex()}`;
}

export default function App() {
  const [log, setLog] = useState<string[]>([]);
  const [platform, setPlatform] = useState(labSettings.platforms[0] ?? '');
  const [running, setRunning] = useState(false);
  const [picking, setPicking] = useState(false);
  const tree = useRef<ZktlsClient | null>(null);

  const append = (line: string) => setLog((prev) => [...prev, line]);

  // Exercises the bridge round-trips that do not need a live backend: create()
  // marshals a SessionConfig across and returns a sessionId; prove() on a fresh
  // session must reject (no capture yet), which runs a real verb call and the
  // error-code mapping; dispose() releases it. The full login->capture->prove->
  // claim flow needs real config and a live verifier.
  const testBridge = async () => {
    setLog([]);
    let c: ZktlsClient | null = null;
    try {
      c = await ZktlsClient.create({
        ...DEMO_CONFIG,
        idempotencyKey: String(Date.now()),
      });
      append(`create OK - sessionId ${c.sessionId.slice(0, 8)}...`);
      try {
        await c.prove();
        append('prove: unexpectedly resolved');
      } catch (err) {
        const e = err as { code?: string };
        append(`prove rejected as expected - code ${e.code ?? 'unknown'}`);
      }
      await c.dispose();
      append('dispose OK');
      append('Bridge round-trips OK');
    } catch (err) {
      const e = err as { code?: string; message?: string };
      append(
        `create failed - ${e.code ?? 'unknown'}: ${e.message ?? String(err)}`
      );
    }
  };

  // A platform's pack, the user present: the SDK shows the disclosure, opens the
  // platform's sign-in page and collects in the page. The data reaches the
  // backend at the result URL; the app gets a summary only.
  const runPack = async () => {
    setLog([]);
    if (!platform) {
      append('No platform: fill labSettings.ts from tree.json');
      return;
    }
    setRunning(true);
    let c: ZktlsClient | null = null;
    try {
      const run = await issueRun(platform);
      const trustBundleJson = await fetchText(labSettings.trustBundleUrl);
      const policyBundleJson = await fetchText(labSettings.policyBundleUrl);
      c = await ZktlsClient.createTree();
      tree.current = c;
      const progress = c.onProgress((e) => append(`${e.phase} ${e.percent}%`));
      try {
        const summary = await c.runTree(
          {
            baseUrl: labSettings.baseUrl,
            appCredential: labSettings.appCredential,
            userIdHash: labSettings.userIdHash,
            idempotencyKey: randomId(),
            clientRegion: labSettings.clientRegion,
            networkKey: 'sample',
            platformId: platform,
            trustBundleJson,
            trustBundleUrl: labSettings.trustBundleUrl,
            trustOperatorKey: labSettings.trustOperatorKey,
            policyBundleJson,
            policyBundleDigest: labSettings.policyBundleDigest,
            relyingPartyNonceHex: '',
            ...run,
          },
          disclosure(platform)
        );
        describe(summary).forEach(append);
      } finally {
        progress.remove();
      }
    } catch (err) {
      const e = err as { code?: string; message?: string };
      append(`${e.code ?? 'No run'}: ${e.message ?? String(err)}`);
    } finally {
      tree.current = null;
      await c?.dispose();
      setRunning(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.status}>zkTLS bridge test</Text>
      <Button title="Test bridge" onPress={testBridge} disabled={running} />
      {/* A plain dropdown: core RN has none, and the community picker does not
          link against RN 0.86's prebuilt iOS core. */}
      <Pressable
        onPress={() => setPicking(!picking)}
        disabled={running}
        style={styles.picker}
      >
        <Text>{platform || 'no platforms in labSettings'}</Text>
        <Text>{picking ? '\u25B4' : '\u25BE'}</Text>
      </Pressable>
      {picking && (
        <ScrollView style={styles.options}>
          {labSettings.platforms.map((id) => (
            <Pressable
              key={id}
              onPress={() => {
                setPlatform(id);
                setPicking(false);
              }}
              style={styles.option}
            >
              <Text style={id === platform && styles.selected}>{id}</Text>
            </Pressable>
          ))}
        </ScrollView>
      )}
      <Button
        title="Run a platform pack"
        onPress={runPack}
        disabled={running}
      />
      <Button
        title="Cancel"
        onPress={() => tree.current?.cancel()}
        disabled={!running}
      />
      <ScrollView style={styles.log}>
        {log.map((line, i) => (
          <Text key={i}>{line}</Text>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    justifyContent: 'center',
    backgroundColor: '#fff',
  },
  status: { fontSize: 18, marginBottom: 12, textAlign: 'center' },
  log: { marginTop: 16, maxHeight: 240 },
  picker: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    borderBottomWidth: 1,
    borderColor: '#888',
    paddingVertical: 10,
    marginVertical: 12,
  },
  options: { maxHeight: 240, marginBottom: 12 },
  option: { paddingVertical: 10 },
  selected: { fontWeight: 'bold' },
});
