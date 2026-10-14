import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';

import { setLanguage } from '@/i18n';
import { TnError, type TnService } from '@/tn/service';
import type { SpeedLimitLookup } from '@/tn/types';

import { SpeedLimitCard } from './speed-limit-card';

const spot = { lat: 52.5, lng: 13.4 };
const found: SpeedLimitLookup = {
  status: 'found', source: 'offline', value: 50, unit: 'kmh', segmentId: 's', segmentKey: 'k', distanceMeters: 3, origin: { kind: 'imported' }, importedValue: null,
};

function service(lookup: SpeedLimitLookup | Error, extra: Record<string, jest.Mock> = {}) {
  return {
    lookupSpeedLimit: lookup instanceof Error ? jest.fn().mockRejectedValue(lookup) : jest.fn().mockResolvedValue(lookup),
    reportMissingSpeedLimit: jest.fn().mockResolvedValue({}),
    reportWrongSpeedLimit: jest.fn().mockResolvedValue({}),
    ...extra,
  } as unknown as TnService & Record<string, jest.Mock>;
}

const card = (s: TnService | null, over: Partial<React.ComponentProps<typeof SpeedLimitCard>> = {}) => (
  <SpeedLimitCard service={s} spot={spot} unit="kmh" locked={false} onSaved={() => {}} onClose={() => {}} {...over} />
);

beforeEach(() => setLanguage('en'));

describe('SpeedLimitCard', () => {
  it('asks for a tap on a road before anything is looked up', async () => {
    const s = service(found);
    await render(card(s, { spot: null }));
    expect(screen.getByText(/Tap a road/)).toBeTruthy();
    expect(s.lookupSpeedLimit).not.toHaveBeenCalled();
  });

  it('says "No speed limit on record" and lets the user add one, with the safety note', async () => {
    const s = service({ status: 'notRecorded', source: 'offline' });
    const onSaved = jest.fn();
    await render(card(s, { onSaved }));
    expect(await screen.findByText('No speed limit on record')).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Add it' }));
    expect(screen.getByText('Only enter what the signs on site show.')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Send' }).props.accessibilityState?.disabled).toBe(true);
    await fireEvent.press(screen.getByRole('button', { name: '50' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Send' }));
    await waitFor(() => expect(s.reportMissingSpeedLimit).toHaveBeenCalledWith({ lat: 52.5, lng: 13.4, value: 50, unit: 'kmh', reason: 'missing' }));
    expect(await screen.findByText(/Saved\. The proposal is sent/)).toBeTruthy();
    expect(onSaved).toHaveBeenCalled();
  });

  it('shows the recorded limit and offers a correction with a reason', async () => {
    const s = service(found);
    await render(card(s));
    expect(await screen.findByLabelText('Speed limit 50 km/h')).toBeTruthy();
    expect(screen.getByText('From the map data')).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Not right?' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Lifted' }));
    await fireEvent.changeText(screen.getByLabelText('Other value'), '30');
    await fireEvent.press(screen.getByRole('button', { name: 'Send' }));
    await waitFor(() => expect(s.reportWrongSpeedLimit).toHaveBeenCalledWith({ lat: 52.5, lng: 13.4, proposedValue: 30, unit: 'kmh', reason: 'limitLifted' }));
  });

  it('is locked above the speed threshold: the limit is readable, but nothing can be submitted', async () => {
    const s = service({ status: 'notRecorded', source: 'offline' });
    await render(card(s, { locked: true }));
    expect(await screen.findByText('No speed limit on record')).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Add it' })).toBeNull();
    expect(screen.getByText(/locked while you drive/)).toBeTruthy();
    expect(s.reportMissingSpeedLimit).not.toHaveBeenCalled();
  });

  it('is honest outside the offline area: not available, no form, never "no limit"', async () => {
    await render(card(service({ status: 'outsideOfflineArea' })));
    expect(await screen.findByText('Speed limit not available here: outside the offline area only online.')).toBeTruthy();
    expect(screen.queryByText('No speed limit on record')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Add it' })).toBeNull();
  });

  it('tells a failed lookup instead of claiming there is no limit', async () => {
    await render(card(service(new TnError('network', 'x'))));
    expect(await screen.findByText(/lookup is not possible right now/)).toBeTruthy();
    expect(screen.queryByText('No speed limit on record')).toBeNull();
  });

  it('shows that the road has a limit by now when the library says so', async () => {
    const s = service({ status: 'notRecorded', source: 'offline' }, { reportMissingSpeedLimit: jest.fn().mockRejectedValue(new TnError('roadAlreadyHasLimit', 'x')) });
    await render(card(s));
    await fireEvent.press(await screen.findByRole('button', { name: 'Add it' }));
    await fireEvent.press(screen.getByRole('button', { name: '30' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Send' }));
    expect(await screen.findByText(/has a speed limit on record by now/)).toBeTruthy();
  });

  it('uses mph quick values when the unit is mph', async () => {
    await render(card(service({ status: 'notRecorded', source: 'offline' }), { unit: 'mph' }));
    await fireEvent.press(await screen.findByRole('button', { name: 'Add it' }));
    expect(screen.getByRole('button', { name: '55' })).toBeTruthy();
    expect(screen.queryByRole('button', { name: '120' })).toBeNull();
  });
});
