import { fireEvent, render, renderHook, screen, waitFor } from '@testing-library/react-native';

import { setLanguage } from '@/i18n';
import type { TnService } from '@/tn/service';
import type { HazardItem } from '@/tn/types';

import { DetailCard } from './detail-card';
import { ReportSheet } from './report-sheet';
import { FilterBar } from './filter-bar';
import { radiusFor, useNearby } from './use-nearby';

const item: HazardItem = {
  kind: 'hazard', id: 'h1', hazardType: 'ice', lat: 1, lng: 2, distanceMeters: 123.4, expiresAt: '2026-10-05T12:00:00Z', confirmCount: 3, denyCount: 1, pending: true,
};

beforeEach(() => setLanguage('en'));

describe('DetailCard', () => {
  it('shows type, votes, distance and the pending note, and can be closed', async () => {
    const onClose = jest.fn();
    await render(<DetailCard item={item} onClose={onClose} />);
    expect(screen.getByText('Ice')).toBeTruthy();
    expect(screen.getByText('3 confirmations · 1 denials')).toBeTruthy();
    expect(screen.getByText('123 m away')).toBeTruthy();
    expect(screen.getByText('Not sent yet — will be transmitted at the next sync.')).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Close' }));
    expect(onClose).toHaveBeenCalled();
  });

  it('omits the pending note for a delivered report', async () => {
    await render(<DetailCard item={{ ...item, pending: false }} onClose={() => {}} />);
    expect(screen.queryByText(/Not sent yet/)).toBeNull();
  });
});

describe('FilterBar', () => {
  it('lists the given types as switches, off ones unchecked', async () => {
    await render(<FilterBar types={['ice', 'traffic']} hidden={['ice']} onToggle={() => {}} />);
    expect(screen.getByRole('switch', { name: 'Show Ice' }).props.accessibilityState).toEqual({ checked: false });
    expect(screen.getByRole('switch', { name: 'Show Traffic jam' }).props.accessibilityState).toEqual({ checked: true });
  });

  it('reports which type was tapped', async () => {
    const onToggle = jest.fn();
    await render(<FilterBar types={['ice']} hidden={[]} onToggle={onToggle} />);
    await fireEvent.press(screen.getByRole('switch', { name: 'Show Ice' }));
    expect(onToggle).toHaveBeenCalledWith('ice');
  });

  it('renders nothing without types', async () => {
    await render(<FilterBar types={[]} hidden={[]} onToggle={() => {}} />);
    expect(screen.queryByRole('switch')).toBeNull();
  });
});

describe('useNearby', () => {
  const fakeService = (getNearby: jest.Mock) => ({ getNearby }) as unknown as TnService;

  it('reads from the library for the viewport and again when the data version moves', async () => {
    const getNearby = jest.fn().mockResolvedValue([item]);
    const viewport = { lat: 1, lng: 2, radiusMeters: 5000 };
    const service = fakeService(getNearby);
    const { result, rerender } = await renderHook(({ version }: { version: number }) => useNearby(service, viewport, version), {
      initialProps: { version: 0 },
    });
    await waitFor(() => expect(result.current).toEqual([item]));
    expect(getNearby).toHaveBeenCalledWith(1, 2, 5000);
    await rerender({ version: 1 });
    await waitFor(() => expect(getNearby).toHaveBeenCalledTimes(2));
  });

  it('answers empty without a service or viewport, and when the library fails', async () => {
    const { result } = await renderHook(() => useNearby(null, null, 0));
    expect(result.current).toEqual([]);
    const failing = jest.fn().mockRejectedValue(new Error('unavailable'));
    const failingService = fakeService(failing);
    const failingViewport = { lat: 1, lng: 2, radiusMeters: 100 };
    const { result: r2 } = await renderHook(() => useNearby(failingService, failingViewport, 0));
    await waitFor(() => expect(failing).toHaveBeenCalled());
    expect(r2.current).toEqual([]);
  });
});

describe('radiusFor', () => {
  it('is the centre-to-corner distance, clamped to what the library allows', () => {
    expect(radiusFor({ lat: 0, lng: 0 }, { lat: 0, lng: 0.1 })).toBeGreaterThan(11_000);
    expect(radiusFor({ lat: 0, lng: 0 }, { lat: 0, lng: 0.1 })).toBeLessThan(11_200);
    expect(radiusFor({ lat: 0, lng: 0 }, { lat: 0, lng: 0.0001 })).toBe(500);
    expect(radiusFor({ lat: 0, lng: 0 }, { lat: 0, lng: 20 })).toBe(50_000);
  });
});

describe('DetailCard voting', () => {
  it('offers "still there" and "gone" and reports the choice', async () => {
    const onVote = jest.fn();
    await render(<DetailCard item={{ ...item, pending: false }} onClose={() => {}} onVote={onVote} />);
    await fireEvent.press(screen.getByRole('button', { name: 'Still there' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Gone' }));
    expect(onVote.mock.calls).toEqual([[true], [false]]);
  });

  it('has no voting without a handler, and none for a report that is still only on this device', async () => {
    await render(<DetailCard item={{ ...item, pending: false }} onClose={() => {}} />);
    expect(screen.queryByText('Is the report still current?')).toBeNull();
    await render(<DetailCard item={item} onClose={() => {}} onVote={() => {}} />);
    expect(screen.queryByRole('button', { name: 'Still there' })).toBeNull();
  });

  it('thanks after a saved vote and shows a failed one', async () => {
    const { rerender } = await render(<DetailCard item={{ ...item, pending: false }} onClose={() => {}} onVote={() => {}} voteState="saved" />);
    expect(screen.getByText('Thanks, your answer is being sent.')).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Still there' })).toBeNull();
    await rerender(<DetailCard item={{ ...item, pending: false }} onClose={() => {}} onVote={() => {}} voteState="failed" />);
    expect(screen.getByText('The answer could not be saved.')).toBeTruthy();
  });
});

describe('ReportSheet', () => {
  const types = ['traffic', 'ice'];

  it('shows one big button per type and reports the pick', async () => {
    const onPick = jest.fn();
    await render(<ReportSheet types={types} location={{ lat: 1, lng: 2, source: 'device' }} locating={false} message={null} onPick={onPick} onCancel={() => {}} />);
    expect(screen.getByText('At your location')).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Report Ice' }));
    expect(onPick).toHaveBeenCalledWith('ice');
  });

  it('names the marked spot when the user tapped the map', async () => {
    await render(<ReportSheet types={types} location={{ lat: 1, lng: 2, source: 'map' }} locating={false} message={null} onPick={() => {}} onCancel={() => {}} />);
    expect(screen.getByText('At the marked spot')).toBeTruthy();
  });

  it('cannot be submitted without a location', async () => {
    const onPick = jest.fn();
    await render(<ReportSheet types={types} location={null} locating message={null} onPick={onPick} onCancel={() => {}} />);
    expect(screen.getByText('Finding your location …')).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Report Ice' }));
    expect(onPick).not.toHaveBeenCalled();
  });

  it('explains when no location is available, shows a message and can be cancelled', async () => {
    const onCancel = jest.fn();
    await render(<ReportSheet types={types} location={null} locating={false} message="Nope" onPick={() => {}} onCancel={onCancel} />);
    expect(screen.getByText(/No location available/)).toBeTruthy();
    expect(screen.getByText('Nope')).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Cancel' }));
    expect(onCancel).toHaveBeenCalled();
  });
});
