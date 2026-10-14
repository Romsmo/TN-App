import type {
  ApiErrorCode,
  BootstrapPlan,
  CameraPolicy,
  CorrectionReasonCode,
  Coverage,
  NearbyCategory,
  NearbyItem,
  NetworkStatus,
  OfflineMode,
  OfflineRegion,
  OfflineSettings,
  PositionUpdate,
  Proposal,
  ReportLimits,
  SpeedLimitAnswer,
  SpeedLimitLookup,
  SpeedUnit,
  StoragePlan,
  StorageUsage,
  SubmittedReport,
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
    return (await this.submitReportFor(type, lat, lng, { speedKmh })).localId;
  }

  /**
   * The same with a duration the reporter chose (`ttlSeconds`, within `getReportLimits`; 1.2.0). Out of range is
   * `ttlOutOfRange` and nothing is queued. `durationHonoured: false` means the server ignored the request.
   */
  submitReportFor(type: string, lat: number, lng: number, extra: { speedKmh?: number; ttlSeconds?: number } = {}): Promise<SubmittedReport> {
    return this.call('submitReport', { type, lat, lng, speedKmh: extra.speedKmh, ttlSeconds: extra.ttlSeconds });
  }

  /** Default, shortest and longest duration for a type (needs one successful sync; 1.2.0). */
  getReportLimits(type: string): Promise<ReportLimits> {
    return this.call('getReportLimits', { type });
  }

  /** The limit at a spot, with the honest third answer "outside the offline area" instead of a silent "none" (1.2.0). */
  lookupSpeedLimit(lat: number, lng: number, heading?: number): Promise<SpeedLimitLookup> {
    return this.call('lookupSpeedLimit', { lat, lng, heading });
  }

  /** "No limit on record here": proposes a value for a road without one. `roadAlreadyHasLimit` if there is one (1.2.0). */
  reportMissingSpeedLimit(report: { lat: number; lng: number; value: number; unit: SpeedUnit; bearing?: number; reason?: CorrectionReasonCode }): Promise<Proposal> {
    return this.call('reportMissingSpeedLimit', report);
  }

  /** "That limit is wrong": proposes another value for a road that has one. */
  reportWrongSpeedLimit(report: { lat: number; lng: number; proposedValue: number; unit: SpeedUnit; reason?: CorrectionReasonCode }): Promise<Proposal> {
    return this.call('reportWrongSpeedLimit', report);
  }

  getOfflineSettings(): Promise<OfflineSettings> {
    return this.call('getOfflineSettings');
  }

  /** Chooses what is kept of the static data; applied with the next sync. `regions` without a mode switches to `regions`. */
  setOfflineRegions(settings: { mode?: OfflineMode; regions?: string[] }): Promise<OfflineSettings> {
    return this.call('setOfflineRegions', settings);
  }

  /** `maxBytes: null` removes the limit, leaving the key out keeps it. */
  setStorageLimits(limits: { maxBytes?: number | null; wifiOnly?: boolean }): Promise<OfflineSettings> {
    return this.call('setStorageLimits', limits);
  }

  async listOfflineRegions(): Promise<OfflineRegion[]> {
    return (await this.call<{ regions: OfflineRegion[] }>('listOfflineRegions')).regions;
  }

  getStoragePlan(): Promise<StoragePlan> {
    return this.call('getStoragePlan');
  }

  getStorageUsage(): Promise<StorageUsage> {
    return this.call('getStorageUsage');
  }

  getCoverage(lat: number, lng: number): Promise<Coverage> {
    return this.call('getCoverage', { lat, lng });
  }

  /** Votes on a report: still there (`true`) or gone (`false`). Queued like every write. */
  async confirmReport(reportId: string, stillThere: boolean): Promise<string> {
    return (await this.call<{ localId: string }>('confirmReport', { reportId, stillThere })).localId;
  }

  /** "This device is gone": the one vote that exists for permanently installed cameras. Queued like every write. */
  async reportCameraRemoved(cameraId: string): Promise<string> {
    return (await this.call<{ localId: string }>('reportCameraRemoved', { cameraId })).localId;
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
