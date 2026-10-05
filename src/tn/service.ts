import type {
  ApiErrorCode,
  BootstrapPlan,
  CameraPolicy,
  NearbyCategory,
  NearbyItem,
  NetworkStatus,
  PositionUpdate,
  SpeedLimitAnswer,
  SyncReport,
  SyncStatus,
  TickResult,
  TnEvent,
} from './types';

/** The part of the library's client the app uses. The native client implements it; tests use a fake. */
export interface RawClient {
  callAsync(method: string, argsJson: string): Promise<string>;
  startRealtime(): void;
  stopRealtime(): void;
  setEventListener(listener: { onEvent(eventJson: string): void } | undefined): void;
  uniffiDestroy(): void;
}

/** A failure answered by the library (`{"error": {code, message}}`) or an unusable answer. */
export class TnError extends Error {
  constructor(
    readonly code: ApiErrorCode | 'badResponse',
    message: string,
  ) {
    super(message);
    this.name = 'TnError';
  }
}

type Envelope = { ok: unknown } | { error: { code: ApiErrorCode; message: string } };

function unwrap<T>(json: string): T {
  let envelope: Envelope;
  try {
    envelope = JSON.parse(json) as Envelope;
  } catch {
    throw new TnError('badResponse', 'The library answered with something that is not JSON.');
  }
  if (envelope && typeof envelope === 'object' && 'error' in envelope && envelope.error) {
    throw new TnError(envelope.error.code, envelope.error.message);
  }
  if (envelope && typeof envelope === 'object' && 'ok' in envelope) {
    return envelope.ok as T;
  }
  throw new TnError('badResponse', 'The library answered without ok or error.');
}

/** Typed access to the library. Knows method names and argument shapes (api.md), nothing about the UI. */
export class TnService {
  constructor(private readonly raw: RawClient) {}

  private async call<T>(method: string, args: Record<string, unknown> = {}): Promise<T> {
    return unwrap<T>(await this.raw.callAsync(method, JSON.stringify(args)));
  }

  async getNearby(lat: number, lng: number, radiusMeters: number, categories?: NearbyCategory[]): Promise<NearbyItem[]> {
    const result = await this.call<{ items: NearbyItem[] }>('getNearby', { lat, lng, radiusMeters, categories });
    return result.items;
  }

  getSpeedLimitAt(lat: number, lng: number, heading?: number): Promise<SpeedLimitAnswer | null> {
    return this.call('getSpeedLimitAt', { lat, lng, heading });
  }

  updatePosition(lat: number, lng: number, speedKmh?: number): Promise<PositionUpdate> {
    return this.call('updatePosition', { lat, lng, speedKmh });
  }

  sync(): Promise<SyncReport> {
    return this.call('sync');
  }

  tick(): Promise<TickResult> {
    return this.call('tick');
  }

  planBootstrap(): Promise<BootstrapPlan> {
    return this.call('planBootstrap');
  }

  getSyncStatus(): Promise<SyncStatus> {
    return this.call('getSyncStatus');
  }

  getNetworkStatus(): Promise<NetworkStatus> {
    return this.call('getNetworkStatus');
  }

  getCameraPolicy(): Promise<CameraPolicy> {
    return this.call('getCameraPolicy');
  }

  /** Stores a report locally (queue) and returns its local id; it is sent with the next sync. */
  async submitReport(type: string, lat: number, lng: number, speedKmh?: number): Promise<string> {
    return (await this.call<{ localId: string }>('submitReport', { type, lat, lng, speedKmh })).localId;
  }

  /** Votes on a report: still there (`true`) or gone (`false`). Queued like every write. */
  async confirmReport(reportId: string, stillThere: boolean): Promise<string> {
    return (await this.call<{ localId: string }>('confirmReport', { reportId, stillThere })).localId;
  }

  async pollEvents(): Promise<TnEvent[]> {
    return (await this.call<{ events: TnEvent[] }>('pollEvents')).events;
  }

  startRealtime(): void {
    this.raw.startRealtime();
  }

  /** Calls `onEvent` for every event; the library calls from its own thread, JS callbacks are marshalled by the binding. */
  onEvents(onEvent: (event: TnEvent) => void): void {
    this.raw.setEventListener({
      onEvent(json) {
        try {
          onEvent(JSON.parse(json) as TnEvent);
        } catch {
          // an unreadable event is ignored, the next sync catches up
        }
      },
    });
  }

  close(): void {
    this.raw.stopRealtime();
    this.raw.setEventListener(undefined);
    this.raw.uniffiDestroy();
  }
}
