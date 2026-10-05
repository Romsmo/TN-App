import { InfoScreen } from '@/screens/info/info-screen';
import { getLibraryVersion } from '@/tn/native';

export default function InfoRoute() {
  return <InfoScreen libraryVersion={getLibraryVersion()} />;
}
