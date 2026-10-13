import { TnError, TnService, type RawClient } from './service';

function fakeRaw(answers: Record<string, string>): RawClient & { calls: [string, unknown][] } {
  const calls: [string, unknown][] = [];
  return {
    calls,
    callAsync: async (method, argsJson) => {
      calls.push([method, JSON.parse(argsJson)]);
      const answer = answers[method];
      if (answer === undefined) throw new Error(`unexpected call ${method}`);
      return answer;
    },
    startRealtime: jest.fn(),
    stopRealtime: jest.fn(),
    setEventListener: jest.fn(),
    uniffiDestroy: jest.fn(),
  };
}

describe('TnService', () => {
  it('unwraps ok results and sends the argument names of api.md', async () => {
    const raw = fakeRaw({ getNearby: JSON.stringify({ ok: { items: [{ kind: 'sign', id: 's1' }] } }) });
    const items = await new TnService(raw).getNearby(52.5, 13.4, 1000, ['hazards']);
    expect(items).toEqual([{ kind: 'sign', id: 's1' }]);
    expect(raw.calls).toEqual([['getNearby', { lat: 52.5, lng: 13.4, radiusMeters: 1000, categories: ['hazards'] }]]);
  });

  it('turns an error answer into a TnError with the library code', async () => {
    const raw = fakeRaw({ sync: JSON.stringify({ error: { code: 'network', message: 'no server' } }) });
    await expect(new TnService(raw).sync()).rejects.toMatchObject({ name: 'TnError', code: 'network', message: 'no server' });
  });

  it('rejects an answer that is not JSON or has neither ok nor error', async () => {
    const service = new TnService(fakeRaw({ tick: 'oops', sync: '{}' }));
    await expect(service.tick()).rejects.toBeInstanceOf(TnError);
    await expect(service.sync()).rejects.toMatchObject({ code: 'badResponse' });
  });

  it('queues a report and a vote with the argument names of api.md', async () => {
    const raw = fakeRaw({
      submitReport: JSON.stringify({ ok: { localId: 'local-1' } }),
      confirmReport: JSON.stringify({ ok: { localId: 'local-2' } }),
    });
    const service = new TnService(raw);
    await expect(service.submitReport('ice', 52.5, 13.4)).resolves.toBe('local-1');
    await expect(service.confirmReport('r1', false)).resolves.toBe('local-2');
    expect(raw.calls).toEqual([
      ['submitReport', { type: 'ice', lat: 52.5, lng: 13.4 }],
      ['confirmReport', { reportId: 'r1', stillThere: false }],
    ]);
  });

  it('accepts a null result (no speed limit nearby)', async () => {
    const service = new TnService(fakeRaw({ getSpeedLimitAt: JSON.stringify({ ok: null }) }));
    await expect(service.getSpeedLimitAt(1, 2)).resolves.toBeNull();
  });

  it('hands events to the callback and ignores unreadable ones', () => {
    const raw = fakeRaw({});
    const service = new TnService(raw);
    const seen: unknown[] = [];
    service.onEvents((e) => seen.push(e));
    const listener = (raw.setEventListener as jest.Mock).mock.calls[0][0] as { onEvent(json: string): void };
    listener.onEvent('{"type":"storageFull"}');
    listener.onEvent('garbage');
    expect(seen).toEqual([{ type: 'storageFull' }]);
  });

  it('close stops realtime, removes the listener and releases the client', () => {
    const raw = fakeRaw({});
    new TnService(raw).close();
    expect(raw.stopRealtime).toHaveBeenCalled();
    expect(raw.setEventListener).toHaveBeenCalledWith(undefined);
    expect(raw.uniffiDestroy).toHaveBeenCalled();
  });
});

