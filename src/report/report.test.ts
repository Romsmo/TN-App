import { setLanguage } from '@/i18n';
import { TnError, type TnService } from '@/tn/service';

import { interimCatalog, mapReportTypes } from './catalog';
import { pendingText, rejectedText } from './pending';
import { isPlausiblePosition, submitHazard, voteOnReport } from './submit';

function service(overrides: Partial<Record<'submitReport' | 'confirmReport', jest.Mock>>): TnService {
  return {
    submitReport: overrides.submitReport ?? jest.fn().mockResolvedValue('local-1'),
    confirmReport: overrides.confirmReport ?? jest.fn().mockResolvedValue('local-2'),
  } as unknown as TnService;
}

describe('isPlausiblePosition', () => {
  it.each([
    [{ lat: 52.5, lng: 13.4 }, true],
    [{ lat: -33.9, lng: 151.2 }, true],
    [{ lat: 0, lng: 0 }, false],
    [{ lat: 91, lng: 0 }, false],
    [{ lat: 0, lng: 181 }, false],
    [{ lat: NaN, lng: 1 }, false],
    [{ lat: 1, lng: Infinity }, false],
  ])('%j -> %s', (position, expected) => {
    expect(isPlausiblePosition(position)).toBe(expected);
  });
});

describe('submitHazard', () => {
  it('queues the report and returns the local id', async () => {
    const submit = jest.fn().mockResolvedValue('local-9');
    await expect(submitHazard(service({ submitReport: submit }), 'ice', { lat: 52.5, lng: 13.4 })).resolves.toEqual({ ok: true, localId: 'local-9' });
    expect(submit.mock.calls).toEqual([['ice', 52.5, 13.4]]); // type and position only, no speed
  });

  it('refuses an implausible position without calling the library', async () => {
    const submit = jest.fn();
    await expect(submitHazard(service({ submitReport: submit }), 'ice', { lat: 0, lng: 0 })).resolves.toEqual({ ok: false, reason: 'invalidPosition' });
    expect(submit).not.toHaveBeenCalled();
  });

  it.each([
    [new TnError('invalidArgument', 'unknown type'), 'invalidType'],
    [new TnError('storageFull', 'full'), 'storageFull'],
    [new TnError('closed', 'closed'), 'failed'],
    [new Error('boom'), 'failed'],
  ])('maps %p to %s', async (error, reason) => {
    const submit = jest.fn().mockRejectedValue(error);
    await expect(submitHazard(service({ submitReport: submit }), 'ice', { lat: 1, lng: 1 })).resolves.toEqual({ ok: false, reason });
  });
});

describe('voteOnReport', () => {
  it('queues the vote', async () => {
    const confirm = jest.fn().mockResolvedValue('local-3');
    await expect(voteOnReport(service({ confirmReport: confirm }), 'r1', true)).resolves.toEqual({ ok: true, localId: 'local-3' });
    expect(confirm).toHaveBeenCalledWith('r1', true);
  });

  it('reports a failing vote as failed', async () => {
    const confirm = jest.fn().mockRejectedValue(new TnError('closed', 'closed'));
    await expect(voteOnReport(service({ confirmReport: confirm }), 'r1', false)).resolves.toEqual({ ok: false, reason: 'failed' });
  });
});

describe('interim catalog', () => {
  it('offers the six hazard types and no camera type', () => {
    expect(interimCatalog.types()).toEqual(['traffic', 'accident', 'construction', 'ice', 'breakdown', 'obstacle']);
    expect(interimCatalog.types().some((type) => /camera|distanceControl/i.test(type))).toBe(false);
  });
});

describe('pending and rejected texts', () => {
  beforeEach(() => setLanguage('en'));

  it('says nothing when nothing waits', () => {
    expect(pendingText({ pending: 0, waitingForWifi: false, offline: false })).toBeNull();
  });

  it.each([
    [{ pending: 2, waitingForWifi: true, offline: true }, /when Wi-Fi is available/],
    [{ pending: 2, waitingForWifi: false, offline: true }, /when you are online/],
    [{ pending: 1, waitingForWifi: false, offline: false }, /being sent/],
  ])('explains the waiting state %j', (input, pattern) => {
    expect(pendingText(input)).toMatch(pattern);
  });

  it('shows a refused write as a calm notice, not as an error', () => {
    expect(rejectedText(0)).toBeNull();
    expect(rejectedText(2)).toMatch(/did not accept/);
    expect(rejectedText(2)).not.toMatch(/failed|could not/i);
  });
});

describe('mapReportTypes: the speed camera is offered only where it is on and allowed in full', () => {
  it.each([
    [false, 'full'],
    [true, 'zones'],
    [true, 'off'],
    [true, null],
  ] as const)('cameras active=%s, level=%s: no camera type', (active, level) => {
    expect(mapReportTypes(active, level)).toEqual(interimCatalog.types());
  });

  it('on and allowed in full: the mobile speed camera is added', () => {
    expect(mapReportTypes(true, 'full')).toEqual([...interimCatalog.types(), 'mobileSpeedCamera']);
  });
});
