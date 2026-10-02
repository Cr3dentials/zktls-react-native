import { useState } from 'react';
import { Text, View, StyleSheet, Button, ScrollView } from 'react-native';
import { ZktlsClient, type SessionConfig } from 'zktls-react-native';

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
  trustOperatorKey: '',
  policyBundleJson: '',
  policyBundleDigest: '',
};

export default function App() {
  const [log, setLog] = useState<string[]>([]);

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

  return (
    <View style={styles.container}>
      <Text style={styles.status}>zkTLS bridge test</Text>
      <Button title="Test bridge" onPress={testBridge} />
      <ScrollView style={styles.log}>
        {log.map((line, i) => (
          <Text key={i}>{line}</Text>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 24, justifyContent: 'center' },
  status: { fontSize: 18, marginBottom: 12, textAlign: 'center' },
  log: { marginTop: 16, maxHeight: 240 },
});
