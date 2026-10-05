import { createLocationSource, type LocationBackend } from './location-source';
import type { Fix } from './warning-engine';

function backend(overrides: Partial<LocationBackend> = {}) {
  let sink: ((fix: Fix) => void) | null = null;
  const log: string[] = [];
  const b: LocationBackend & { push(f: Partial<Fix>): void; log: string[] } = {
    log,
    setSink: (s) => void (sink = s),
    requestPermission: async () => true,
    start: jest.fn(async (s) => void log.push(`start:${s.regime}`)),
    stop: jest.fn(async () => void log.push('stop')),
    push: (f) => sink?.({ lat: 1, lng: 2, speedKmh: 0, heading: 0, t: 0, ...f }),
    ...overrides,
  };
  return b;
}

const flush = async () => {
  for (let i = 0; i < 20; i++) await Promise.resolve();
};

describe('location source', () => {
  it('asks for permission first and throws when it is refused', async () => {
    const b = backend({ requestPermission: async () => false });
    await expect(createLocationSource(b).start(() => {})).rejects.toThrow('location-permission-denied');
    expect(b.start).not.toHaveBeenCalled();
  });

  it('starts calmly and forwards fixes', async () => {
    const b = backend();
    const seen: Fix[] = [];
    await createLocationSource(b).start((f) => seen.push(f));
    expect(b.log).toEqual(['start:crawl']);
    b.push({ speedKmh: 3 });
    expect(seen).toHaveLength(1);
  });

  it('changes the rate when the speed regime really changes, once', async () => {
    const b = backend();
    await createLocationSource(b).start(() => {});
    b.push({ speedKmh: 100 });
    b.push({ speedKmh: 101 }); // a second fix during the restart must not start another one
    await flush();
    expect(b.log).toEqual(['start:crawl', 'stop', 'start:fast']);
  });

  it('stops everything when the drive ends, also when a change of the rate is under way', async () => {
    const b = backend();
    let releaseStart: () => void = () => {};
    const source = createLocationSource(b);
    await source.start(() => {});
    (b.start as jest.Mock).mockImplementationOnce(() => new Promise<void>((resolve) => (releaseStart = resolve)));
    b.push({ speedKmh: 100 }); // restart begins: stop, then a start that is still pending
    await flush();
    source.stop(); // the user ends the drive meanwhile
    releaseStart();
    await flush();
    expect(b.log[b.log.length - 1]).toBe('stop'); // nothing is left running
  });

  it('does not start the new rate at all when the drive ended before the old updates were stopped', async () => {
    const b = backend();
    let releaseStop: () => void = () => {};
    const source = createLocationSource(b);
    await source.start(() => {});
    (b.stop as jest.Mock).mockImplementationOnce(() => new Promise<void>((resolve) => (releaseStop = () => (b.log.push('stop'), resolve()))));
    b.push({ speedKmh: 100 });
    await flush();
    source.stop();
    releaseStop();
    await flush();
    expect(b.log.filter((l) => l.startsWith('start'))).toEqual(['start:crawl']);
  });

  it('goes back to the old rate once when the new one cannot start', async () => {
    const b = backend();
    await createLocationSource(b).start(() => {});
    (b.start as jest.Mock).mockRejectedValueOnce(new Error('boom'));
    b.push({ speedKmh: 100 });
    await flush();
    expect(b.log).toEqual(['start:crawl', 'stop', 'start:crawl']);
  });

  it('ignores fixes after stop', async () => {
    const b = backend();
    const seen: Fix[] = [];
    const source = createLocationSource(b);
    await source.start((f) => seen.push(f));
    source.stop();
    b.push({ speedKmh: 50 });
    expect(seen).toHaveLength(0);
  });
});
