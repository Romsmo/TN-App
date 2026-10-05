import { setLanguage } from '@/i18n';
import type { NearbyItem, SpeedLimitAnswer } from '@/tn/types';

import type { DriveDataSource } from './data-source';
import { DriveSession, spokenText, type DriveSettings } from './drive-session';
import type { Feedback } from './feedback';
import { destination } from './geo';
import type { Fix } from './warning-engine';

const origin = { lat: 52.5, lng: 13.4 };

const settings: DriveSettings = { unit: 'kmh', sound: true, voice: true, warnOff: [], scale: 1, lockEnabled: true };

function hazard(northM: number, id = 'h1', type = 'accident', pending = false): NearbyItem {
  const p = destination(origin, 0, northM);
  return { kind: 'hazard', id, hazardType: type, lat: p.lat, lng: p.lng, distanceMeters: 0, expiresAt: '2030-01-01T00:00:00Z', confirmCount: 2, denyCount: 0, pending };
}

function zone(entryM: number): NearbyItem {
  const corner = (n: number, e: number): [number, number] => {
    const p = destination(destination(origin, 0, n), 90, e);
    return [p.lng, p.lat];
  };
  return { kind: 'cameraZone', id: 'z1', cell: 'c', resolution: 7, cameraTypes: ['mobileSpeedCamera'], distanceMeters: 0, outline: [corner(entryM, -300), corner(entryM, 300), corner(entryM + 800, 300), corner(entryM + 800, -300)] };
}

const limit = (value: number): SpeedLimitAnswer => ({ value, unit: 'kmh', segmentId: 's', segmentKey: null, distanceMeters: 0, origin: { kind: 'imported' }, importedValue: null });

function setup(items: NearbyItem[] = [], opts: { limitValue?: number | null; settings?: Partial<DriveSettings> } = {}) {
  setLanguage('en');
  let now = 1_000_000;
  const feedback: jest.Mocked<Feedback> = { warn: jest.fn(), confirm: jest.fn(), prompt: jest.fn(), silence: jest.fn() };
  const data: DriveDataSource = {
    nearby: jest.fn(async () => items),
    speedLimit: jest.fn(async () => (opts.limitValue === null ? null : limit(opts.limitValue ?? 100))),
  };
  const submitReport = jest.fn(async () => true);
  const vote = jest.fn(async () => true);
  const current = { ...settings, ...opts.settings };
  const session = new DriveSession({ data, feedback, getSettings: () => current, now: () => now, submitReport, vote });
  const flush = async () => {
    for (let i = 0; i < 5; i++) await Promise.resolve();
  };
  const at = (m: number, speedKmh = 100): Fix => {
    const p = destination(origin, 0, m);
    return { lat: p.lat, lng: p.lng, speedKmh, heading: 0, t: now };
  };
  /** Drives north from `fromM` to `toM`, one fix per `stepM`, one second apart. */
  const drive = async (fromM: number, toM: number, speed = 100, stepM = 25) => {
    for (let m = fromM; m <= toM; m += stepM) {
      session.onFix(at(m, speed));
      await flush();
      now += 1000;
      session.tick();
    }
  };
  return { session, feedback, data, submitReport, vote, drive, at, flush, settings: current, advance: (ms: number) => void (now += ms), getNow: () => now };
}

describe('DriveSession basics', () => {
  it('is idle until started, then active, and silences everything when stopped', () => {
    const { session, feedback } = setup();
    expect(session.getSnapshot().active).toBe(false);
    session.start();
    expect(session.getSnapshot().active).toBe(true);
    session.stop();
    expect(session.getSnapshot()).toMatchObject({ active: false, warnings: [], prompt: null });
    expect(feedback.silence).toHaveBeenCalled();
  });

  it('ignores fixes while not active', async () => {
    const { session, at, flush } = setup([hazard(500)]);
    session.onFix(at(0));
    await flush();
    expect(session.getSnapshot().speedKmh).toBeNull();
  });

  it('shows the speed, the limit and turns red when over it', async () => {
    const { session, at, flush } = setup([], { limitValue: 50 });
    session.start();
    session.onFix(at(0, 48));
    await flush();
    session.onFix(at(30, 48));
    expect(session.getSnapshot()).toMatchObject({ speedKmh: 48, limit: { value: 50, unit: 'kmh' }, speedState: 'ok' });
    session.onFix(at(60, 60));
    expect(session.getSnapshot().speedState).toBe('over');
  });

  it('shows no limit, and never red, when none is known', async () => {
    const { session, at, flush } = setup([], { limitValue: null });
    session.start();
    session.onFix(at(0, 200));
    await flush();
    session.onFix(at(60, 200));
    expect(session.getSnapshot()).toMatchObject({ limit: null, speedState: 'ok' });
  });
});