describe('TnService: library 1.2.0', () => {
  const ok = (value: unknown) => JSON.stringify({ ok: value });

  it('asks for a report duration with ttlSeconds and reports whether it was honoured', async () => {
    const raw = fakeRaw({ submitReport: ok({ localId: 'l1', expiresInSeconds: 7200, durationHonoured: true, defaultSeconds: 1500 }) });
    const submitted = await new TnService(raw).submitReportFor('ice', 52.5, 13.4, { ttlSeconds: 7200 });
    expect(submitted).toMatchObject({ localId: 'l1', durationHonoured: true });
    expect(raw.calls).toEqual([['submitReport', { type: 'ice', lat: 52.5, lng: 13.4, ttlSeconds: 7200 }]]);
  });

  it('refuses a duration outside the bounds with the library code', async () => {
    const raw = fakeRaw({ submitReport: JSON.stringify({ error: { code: 'ttlOutOfRange', message: 'too long' } }) });
    await expect(new TnService(raw).submitReportFor('ice', 1, 2, { ttlSeconds: 99999999 })).rejects.toMatchObject({ code: 'ttlOutOfRange' });
  });

  it('reads the limits of a type', async () => {
    const raw = fakeRaw({ getReportLimits: ok({ supported: true, defaultSeconds: 10800, minSeconds: 600, maxSeconds: 43200 }) });
    await expect(new TnService(raw).getReportLimits('mobileSpeedCamera')).resolves.toEqual({ supported: true, defaultSeconds: 10800, minSeconds: 600, maxSeconds: 43200 });
    expect(raw.calls).toEqual([['getReportLimits', { type: 'mobileSpeedCamera' }]]);
  });

  it('looks up a limit and passes on the three answers', async () => {
    const raw = fakeRaw({ lookupSpeedLimit: ok({ status: 'outsideOfflineArea' }) });
    await expect(new TnService(raw).lookupSpeedLimit(1, 2, 90)).resolves.toEqual({ status: 'outsideOfflineArea' });
    expect(raw.calls).toEqual([['lookupSpeedLimit', { lat: 1, lng: 2, heading: 90 }]]);
  });

  it('proposes a missing and a wrong limit with the argument names of api.md', async () => {
    const proposal = { segmentKey: 'k', segmentId: 's', value: 50, unit: 'kmh', state: 'queued', correctionId: null, confirmations: 0 };
    const raw = fakeRaw({ reportMissingSpeedLimit: ok(proposal), reportWrongSpeedLimit: ok(proposal) });
    const service = new TnService(raw);
    await service.reportMissingSpeedLimit({ lat: 1, lng: 2, value: 50, unit: 'kmh', bearing: 10 });
    await service.reportWrongSpeedLimit({ lat: 1, lng: 2, proposedValue: 30, unit: 'kmh', reason: 'wrongValue' });
    expect(raw.calls).toEqual([
      ['reportMissingSpeedLimit', { lat: 1, lng: 2, value: 50, unit: 'kmh', bearing: 10 }],
      ['reportWrongSpeedLimit', { lat: 1, lng: 2, proposedValue: 30, unit: 'kmh', reason: 'wrongValue' }],
    ]);
  });

  it('manages the offline area', async () => {
    const settings = { mode: 'regions', regions: ['DE-BY'], home: null, maxBytes: null, wifiOnly: true };
    const raw = fakeRaw({ setOfflineRegions: ok(settings), setStorageLimits: ok(settings), listOfflineRegions: ok({ regions: [{ id: 'DE-BY' }] }), getCoverage: ok({ covered: false, tile: null, state: 'outside', usesNetwork: true }) });
    const service = new TnService(raw);
    await service.setOfflineRegions({ regions: ['DE-BY'] });
    await service.setStorageLimits({ maxBytes: null });
    await expect(service.listOfflineRegions()).resolves.toEqual([{ id: 'DE-BY' }]);
    await expect(service.getCoverage(1, 2)).resolves.toMatchObject({ state: 'outside' });
    expect(raw.calls[1]).toEqual(['setStorageLimits', { maxBytes: null }]);
  });
});

