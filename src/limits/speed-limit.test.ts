import { TnError, type TnService } from '@/tn/service';

import { entryLocked, lookupSpot, parseLimitValue, proposeCorrection, proposeMissing } from './speed-limit';

const spot = { lat: 52.5, lng: 13.4 };
const fake = (methods: Record<string, jest.Mock>) => methods as unknown as TnService;

describe('parseLimitValue', () => {
  it.each([['50', 'kmh', 50], [' 130 ', 'kmh', 130], ['5', 'kmh', 5], ['200', 'kmh', 200], ['55', 'mph', 55]] as const)('%j %s -> %d', (text, unit, expected) => {
    expect(parseLimitValue(text, unit)).toBe(expected);
  });
  it.each([['', 'kmh'], ['abc', 'kmh'], ['4', 'kmh'], ['201', 'kmh'], ['126', 'mph'], ['5,5', 'kmh'], ['-50', 'kmh'], ['1000', 'kmh']] as const)('rejects %j (%s)', (text, unit) => {
    expect(parseLimitValue(text, unit)).toBeNull();
  });
});

describe('entryLocked (Fahrsperre)', () => {
  it('is locked while the drive lock is in force', () => {
    expect(entryLocked({ lockActive: true, lockEnabled: true, deviceSpeedKmh: 0 })).toBe(true);
  });
  it('is locked at driving speed (10 km/h and up) even without a started drive, when the lock is on', () => {
    expect(entryLocked({ lockActive: false, lockEnabled: true, deviceSpeedKmh: 10 })).toBe(true);
    expect(entryLocked({ lockActive: false, lockEnabled: true, deviceSpeedKmh: 80 })).toBe(true);
  });
  it('is open when standing or walking, or when the speed is unknown', () => {
    expect(entryLocked({ lockActive: false, lockEnabled: true, deviceSpeedKmh: 9.9 })).toBe(false);
    expect(entryLocked({ lockActive: false, lockEnabled: true, deviceSpeedKmh: null })).toBe(false);
  });
  it('does not lock by device speed when the user switched the lock off (the drive lock itself still decides)', () => {
    expect(entryLocked({ lockActive: false, lockEnabled: false, deviceSpeedKmh: 90 })).toBe(false);
  });
});

describe('lookupSpot', () => {
  it('passes the answer on, including the honest "outside the offline area"', async () => {
    const lookup = jest.fn().mockResolvedValue({ status: 'outsideOfflineArea' });
    await expect(lookupSpot(fake({ lookupSpeedLimit: lookup }), spot)).resolves.toEqual({ phase: 'done', result: { status: 'outsideOfflineArea' } });
    expect(lookup).toHaveBeenCalledWith(52.5, 13.4);
  });
  it('turns a failed lookup into an error state', async () => {
    await expect(lookupSpot(fake({ lookupSpeedLimit: jest.fn().mockRejectedValue(new TnError('network', 'x')) }), spot)).resolves.toEqual({ phase: 'error' });
  });
});

describe('proposals', () => {
  it('proposes a missing limit with the reason "missing", only value, unit and the spot', async () => {
    const report = jest.fn().mockResolvedValue({});
    await expect(proposeMissing(fake({ reportMissingSpeedLimit: report }), spot, 50, 'kmh')).resolves.toEqual({ ok: true });
    expect(report).toHaveBeenCalledWith({ lat: 52.5, lng: 13.4, value: 50, unit: 'kmh', reason: 'missing' });
  });
  it('proposes a correction with the chosen reason', async () => {
    const report = jest.fn().mockResolvedValue({});
    await expect(proposeCorrection(fake({ reportWrongSpeedLimit: report }), spot, 30, 'kmh', 'signMissingOrNew')).resolves.toEqual({ ok: true });
    expect(report).toHaveBeenCalledWith({ lat: 52.5, lng: 13.4, proposedValue: 30, unit: 'kmh', reason: 'signMissingOrNew' });
  });
  it.each([
    [new TnError('roadAlreadyHasLimit', 'x'), 'roadAlreadyHasLimit'],
    [new TnError('invalidArgument', 'x'), 'invalidValue'],
    [new TnError('storageFull', 'x'), 'storageFull'],
    [new TnError('network', 'x'), 'network'],
    [new Error('boom'), 'failed'],
  ])('maps %p to %s', async (error, reason) => {
    await expect(proposeMissing(fake({ reportMissingSpeedLimit: jest.fn().mockRejectedValue(error) }), spot, 50, 'kmh')).resolves.toEqual({ ok: false, reason });
  });
});
