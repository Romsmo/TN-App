import { useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { ConfirmDialog } from '@/components/confirm-dialog';
import { Body, RowIcon, Toggle } from '@/components/ui';
import { getLanguage, t } from '@/i18n';
import { CAMERA_NOTICE, CAMERA_NOTICE_VERSION } from '@/legal/texts';
import type { CameraLevel } from '@/tn/types';

type Props = {
  enabled: boolean;
  onChange: (enabled: boolean) => void;
  /** The country policy as the library reports it; null while unknown. `off` takes the option away. */
  maxLevel: CameraLevel | null;
  /** The notice version the user has seen, and the version of the server's notice (null = unknown). */
  noticeSeen: string | null;
  serverNoticeVersion: string | null;
  onNoticeSeen: (version: string) => void;
};

/** What the user has to have seen: our wording's version and, when the server's notice changes, that version too. */
export function noticeKey(serverNoticeVersion: string | null): string {
  return serverNoticeVersion ? `${CAMERA_NOTICE_VERSION}|${serverNoticeVersion}` : CAMERA_NOTICE_VERSION;
}

/**
 * The speed-camera option, off at the first start. Ticking it shows the legal notice once (plainly informing, not a
 * consent dialog) and again only when the wording or the server's notice version changed.
 * When the network's policy allows nothing (`off`) the option is unavailable and says why.
 */
export function CamerasSwitch({ enabled, onChange, maxLevel, noticeSeen, serverNoticeVersion, onNoticeSeen }: Props) {
  const [showing, setShowing] = useState(false);
  const blocked = maxLevel === 'off';
  const key = noticeKey(serverNoticeVersion);

  const toggle = (value: boolean) => {
    onChange(value);
    if (value && noticeSeen !== key) setShowing(true);
  };

  return (
    <View>
      <View style={styles.row}>
        <RowIcon name="camera" />
        <View style={styles.flex}>
          <Body>{t('cameras.label')}</Body>
        </View>
        <Toggle accessibilityLabel={t('cameras.label')} value={enabled && !blocked} disabled={blocked} onValueChange={toggle} />
      </View>
      <Body secondary>{t('cameras.hint')}</Body>
      {blocked ? <Body secondary>{t('cameras.policyOff')}</Body> : null}
      {maxLevel === 'zones' ? <Body secondary>{t('cameras.policyZones')}</Body> : null}
      <ConfirmDialog
        visible={showing}
        title={t('cameras.noticeTitle')}
        body={CAMERA_NOTICE[getLanguage()]}
        confirmLabel={t('cameras.noticeOk')}
        onConfirm={() => {
          setShowing(false);
          onNoticeSeen(key);
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({ row: { flexDirection: 'row', alignItems: 'center', gap: 12 }, flex: { flex: 1 } });