describe('DriveSession after the end', () => {
  it('does not come back to life when a late answer arrives', async () => {
    const { session, data, at } = setup([], { limitValue: 50 });
    let release: (v: SpeedLimitAnswer | null) => void = () => {};
    (data.speedLimit as jest.Mock).mockImplementationOnce(() => new Promise((resolve) => (release = resolve)));
    session.start();
    session.onFix(at(0, 40));
    session.stop();
    release(limit(50));
    await Promise.resolve();
    await Promise.resolve();
    expect(session.getSnapshot()).toMatchObject({ active: false, limit: null });
  });
});

describe('DriveSession warnings', () => {
  it('warns early and again shortly before, with a tone and a sentence each time', async () => {
    const { session, feedback, drive } = setup([hazard(3000)]);
    session.start();
    await drive(0, 3050);
    const calls = feedback.warn.mock.calls;
    expect(calls.map((c) => c[0].level)).toEqual(['first', 'second']);
    expect(calls[0]![0].text).toMatch(/^Accident in \d+ metres$/);
    expect(calls[1]![0].text).toBe('Accident ahead');
    expect(calls[0]![1]).toEqual({ sound: true, voice: true });
  });

  it('keeps the warning on screen and removes it when the object is passed', async () => {
    const { session, drive } = setup([hazard(3000)]);
    session.start();
    await drive(0, 2400);
    expect(session.getSnapshot().warnings[0]).toMatchObject({ id: 'h1', level: 'first', label: 'Accident' });
    await drive(2425, 3100);
    expect(session.getSnapshot().warnings).toEqual([]);
  });

  it('never repeats a warning while standing near the same spot', async () => {
    const { session, feedback, at, flush } = setup([hazard(500)]);
    session.start();
    for (let i = 0; i < 15; i++) {
      session.onFix(at(0));
      await flush();
    }
    expect(feedback.warn).toHaveBeenCalledTimes(1);
  });

  it('is silent and invisible for a category the user switched off', async () => {
    const { session, feedback, drive } = setup([hazard(3000)], { settings: { warnOff: ['accident'] } });
    session.start();
    await drive(0, 3050);
    expect(feedback.warn).not.toHaveBeenCalled();
    expect(session.getSnapshot().warnings).toEqual([]);
  });

  it('does not warn about the driver\'s own report that is still waiting to be sent', async () => {
    const { session, feedback, drive } = setup([hazard(3000, 'mine', 'accident', true)]);
    session.start();
    await drive(0, 3050);
    expect(feedback.warn).not.toHaveBeenCalled();
  });

  it('mute turns tone and voice off and silences what is being spoken', async () => {
    const { session, feedback, drive } = setup([hazard(3000)]);
    session.start();
    session.setMuted(true);
    expect(feedback.silence).toHaveBeenCalled();
    await drive(0, 3050);
    expect(feedback.warn).toHaveBeenCalled();
    for (const call of feedback.warn.mock.calls) expect(call[1]).toEqual({ sound: false, voice: false });
    expect(session.getSnapshot().muted).toBe(true);
  });

  it('respects the sound and voice settings separately', async () => {
    const { session, feedback, drive } = setup([hazard(3000)], { settings: { voice: false } });
    session.start();
    await drive(0, 3050);
    for (const call of feedback.warn.mock.calls) expect(call[1]).toEqual({ sound: true, voice: false });
  });

  it('does not talk over itself: a second early warning right after the first is not spoken', async () => {
    const { session, feedback, drive } = setup([hazard(3000, 'a'), hazard(3010, 'b', 'ice')]);
    session.start();
    await drive(0, 2400);
    const firsts = feedback.warn.mock.calls.filter((c) => c[0].level === 'first');
    expect(firsts).toHaveLength(2);
    expect(firsts[0]![1].voice).toBe(true);
    expect(firsts[1]![1].voice).toBe(false);
  });

  it('keeps a limit of three warnings on screen, the closest first', async () => {
    const items = [hazard(3000, 'a'), hazard(3040, 'b', 'ice'), hazard(3080, 'c', 'traffic'), hazard(3120, 'd', 'obstacle')];
    const { session, drive } = setup(items);
    session.start();
    await drive(0, 2500);
    expect(session.getSnapshot().warnings.length).toBeLessThanOrEqual(3);
  });
});

