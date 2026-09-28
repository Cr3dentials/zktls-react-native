import { useEffect, useState } from 'react';
import { Text, View, StyleSheet, Button, ScrollView } from 'react-native';
import { ZktlsClient, type Phase, type SessionConfig } from 'zktls-react-native';

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
  const [phase, setPhase] = useState<Phase | 'idle'>('idle');
  const [percent, setPercent] = useState(0);
  const [log, setLog] = useState<string[]>([]);
  const [client, setClient] = useState<ZktlsClient | null>(null);

  const append = (line: string) => setLog((prev) => [...prev, line]);

  useEffect(() => {
    if (!client) return;
    const sub = client.onProgress((e) => {
      setPhase(e.phase);
      setPercent(e.percent);
    });
    return () => sub.remove();
  }, [client]);

  const run = async () => {
    let c: ZktlsClient | null = null;
    try {
      c = await ZktlsClient.create({
        ...DEMO_CONFIG,
        idempotencyKey: String(Date.now()),
      });
      setClient(c);
      await c.login();
      await c.capture();
      const report = await c.prove();
      if (!report.accepted) {
        append(`Not proven: ${report.verdict}`);
        return;
      }
      const claim = await c.claim();
      append(`Claim: ${claim.encoded.slice(0, 32)}...`);
    } catch (err) {
      const e = err as { code?: string; message?: string };
      append(`Error [${e.code ?? 'Unknown'}]: ${e.message ?? String(err)}`);
    } finally {
      await c?.dispose();
      setClient(null);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.status}>
        {phase} {percent}%
      </Text>
      <Button title="Run verification" onPress={run} />
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
