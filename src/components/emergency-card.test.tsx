import { act, fireEvent, render, screen } from '@testing-library/react-native';

import { setLanguage } from '@/i18n';

import { EmergencyCard } from './emergency-card';

beforeEach(() => setLanguage('en'));

describe('EmergencyCard', () => {
  it('says what is missing when no server is reachable, and what still works', async () => {
    await render(<EmergencyCard reason="noServer" onRetry={async () => {}} onSetup={() => {}} />);
    expect(screen.getByText('Emergency mode')).toBeTruthy();
    expect(screen.getByText(/No server is reachable yet/)).toBeTruthy();
    expect(screen.getByText(/you can queue reports/)).toBeTruthy();
  });

  it('says "no access" when credentials are missing', async () => {
    await render(<EmergencyCard reason="noAccess" onRetry={async () => {}} onSetup={() => {}} />);
    expect(screen.getByText(/No access has been set up yet/)).toBeTruthy();
  });

  it('retries on tap, shows the search while it runs, and can be used again afterwards', async () => {
    let finish: () => void = () => {};
    const onRetry = jest.fn(() => new Promise<void>((resolve) => (finish = resolve)));
    await render(<EmergencyCard reason="noServer" onRetry={onRetry} onSetup={() => {}} />);
    await fireEvent.press(screen.getByRole('button', { name: 'Try again' }));
    expect(onRetry).toHaveBeenCalledTimes(1);
    expect(screen.getByRole('button', { name: 'Searching …' })).toBeTruthy();
    await act(async () => finish());
    expect(screen.getByRole('button', { name: 'Try again' })).toBeTruthy();
  });

  it('opens the server setup', async () => {
    const onSetup = jest.fn();
    await render(<EmergencyCard reason="noServer" onRetry={async () => {}} onSetup={onSetup} />);
    await fireEvent.press(screen.getByRole('button', { name: 'Set up server' }));
    expect(onSetup).toHaveBeenCalled();
  });
});