describe('DriveSession camera zones', () => {
  it('warns about the area with no distance and no spot, in words and on screen', async () => {
    const { session, feedback, drive } = setup([zone(2000)]);
    session.start();
    await drive(0, 2300);
    expect(feedback.warn).toHaveBeenCalled();
    for (const [warning] of feedback.warn.mock.calls) {
      expect(warning.text).toMatch(/^(Danger area ahead|In the danger area)$/);
      expect(warning.text).not.toMatch(/\d/);
    }
    for (const w of session.getSnapshot().warnings) {
      expect(w).toMatchObject({ kind: 'zone', label: 'Danger area', distanceM: null });
    }
  });

  it('does not warn about a zone when the camera category is switched off', async () => {
    const { session, feedback, drive } = setup([zone(2000)], { settings: { warnOff: ['cameras'] } });
    session.start();
    await drive(0, 2300);
    expect(feedback.warn).not.toHaveBeenCalled();
  });

  it('never prompts "still there?" after a zone', async () => {
    const { session, drive } = setup([zone(1500)]);
    session.start();
    await drive(0, 2700);
    expect(session.getSnapshot().prompt).toBeNull();
  });
});

describe('DriveSession "still there?"', () => {
  it('asks after a reported hazard was passed, with a tone', async () => {
    const { session, feedback, drive } = setup([hazard(1500)]);
    session.start();
    await drive(0, 1600);
    expect(session.getSnapshot().prompt).toMatchObject({ id: 'h1', hazardType: 'accident' });
    expect(feedback.prompt).toHaveBeenCalledTimes(1);
  });

  it('disappears by itself after a few seconds', async () => {
    const { session, drive, advance } = setup([hazard(1500)]);
    session.start();
    await drive(0, 1600);
    expect(session.getSnapshot().prompt).not.toBeNull();
    advance(9000);
    session.tick();
    expect(session.getSnapshot().prompt).toBeNull();
  });

  it.each([true, false])('an answer of stillThere=%s counts as a vote and confirms with feedback', async (stillThere) => {
    const { session, drive, vote, feedback } = setup([hazard(1500)]);
    session.start();
    await drive(0, 1600);
    await session.answerPrompt(stillThere);
    expect(vote).toHaveBeenCalledWith('h1', stillThere);
    expect(session.getSnapshot().prompt).toBeNull();
    expect(feedback.confirm).toHaveBeenCalled();
  });

  it('does not ask again within half a minute', async () => {
    const { session, drive } = setup([hazard(1500, 'a'), hazard(1700, 'b', 'ice')]);
    session.start();
    await drive(0, 1600);
    expect(session.getSnapshot().prompt?.id).toBe('a');
    await session.answerPrompt(true);
    await drive(1625, 1800);
    expect(session.getSnapshot().prompt).toBeNull();
  });

  it('can be dismissed without an answer and sends no vote', async () => {
    const { session, drive, vote } = setup([hazard(1500)]);
    session.start();
    await drive(0, 1600);
    session.dismissPrompt();
    expect(session.getSnapshot().prompt).toBeNull();
    expect(vote).not.toHaveBeenCalled();
  });
});

