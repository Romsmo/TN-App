import { t } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import type { NearbyItem, SpeedUnit } from '@/tn/types';

import type { DriveDataSource } from './data-source';
import type { Feedback } from './feedback';
import { bearingDegrees, distanceMeters } from './geo';
import { LockTracker } from './lock';
import { thresholds, WarningEngine, DEFAULT_WARN_CONFIG, type Fix, type WarnCandidate, type WarnEvent } from './warning-engine';
import { speedState, type SpeedState } from './units';

/** The settings the session reads, fresh at every use (they can change while driving, e.g. mute). */
export type DriveSettings = {
  unit: SpeedUnit;
  sound: boolean;
  voice: boolean;
  /** Categories (hazard types, `cameras`) the user does not want warnings for. */
  warnOff: readonly string[];
  /** Stretches or shrinks the warning distances. */
  scale: number;
  lockEnabled: boolean;
};

export type ActiveWarning = {
  id: string;
  level: 'first' | 'second';
  kind: 'point' | 'zone';
  category: string;
  /** What the screen shows ("Unfall", "Gefahrenbereich"). */
  label: string;
  /** Metres to a point object; always null for a zone: an area has no distance to a spot. */
  distanceM: number | null;
  since: number;
};

export type Prompt = { id: string; hazardType: string; since: number };

export type DriveSnapshot = {
  active: boolean;
  simulated: boolean;
  speedKmh: number | null;
  limit: { value: number; unit: SpeedUnit } | null;
  speedState: SpeedState;
  warnings: ActiveWarning[];
  prompt: Prompt | null;
  muted: boolean;
  /** The speed lock is in force (driving above the threshold, lock switched on). */
  locked: boolean;
  /** Driving above the threshold, whatever the user's lock setting says. */
  speedLocked: boolean;
  /** No position for a while. */
  gpsLost: boolean;
};

export type DriveDeps = {
  data: DriveDataSource;
  feedback: Feedback;
  getSettings: () => DriveSettings;
  now: () => number;
  /** One-tap report; resolves true when the report was stored. */
  submitReport: (type: string, position: { lat: number; lng: number }, speedKmh: number | null) => Promise<boolean>;
  /** Vote on a report; resolves true when stored. */
  vote: (reportId: string, stillThere: boolean) => Promise<boolean>;
  simulated?: boolean;
};

const WARNING_SHOWN_MS = 12_000;
const PROMPT_SHOWN_MS = 8_000;
const PROMPT_MIN_GAP_MS = 30_000;
const SPEECH_MIN_GAP_MS = 2_500;
const GPS_LOST_AFTER_MS = 10_000;
const REFRESH_MOVED_M = 200;
const REFRESH_AFTER_MS = 10_000;

const INITIAL: DriveSnapshot = {
  active: false,
  simulated: false,
  speedKmh: null,
  limit: null,
  speedState: 'ok',
  warnings: [],
  prompt: null,
  muted: false,
  locked: false,
  speedLocked: false,
  gpsLost: false,
};

function categoryOf(item: NearbyItem): string | null {
  switch (item.kind) {
    case 'hazard':
      return item.hazardType;
    case 'camera':
    case 'cameraZone':
      return 'cameras';
    default:
      return null;
  }
}

/** The text for a warning event: a point gets a distance, an area never does. */
export function warningLabel(category: string, kind: 'point' | 'zone', source: 'hazard' | 'camera' | 'zone', rawType: string | null): string {
  if (kind === 'zone') return t('drive.zone');
  return hazardLabel(source === 'camera' && rawType ? rawType : category);
}

/**
 * The drive mode's brain. Position fixes go in; speed, limit, warnings, "still there?" prompts and the lock come out as a
 * snapshot. Everything outside (clock, data, speech, haptics, storage of reports) is injected, so the whole flow runs in tests.
 */
export class DriveSession {
  private snap: DriveSnapshot = INITIAL;
  private readonly listeners = new Set<() => void>();
  private readonly engine = new WarningEngine();
  private readonly lock = new LockTracker();
  private items: NearbyItem[] = [];
  private queriedAt: { lat: number; lng: number; at: number } | null = null;
  private querying = false;
  private lastFix: Fix | null = null;
  private lastFixAtMs = 0;
  private previous: Fix | null = null;
  private lastSpeechAt = -Infinity;
  private lastPromptAt = -Infinity;
  private limitAt: { lat: number; lng: number; at: number } | null = null;
  private rawTypes = new Map<string, string>();

