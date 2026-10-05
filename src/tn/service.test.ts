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