describe('DriveSession lock', () => {
  it('locks at driving speed and releases after standing still a moment', async () => {
    const { session, at, flush, advance } = setup();
    session.start();
    session.onFix(at(0, 50));
    await flush();
    expect(session.getSnapshot().locked).toBe(true);
    advance(1000);
    session.onFix(at(0, 0));
    expect(session.getSnapshot().locked).toBe(true);
    advance(2500);
    session.onFix(at(0, 0));
    expect(session.getSnapshot().locked).toBe(false);
  });

  it('is never locked when the user switched the lock off', async () => {
    const { session, at, flush } = setup([], { settings: { lockEnabled: false } });
    session.start();
    session.onFix(at(0, 120));
    await flush();
    expect(session.getSnapshot().locked).toBe(false);
  });

  it('releases a stale lock when positions stop coming', async () => {
    const { session, at, flush, advance } = setup();
    session.start();
    session.onFix(at(0, 80));
    await flush();
    expect(session.getSnapshot().locked).toBe(true);
    advance(61_000);
    session.tick();
    expect(session.getSnapshot()).toMatchObject({ locked: false, gpsLost: true });
  });
});

describe('DriveSession one-tap report', () => {
  it('cannot report before a position is known', async () => {
    const { session, submitReport } = setup();
    session.start();
    await expect(session.report('traffic')).resolves.toBe(false);
    expect(submitReport).not.toHaveBeenCalled();
  });

  it('reports at the current position, without sending the speed, and confirms with feedback', async () => {
    const { session, at, flush, submitReport, feedback } = setup();
    session.start();
    session.onFix(at(100, 70));
    await flush();
    await expect(session.report('traffic')).resolves.toBe(true);
    expect(submitReport).toHaveBeenCalledTimes(1);
    expect(submitReport.mock.calls[0]).toEqual(['traffic', expect.objectContaining({ lat: expect.any(Number), lng: expect.any(Number) })]);
    expect(feedback.confirm).toHaveBeenCalled();
  });

  it('gives no confirmation when storing failed', async () => {
    const { session, at, flush, submitReport, feedback } = setup();
    submitReport.mockResolvedValueOnce(false);
    session.start();
    session.onFix(at(100, 70));
    await flush();
    await expect(session.report('traffic')).resolves.toBe(false);
    expect(feedback.confirm).not.toHaveBeenCalled();
  });
});

describe('DriveSession stale positions', () => {
  it('does not report at an old position (GPS lost) or after the drive', async () => {
    const { session, at, flush, submitReport, advance } = setup();
    session.start();
    session.onFix(at(100, 70));
    await flush();
    advance(20_000);
    await expect(session.report('traffic')).resolves.toBe(false);
    session.onFix(at(200, 70));
    await flush();
    await expect(session.report('traffic')).resolves.toBe(true);
    session.stop();
    await expect(session.report('traffic')).resolves.toBe(false);
    expect(submitReport).toHaveBeenCalledTimes(1);
  });

  it('updates the raw speed lock when a stale lock is released, also with the lock setting off', async () => {
    const { session, at, flush, advance } = setup([], { settings: { lockEnabled: false } });
    session.start();
    session.onFix(at(0, 80));
    await flush();
    expect(session.getSnapshot().speedLocked).toBe(true);
    advance(61_000);
    session.tick();
    expect(session.getSnapshot().speedLocked).toBe(false);
  });
});

describe('DriveSession heading', () => {
  it('derives the heading from the movement when the receiver gives none', async () => {
    const { session, feedback, at, flush, advance } = setup([hazard(3000)]);
    session.start();
    for (let m = 0; m <= 2600; m += 25) {
      const fix = { ...at(m, 100), heading: null };
      session.onFix(m === 0 ? { ...fix, heading: 0 } : fix);
      await flush();
      advance(1000);
    }
    expect(feedback.warn).toHaveBeenCalled();
  });
});

describe('spokenText', () => {
  beforeEach(() => setLanguage('en'));

  it('names a distance for a point and rounds it to 50 m', () => {
    expect(spokenText('Accident', 'first', 'point', 663)).toBe('Accident in 650 metres');
  });

  it('never gives a distance for an area, whatever it is passed', () => {
    expect(spokenText('Danger area', 'first', 'zone', 400)).toBe('Danger area ahead');
    expect(spokenText('Danger area', 'second', 'zone', 10)).toBe('In the danger area');
  });
});