  constructor(private readonly deps: DriveDeps) {}

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): DriveSnapshot => this.snap;

  private set(patch: Partial<DriveSnapshot>): void {
    this.snap = { ...this.snap, ...patch };
    this.listeners.forEach((l) => l());
  }

  start(): void {
    this.engine.reset();
    this.lock.reset();
    this.items = [];
    this.queriedAt = null;
    this.lastFix = null;
    this.previous = null;
    this.limitAt = null;
    this.lastFixAtMs = this.deps.now();
    this.set({ ...INITIAL, active: true, simulated: this.deps.simulated ?? false });
  }

  stop(): void {
    this.deps.feedback.silence();
    this.engine.reset();
    this.lock.reset();
    this.set({ ...INITIAL, active: false });
  }

  setMuted(muted: boolean): void {
    if (muted) this.deps.feedback.silence();
    this.set({ muted });
  }

  /** The heading of the fix; when the receiver gives none (standing, slow) it comes from the last clear movement. */
  private headingOf(fix: Fix): number | null {
    if (fix.heading !== null && (fix.speedKmh ?? 0) >= 4) return fix.heading;
    const prev = this.previous;
    if (!prev) return fix.heading;
    if (distanceMeters(prev, fix) < 10) return prev.heading;
    return bearingDegrees(prev, fix);
  }

  onFix(raw: Fix): void {
    if (!this.snap.active) return;
    const now = this.deps.now();
    const settings = this.deps.getSettings();
    const fix: Fix = { ...raw, heading: this.headingOf(raw) };
    if (fix.heading !== null) this.previous = fix;
    this.lastFix = fix;
    this.lastFixAtMs = now;

    const speedLocked = this.lock.update(fix.speedKmh, now);
    const locked = speedLocked && settings.lockEnabled;
    void this.refreshData(fix, now);

    const events = this.engine.update(fix, this.candidates(settings));
    const warnings = this.applyEvents(events, now, settings);
    this.handlePassed(events, now, settings);

    this.set({
      speedKmh: fix.speedKmh,
      speedState: speedState(fix.speedKmh, this.snap.limit),
      warnings,
      locked,
      speedLocked,
      gpsLost: false,
    });
  }

  /** Regular heartbeat (about once a second): lets warnings and the prompt expire, releases a stale lock. */
  tick(): void {
    if (!this.snap.active) return;
    const now = this.deps.now();
    const warnings = this.snap.warnings.filter((w) => now - w.since < WARNING_SHOWN_MS);
    const prompt = this.snap.prompt && now - this.snap.prompt.since < PROMPT_SHOWN_MS ? this.snap.prompt : null;
    const speedLocked = this.lock.tick(now);
    const stillLocked = speedLocked && this.deps.getSettings().lockEnabled;
    const gpsLost = now - this.lastFixAtMs > GPS_LOST_AFTER_MS;
    if (warnings.length !== this.snap.warnings.length || prompt !== this.snap.prompt || stillLocked !== this.snap.locked || gpsLost !== this.snap.gpsLost) {
      this.set({ warnings, prompt, locked: stillLocked, speedLocked, gpsLost });
    }
  }

  private candidates(settings: DriveSettings): WarnCandidate[] {
    const out: WarnCandidate[] = [];
    for (const item of this.items) {
      const category = categoryOf(item);
      if (!category || settings.warnOff.includes(category)) continue;
      if (item.kind === 'hazard' && !item.pending) out.push({ id: item.id, kind: 'point', category, source: 'hazard', lat: item.lat, lng: item.lng });
      else if (item.kind === 'camera') out.push({ id: item.id, kind: 'point', category, source: 'camera', lat: item.lat, lng: item.lng });
      else if (item.kind === 'cameraZone') out.push({ id: item.id, kind: 'zone', category, ring: item.outline });
    }
    return out;
  }

  private async refreshData(fix: Fix, now: number): Promise<void> {
    const moved = this.queriedAt ? distanceMeters(this.queriedAt, fix) : Infinity;
    if (!this.querying && (moved > REFRESH_MOVED_M || !this.queriedAt || now - this.queriedAt.at > REFRESH_AFTER_MS)) {
      this.querying = true;
      this.queriedAt = { lat: fix.lat, lng: fix.lng, at: now };
      try {
        const radius = Math.max(2500, thresholds(fix.speedKmh ?? 0, { ...DEFAULT_WARN_CONFIG, scale: this.deps.getSettings().scale }).first * 1.6);
        this.items = await this.deps.data.nearby(fix.lat, fix.lng, radius);
        this.rawTypes = new Map(this.items.flatMap((i) => (i.kind === 'camera' ? [[i.id, i.cameraType] as [string, string]] : [])));
      } catch {
        // keep what we had: an empty read must not silence warnings that were already known
      } finally {
        this.querying = false;
      }
    }
    const limitMoved = this.limitAt ? distanceMeters(this.limitAt, fix) : Infinity;
    if (limitMoved > 30 || !this.limitAt || now - this.limitAt.at > 3000) {
      this.limitAt = { lat: fix.lat, lng: fix.lng, at: now };
      try {
        const answer = await this.deps.data.speedLimit(fix.lat, fix.lng, fix.heading);
        const limit = answer ? { value: answer.value, unit: answer.unit } : null;
        this.set({ limit, speedState: speedState(this.snap.speedKmh, limit) });
      } catch {
        // no limit shown rather than a wrong one
      }
    }
  }

  private applyEvents(events: WarnEvent[], now: number, settings: DriveSettings): ActiveWarning[] {
    let warnings = this.snap.warnings.filter((w) => now - w.since < WARNING_SHOWN_MS);
    for (const e of events) {
      if (e.type === 'passed') {
        warnings = warnings.filter((w) => w.id !== e.id);
        continue;
      }
      const label = warningLabel(e.category, e.kind, e.source, this.rawTypes.get(e.id) ?? null);
      warnings = [
        ...warnings.filter((w) => w.id !== e.id),
        { id: e.id, level: e.level, kind: e.kind, category: e.category, label, distanceM: e.kind === 'zone' ? null : e.distanceM, since: now },
      ];
      const muted = this.snap.muted;
      const speak = settings.voice && !muted && (e.level === 'second' || now - this.lastSpeechAt >= SPEECH_MIN_GAP_MS);
      if (speak) this.lastSpeechAt = now;
      this.deps.feedback.warn(
        { level: e.level, text: spokenText(label, e.level, e.kind, e.distanceM) },
        { sound: settings.sound && !muted, voice: speak },
      );
    }
    return warnings.sort((a, b) => (a.level === b.level ? b.since - a.since : a.level === 'second' ? -1 : 1)).slice(0, 3);
  }

  private handlePassed(events: WarnEvent[], now: number, settings: DriveSettings): void {
    for (const e of events) {
      if (e.type !== 'passed' || e.source !== 'hazard' || this.snap.prompt || now - this.lastPromptAt < PROMPT_MIN_GAP_MS) continue;
      this.lastPromptAt = now;
      this.set({ prompt: { id: e.id, hazardType: e.category, since: now } });
      this.deps.feedback.prompt({ sound: settings.sound && !this.snap.muted });
    }
  }

  /** The answer to the "still there?" card; it counts as a confirmation or a denial. */
  async answerPrompt(stillThere: boolean): Promise<void> {
    const prompt = this.snap.prompt;
    if (!prompt) return;
    this.set({ prompt: null });
    const ok = await this.deps.vote(prompt.id, stillThere);
    if (ok) this.deps.feedback.confirm({ sound: this.deps.getSettings().sound && !this.snap.muted });
  }

  dismissPrompt(): void {
    if (this.snap.prompt) this.set({ prompt: null });
  }

  /** One-tap report at the current position. Returns false when there is no position yet or storing failed. */
  async report(type: string): Promise<boolean> {
    const fix = this.lastFix;
    if (!fix) return false;
    const ok = await this.deps.submitReport(type, { lat: fix.lat, lng: fix.lng }, fix.speedKmh);
    if (ok) this.deps.feedback.confirm({ sound: this.deps.getSettings().sound && !this.snap.muted });
    return ok;
  }
}

/** The sentence spoken for a warning. A zone is "Gefahrenbereich", never a distance to a spot. */
export function spokenText(label: string, level: 'first' | 'second', kind: 'point' | 'zone', distanceM: number | null): string {
  if (kind === 'zone') return level === 'first' ? t('drive.say.zoneAhead') : t('drive.say.zoneInside');
  if (level === 'second' || distanceM === null) return t('drive.say.second', { what: label });
  return t('drive.say.first', { what: label, distance: Math.round(distanceM / 50) * 50 });
}
