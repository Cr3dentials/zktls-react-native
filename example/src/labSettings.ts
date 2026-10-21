// Settings for "Run a platform pack". Fill them from pack-lab's tree.json for a
// local lab (base_url, app_credential, user_id_hash, client_region,
// trust_operator_key, runs_url, platforms). Never commit real values.
// The bundle URLs are only read by a pack that attests; leave them empty if
// tree.json has none.
export const labSettings = {
  baseUrl: '',
  appCredential: '',
  userIdHash: '',
  clientRegion: '',
  trustOperatorKey: '',
  runsUrl: '',
  platforms: [] as string[],
  trustBundleUrl: '',
  policyBundleUrl: '',
  policyBundleDigest: '',
};
