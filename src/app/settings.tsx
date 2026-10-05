import { LockGuard } from '@/components/lock-guard';
import { SettingsScreen } from '@/screens/settings/settings-screen';

export default function SettingsRoute() {
  return (
    <LockGuard>
      <SettingsScreen />
    </LockGuard>
  );
}
