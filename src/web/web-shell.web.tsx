import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon } from '@/components/icon';
import { Button } from '@/components/ui';
import { t } from '@/i18n';
import { elevation, radius, squircle, TAB_BAR_CLEARANCE, type, useTheme } from '@/theme';

import { detectOs, isStandalone, shouldOfferInstall } from './platform';

const DISMISSED_KEY = 'tnviewer.installHintDismissed';

type WebGlobals = {
  __tnWaiting?: unknown;
  __tnApplyUpdate?: () => void;
};

type InstallPromptEvent = Event & { prompt(): Promise<void> };

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

/**
 * Only one tab may run the app: the library keeps its whole store in memory and writes it as one snapshot, so two tabs on
 * the same database overwrite each other (client-lib/docs/integration-web.md). The first tab takes a lock that lives as long
 * as the page; a second tab sees it is taken and shows a short explanation instead of starting the app.
 * Browsers without the Web Locks API start the app unguarded (documented in docs/web-limits.md).
 */
function useSingleTab(): 'checking' | 'ok' | 'blocked' {
  const [state, setState] = useState<'checking' | 'ok' | 'blocked'>(() => (typeof navigator !== 'undefined' && navigator.locks ? 'checking' : 'ok'));
  useEffect(() => {
    if (!navigator.locks) return;
    void navigator.locks.request('tnviewer-database', { ifAvailable: true }, (lock) => {
      setState(lock ? 'ok' : 'blocked');
      return lock ? new Promise<void>(() => undefined) : undefined; // held until the page goes away
    });
  }, []);
  return state;
}

function UpdateBanner() {
  const theme = useTheme();
  const [available, setAvailable] = useState(() => (globalThis as WebGlobals).__tnWaiting !== undefined);
  useEffect(() => {
    const on = () => setAvailable(true);
    window.addEventListener('tn-update-available', on);
    return () => window.removeEventListener('tn-update-available', on);
  }, []);
  if (!available) return null;
  return (
    <View accessibilityRole="alert" style={[styles.card, squircle, elevation(theme, 2), { backgroundColor: theme.surface }]}>
      <Text style={[type.body, styles.flex, { color: theme.text }]}>{t('web.update.text')}</Text>
      <Button label={t('web.update.button')} onPress={() => (globalThis as WebGlobals).__tnApplyUpdate?.()} />
    </View>
  );
}

function InstallHint() {
  const theme = useTheme();
  const [prompt, setPrompt] = useState<InstallPromptEvent | null>(null);
  const [dismissed, setDismissed] = useState(() => read(DISMISSED_KEY) === '1');
  useEffect(() => {
    const on = (event: Event) => {
      event.preventDefault();
      setPrompt(event as InstallPromptEvent);
    };
    window.addEventListener('beforeinstallprompt', on);
    return () => window.removeEventListener('beforeinstallprompt', on);
  }, []);
  const os = detectOs(navigator.userAgent, navigator.maxTouchPoints, navigator.platform);
  const standalone = isStandalone({ matchMedia: window.matchMedia?.bind(window), navigatorStandalone: (navigator as { standalone?: boolean }).standalone });
  if (!shouldOfferInstall({ os, standalone, dismissed })) return null;
  const later = () => {
    try {
      localStorage.setItem(DISMISSED_KEY, '1');
    } catch {
      // asked again next time
    }
    setDismissed(true);
  };
  return (
    <View style={[styles.card, squircle, elevation(theme, 2), styles.column, { backgroundColor: theme.surface }]}>
      <Text accessibilityRole="header" style={[type.heading, { color: theme.text }]}>
        {t('web.install.title')}
      </Text>
      <Text style={[type.caption, { color: theme.textSecondary }]}>{t(os === 'ios' ? 'web.install.ios' : 'web.install.android')}</Text>
      <View style={styles.row}>
        {prompt ? (
          <View style={styles.flex}>
            <Button
              label={t('web.install.button')}
              onPress={() => {
                void prompt.prompt();
                setPrompt(null);
              }}
            />
          </View>
        ) : null}
        <View style={styles.flex}>
          <Button kind="plain" label={t('web.install.later')} onPress={later} />
        </View>
      </View>
    </View>
  );
}

function TestBadge() {
  const theme = useTheme();
  return (
    <View pointerEvents="none" style={styles.badgeBox}>
      <View style={[styles.badge, { backgroundColor: theme.warn }]}>
        <Icon name="flask" size={12} color="#FFFFFF" />
        <Text style={styles.badgeText}>{t('web.testBadge')}</Text>
      </View>
    </View>
  );
}

function LockedTab() {
  const theme = useTheme();
  return (
    <View style={[styles.locked, { backgroundColor: theme.background }]}>
      <Text accessibilityRole="header" style={[type.title, { color: theme.text }]}>
        {t('web.lock.title')}
      </Text>
      <Text style={[type.body, { color: theme.textSecondary }]}>{t('web.lock.body')}</Text>
      <Pressable accessibilityRole="button" accessibilityLabel={t('web.lock.reload')} onPress={() => window.location.reload()} style={[styles.reload, { backgroundColor: theme.tint }]}>
        <Text style={[styles.reloadText, { color: theme.onTint }]}>{t('web.lock.reload')}</Text>
      </Pressable>
    </View>
  );
}

/** What only the browser version needs around the app: one tab at a time, install hint, update notice, "test version" label. */
export function WebShell({ children }: { children: React.ReactNode }) {
  const insets = useSafeAreaInsets();
  const tab = useSingleTab();
  if (tab === 'blocked') return <LockedTab />;
  if (tab === 'checking') return null;
  return (
    <View style={styles.flex}>
      {children}
      <View pointerEvents="box-none" style={[styles.overlay, { top: insets.top + 8 }]}>
        <UpdateBanner />
      </View>
      <View pointerEvents="box-none" style={styles.bottomOverlay}>
        <InstallHint />
      </View>
      <TestBadge />
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  overlay: { position: 'absolute', left: 0, right: 0, gap: 8, zIndex: 20 },
  bottomOverlay: { position: 'absolute', left: 0, right: 0, bottom: TAB_BAR_CLEARANCE + 12, zIndex: 20 },
  card: { marginHorizontal: 16, borderRadius: radius.lg, padding: 14, flexDirection: 'row', alignItems: 'center', gap: 12 },
  column: { flexDirection: 'column', alignItems: 'stretch', gap: 8 },
  row: { flexDirection: 'row', gap: 8 },
  badgeBox: { position: 'absolute', left: 0, right: 0, bottom: TAB_BAR_CLEARANCE - 8, alignItems: 'flex-end', paddingRight: 20, zIndex: 5 },
  badge: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 8, paddingVertical: 3, borderRadius: radius.pill },
  badgeText: { color: '#FFFFFF', fontSize: 11, fontWeight: '800', letterSpacing: 0.4 },
  locked: { flex: 1, padding: 24, justifyContent: 'center', gap: 12 },
  reload: { minHeight: 52, borderRadius: radius.pill, alignItems: 'center', justifyContent: 'center', marginTop: 8 },
  reloadText: { fontSize: 17, fontWeight: '700' },
});
