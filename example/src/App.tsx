import { useEffect, useState } from 'react';
import { Text, View, StyleSheet, Button, ScrollView } from 'react-native';
import {
  Zktls,
  ZktlsClient,
  type SessionConfig,
  type VerifyOutcome,
  type ZktlsError,
} from '@cr3dentials-org/zktls-react-native';
import { settings } from './settings';

// Placeholder configuration for "Test bridge". A real proof needs a SessionConfig
// from your backend: baseUrl, appCredential, the trust and policy bundles, and
// their pins.
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

// What the app learns from a verification: how each platform ended, never the
// data, which your server gets in signed webhooks.
function describe(o: VerifyOutcome): string[] {
  return [
    `verification ${o.verificationId}`,
    ...o.platforms.map(
      (p) => `${p.platform}: ${p.status}${p.reason ? ` (${p.reason})` : ''}`
    ),
  ];
}

export default function App() {
  const [log, setLog] = useState<string[]>([]);
  const [running, setRunning] = useState(false);

  const append = (line: string) => setLog((prev) => [...prev, line]);

  // Once, when the app starts, with the app's publishable key.
  useEffect(() => {
    Zktls.configure(settings.appKey).catch((e: ZktlsError) =>
      append(`configure failed - ${e.code}: ${e.message}`)
    );
  }, []);

  // Exercises the proof-flow round-trips that do not need a live backend:
  // create() marshals a SessionConfig across and returns a sessionId; prove() on
  // a fresh session must reject (no capture yet), which runs a real verb call and
  // the error-code mapping; dispose() releases it.
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
        append(`prove rejected as expected - code ${(err as ZktlsError).code}`);
      }
      await c.dispose();
      append('dispose OK');
      append('Bridge round-trips OK');
    } catch (err) {
      const e = err as ZktlsError;
      append(`create failed - ${e.code ?? 'unknown'}: ${e.message}`);
    }
  };

  // The partner flow: the SDK shows its own screens, runs each platform, and
  // resolves once the user leaves. A reference is a value your server already
  // knows, such as a user or order id; every webhook carries it.
  const verify = async () => {
    setLog([]);
    if (!settings.appKey) {
      append('No app key: add example/verify.json');
      return;
    }
    setRunning(true);
    try {
      const outcome = await Zktls.verify(
        settings.platforms,
        `example-${Date.now()}`
      );
      describe(outcome).forEach(append);
    } catch (err) {
      const e = err as ZktlsError;
      // A refusal: the SDK has already shown the user why.
      append(
        e.code === 'Refused'
          ? `not started: ${e.refusal} - ${e.message}`
          : `${e.code ?? 'Error'}: ${e.message}`
      );
    } finally {
      setRunning(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.status}>zkTLS bridge test</Text>
      <Button title="Test bridge" onPress={testBridge} disabled={running} />
      <View style={styles.gap} />
      <Button
        title={`Verify ${settings.platforms.join(', ')}`}
        onPress={verify}
        disabled={running}
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
  gap: { height: 12 },
  log: { marginTop: 16, maxHeight: 240 },
});
