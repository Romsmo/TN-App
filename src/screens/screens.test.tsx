import { render, screen } from '@testing-library/react-native';

import { setLanguage } from '@/i18n';

import DriveScreen from '@/app/drive';
import MapScreen from '@/app/index';
import SettingsScreen from '@/app/settings';

describe('placeholder screens', () => {
  beforeEach(() => setLanguage('en'));

  it.each([
    ['map', MapScreen],
    ['drive', DriveScreen],
    ['settings', SettingsScreen],
  ])('%s says plainly that it is not built yet', async (_name, Screen) => {
    await render(<Screen />);
    expect(screen.getByText('This area will be built in a later stage.')).toBeTruthy();
  });

  it('shows the app version in settings', async () => {
    await render(<SettingsScreen />);
    expect(screen.getByText(/^Version /)).toBeTruthy();
  });
});
