import { LockGuard } from '@/components/lock-guard';
import { ServerScreen } from '@/screens/server/server-screen';

export default function ServerRoute() {
  return (
    <LockGuard>
      <ServerScreen />
    </LockGuard>
  );
}
