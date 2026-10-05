import { LockGuard } from '@/components/lock-guard';
import { DataScreen } from '@/screens/data/data-screen';

export default function DataRoute() {
  return (
    <LockGuard>
      <DataScreen />
    </LockGuard>
  );
}
