import { useState } from 'react';
import { ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';

import { Body, Button, MIN_TOUCH, Section } from '@/components/ui';
import { formatDateTime } from '@/i18n/format';
import { t, type TextKey } from '@/i18n';
import { settingsStore, useSettings } from '@/settings';
import { useTn } from '@/state/tn-provider';
import { normalizeServerAddress } from '@/tn/server-address';
import { useTheme } from '@/theme';

const ADDRESS_ERRORS = {
  empty: 'server.errorEmpty',
  invalid: 'server.errorInvalid',
  insecure: 'server.errorInsecure',
  credentials: 'server.errorCredentials',
} as const satisfies Record<string, TextKey>;

function StatusLine({ text }: { text: string }) {
  return <Body secondary>{text}</Body>;
}

export function ServerScreen() {
  const theme = useTheme();
  const settings = useSettings();
  const tn = useTn();

  const [address, setAddress] = useState(settings.serverAddress ?? '');
  const [addressError, setAddressError] = useState<TextKey | null>(null);
  const [kind, setKind] = useState<'client' | 'app'>('app');
  const [accessId, setAccessId] = useState('');
  const [accessSecret, setAccessSecret] = useState('');
  const [accessMessage, setAccessMessage] = useState<TextKey | null>(null);

  const inputStyle = [styles.input, { color: theme.text, borderColor: theme.textSecondary, backgroundColor: theme.background }];

  const connect = () => {
    const result = normalizeServerAddress(address, { allowInsecure: __DEV__ });
    if (!result.ok) {
      setAddressError(ADDRESS_ERRORS[result.reason]);
      return;
    }
    setAddressError(null);
    setAddress(result.url);
    settingsStore.update({ serverAddress: result.url });
  };

  const useDiscovery = () => {
    setAddressError(null);
    setAddress('');
    settingsStore.update({ serverAddress: null });
  };

  const saveAccess = () => {
    const id = accessId.trim();
    const secret = accessSecret.trim();
    if (!id || !secret) {
      setAccessMessage('server.accessIncomplete');
      return;
    }
    tn.credentialsStore.set(
      kind === 'app' ? { type: 'app', appClientId: id, appClientSecret: secret } : { type: 'client', clientId: id, clientSecret: secret },
    );
    setAccessId('');
    setAccessSecret('');
    setAccessMessage('server.accessSaved');
  };

  const clearAccess = () => {
    tn.credentialsStore.clear();
    setAccessMessage(null);
  };

  const sync = tn.sync;
  const nodes = tn.network?.knownNodes ?? [];
  const current = new Set(tn.network?.currentNodes ?? []);

  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <Section title={t('server.address')}>
        <TextInput
          accessibilityLabel={t('server.address')}
          value={address}
          onChangeText={setAddress}
          placeholder="node.example.org"
          placeholderTextColor={theme.textSecondary}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
          style={inputStyle}
        />
        <StatusLine text={t('server.addressHint')} />
        {addressError ? (
          <Text accessibilityRole="alert" style={{ color: theme.danger, fontSize: 15 }}>
            {t(addressError)}
          </Text>
        ) : null}
        <Button label={t('server.connect')} onPress={connect} />
        <Button kind="plain" label={t('server.auto')} onPress={useDiscovery} />
        <StatusLine text={settings.serverAddress ? t('server.usingServer', { address: settings.serverAddress }) : t('server.usingDiscovery')} />
      </Section>

      <Section title={t('server.access')}>
        <StatusLine text={t('server.accessHint')} />
        <View style={styles.row}>
          <View style={styles.flex}>
            <Button kind={kind === 'app' ? 'primary' : 'plain'} label={t('server.accessKind.app')} onPress={() => setKind('app')} />
          </View>
          <View style={styles.flex}>
            <Button kind={kind === 'client' ? 'primary' : 'plain'} label={t('server.accessKind.client')} onPress={() => setKind('client')} />
          </View>
        </View>
        <TextInput
          accessibilityLabel={t('server.accessId')}
          value={accessId}
          onChangeText={setAccessId}
          placeholder={t('server.accessId')}
          placeholderTextColor={theme.textSecondary}
          autoCapitalize="none"
          autoCorrect={false}
          style={inputStyle}
        />
        <TextInput
          accessibilityLabel={t('server.accessSecret')}
          value={accessSecret}
          onChangeText={setAccessSecret}
          placeholder={t('server.accessSecret')}
          placeholderTextColor={theme.textSecondary}
          autoCapitalize="none"
          autoCorrect={false}
          secureTextEntry
          style={inputStyle}
        />
        {accessMessage ? <StatusLine text={t(accessMessage)} /> : null}
        <Button label={t('server.accessSave')} onPress={saveAccess} />
        <Button kind="plain" label={t('server.accessClear')} onPress={clearAccess} />
      </Section>

      <Section title={t('server.status')}>
        {tn.phase === 'starting' ? <StatusLine text={t('status.starting')} /> : null}
        {tn.phase === 'noCredentials' ? <StatusLine text={t('status.noCredentials')} /> : null}
        {tn.phase === 'error' ? <StatusLine text={t('status.error', { message: tn.error ?? t('common.unknown') })} /> : null}
        {sync ? (
          <>
            <Body>{t(`server.connection.${sync.connection}`)}</Body>
            <StatusLine text={t('server.lastSync', { time: sync.lastSyncedAtUnixMs ? formatDateTime(sync.lastSyncedAtUnixMs) : t('common.never') })} />
            <StatusLine text={t('server.pending', { count: sync.pendingWrites })} />
            {sync.lastErrorCode ? <StatusLine text={t('server.lastError', { code: sync.lastErrorCode })} /> : null}
          </>
        ) : null}
        {tn.network?.onlineNetwork != null ? <StatusLine text={t('server.online', { count: tn.network.onlineNetwork })} /> : null}
        <Button label={t('server.syncNow')} onPress={() => void tn.syncNow()} disabled={!tn.service} />
      </Section>

      <Section title={t('server.nodes')}>
        {nodes.length === 0 ? <StatusLine text={t('server.nodesNone')} /> : null}
        {nodes.map((node) => (
          <View key={node.nodeId} accessible accessibilityLabel={`${node.address}, ${t(`server.tier.${node.tier}`)}`}>
            <Body>{node.address}</Body>
            <StatusLine
              text={[t(`server.tier.${node.tier}`), current.has(node.nodeId) ? t('server.nodeUsed') : null, node.backedOff ? t('server.nodeBackedOff') : null]
                .filter(Boolean)
                .join(' · ')}
            />
          </View>
        ))}
      </Section>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 18 },
  input: { minHeight: MIN_TOUCH, borderWidth: StyleSheet.hairlineWidth, borderRadius: 10, paddingHorizontal: 12, fontSize: 17 },
  row: { flexDirection: 'row', gap: 8 },
  flex: { flex: 1 },
});
