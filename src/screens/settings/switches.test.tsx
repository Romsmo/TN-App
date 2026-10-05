import { fireEvent, render, screen } from '@testing-library/react-native';

import { setLanguage } from '@/i18n';
import { CAMERA_NOTICE, CAMERA_NOTICE_VERSION, LOCK_WARNING, plain } from '@/legal/texts';

import { CamerasSwitch, noticeKey } from './cameras-switch';
import { LockSwitch } from './lock-switch';

beforeEach(() => setLanguage('de'));

describe('LockSwitch (Fahrsperre)', () => {
  it('shows the exact warning and asks for confirmation before the lock is switched off', async () => {
    const onChange = jest.fn();
    await render(<LockSwitch enabled onChange={onChange} />);
    await fireEvent(screen.getByLabelText('Fahrsperre'), 'valueChange', false);
    expect(screen.getByText(LOCK_WARNING.de)).toBeTruthy();
    expect(onChange).not.toHaveBeenCalled(); // nothing changed yet
    await fireEvent.press(screen.getByRole('button', { name: 'Ich habe es verstanden, abschalten' }));
    expect(onChange).toHaveBeenCalledWith(false);
  });

  it('keeps the lock when the warning is cancelled', async () => {
    const onChange = jest.fn();
    await render(<LockSwitch enabled onChange={onChange} />);
    await fireEvent(screen.getByLabelText('Fahrsperre'), 'valueChange', false);
    await fireEvent.press(screen.getByRole('button', { name: 'Sperre anlassen' }));
    expect(onChange).not.toHaveBeenCalled();
    expect(screen.queryByText(LOCK_WARNING.de)).toBeNull();
  });

  it('shows the warning again every time the lock is switched off', async () => {
    const onChange = jest.fn();
    const { rerender } = await render(<LockSwitch enabled onChange={onChange} />);
    for (let round = 0; round < 3; round++) {
      await fireEvent(screen.getByLabelText('Fahrsperre'), 'valueChange', false);
      expect(screen.getByText(LOCK_WARNING.de)).toBeTruthy();
      await fireEvent.press(screen.getByRole('button', { name: 'Ich habe es verstanden, abschalten' }));
      await rerender(<LockSwitch enabled={false} onChange={onChange} />);
      await fireEvent(screen.getByLabelText('Fahrsperre'), 'valueChange', true); // switching on needs no confirmation
      await rerender(<LockSwitch enabled onChange={onChange} />);
    }
    expect(onChange.mock.calls.filter(([v]) => v === false)).toHaveLength(3);
    expect(onChange.mock.calls.filter(([v]) => v === true)).toHaveLength(3);
  });

  it('switches on without any dialog', async () => {
    const onChange = jest.fn();
    await render(<LockSwitch enabled={false} onChange={onChange} />);
    await fireEvent(screen.getByLabelText('Fahrsperre'), 'valueChange', true);
    expect(onChange).toHaveBeenCalledWith(true);
    expect(screen.queryByText(LOCK_WARNING.de)).toBeNull();
  });

  it('shows the English warning in English', async () => {
    setLanguage('en');
    await render(<LockSwitch enabled onChange={() => {}} />);
    await fireEvent(screen.getByLabelText('Driving lock'), 'valueChange', false);
    expect(screen.getByText(LOCK_WARNING.en)).toBeTruthy();
  });
});

describe('CamerasSwitch (Blitzer)', () => {
  const base = { enabled: false, maxLevel: 'full' as const, noticeSeen: null, serverNoticeVersion: null };

  it('shows the notice, exactly as specified, when ticked for the first time', async () => {
    const onChange = jest.fn();
    const onNoticeSeen = jest.fn();
    await render(<CamerasSwitch {...base} onChange={onChange} onNoticeSeen={onNoticeSeen} />);
    await fireEvent(screen.getByLabelText('Blitzer anzeigen und melden'), 'valueChange', true);
    expect(onChange).toHaveBeenCalledWith(true);
    expect(screen.getByText(plain(CAMERA_NOTICE.de))).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Verstanden' }));
    expect(onNoticeSeen).toHaveBeenCalledWith(CAMERA_NOTICE_VERSION);
  });

  it('shows the notice only once: not again when it was seen', async () => {
    await render(<CamerasSwitch {...base} noticeSeen={CAMERA_NOTICE_VERSION} onChange={() => {}} onNoticeSeen={() => {}} />);
    await fireEvent(screen.getByLabelText('Blitzer anzeigen und melden'), 'valueChange', true);
    expect(screen.queryByText(plain(CAMERA_NOTICE.de))).toBeNull();
  });

  it('shows it again when the server\'s notice version grew', async () => {
    const seen = noticeKey('1');
    await render(<CamerasSwitch {...base} noticeSeen={seen} serverNoticeVersion="2" onChange={() => {}} onNoticeSeen={() => {}} />);
    await fireEvent(screen.getByLabelText('Blitzer anzeigen und melden'), 'valueChange', true);
    expect(screen.getByText(plain(CAMERA_NOTICE.de))).toBeTruthy();
  });

  it('shows no notice when switching off', async () => {
    await render(<CamerasSwitch {...base} enabled onChange={() => {}} onNoticeSeen={() => {}} />);
    await fireEvent(screen.getByLabelText('Blitzer anzeigen und melden'), 'valueChange', false);
    expect(screen.queryByText(plain(CAMERA_NOTICE.de))).toBeNull();
  });

  it('is unavailable, and says why, when the network policy is off', async () => {
    await render(<CamerasSwitch {...base} enabled maxLevel="off" onChange={() => {}} onNoticeSeen={() => {}} />);
    const toggle = screen.getByLabelText('Blitzer anzeigen und melden');
    expect(toggle.props.value).toBe(false);
    expect(toggle.props.disabled).toBe(true);
    expect(screen.getByText(/nicht freigegeben/)).toBeTruthy();
  });

  it('says that only areas are shown when the policy allows zones only', async () => {
    await render(<CamerasSwitch {...base} maxLevel="zones" onChange={() => {}} onNoticeSeen={() => {}} />);
    expect(screen.getByText(/nur Gefahrenbereiche/)).toBeTruthy();
  });
});
