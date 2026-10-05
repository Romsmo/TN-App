import { LockGuard } from '@/components/lock-guard';
import { InfoScreen } from '@/screens/info/info-screen';
import { getLibraryVersion } from '@/tn/native';

export default function InfoRoute() {
  return (
    <LockGuard>
      <InfoScreen libraryVersion={getLibraryVersion()} />
    </LockGuard>
  );
}
