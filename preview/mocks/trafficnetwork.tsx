/** A pretend library client with demo data around the invented demo route, so every screen has something to show. */
const CENTER = { lat: 48.2, lng: 11.6 };
const at = (dLat: number, dLng: number) => ({ lat: CENTER.lat + dLat, lng: CENTER.lng + dLng });

export function libraryVersion(): string {
  return '1.1.0 (preview)';
}

type Json = Record<string, unknown>;

/** `#notmodus` in the page address plays a fresh install where no server answers (the emergency mode). */
const EMERGENCY = typeof location !== 'undefined' && location.hash === '#notmodus';

export class TrafficNetworkClient {
  private cameras: boolean;
  private reports: Json[] = [];
  private votes = 0;

  constructor(optionsJson: string) {
    this.cameras = JSON.parse(optionsJson).cameraNamespaceEnabled === true && !EMERGENCY;
  }

  private items(): Json[] {
    const hazard = (id: string, hazardType: string, p: { lat: number; lng: number }, confirmCount: number, denyCount = 0, pending = false): Json => ({
      kind: 'hazard', id, hazardType, lat: p.lat, lng: p.lng, distanceMeters: Math.round(Math.hypot((p.lat - CENTER.lat) * 111_000, (p.lng - CENTER.lng) * 74_000)),
      expiresAt: new Date(Date.now() + 2 * 3_600_000).toISOString(), confirmCount, denyCount, pending,
    });
    const items: Json[] = [
      hazard('h1', 'traffic', at(0.012, 0.018), 7),
      hazard('h2', 'accident', at(-0.01, 0.01), 4, 1),
      hazard('h3', 'construction', at(0.02, -0.012), 12),
      hazard('h4', 'ice', at(-0.018, -0.02), 3),
      hazard('h5', 'obstacle', at(0.004, 0.026), 2),
      ...this.reports,
    ];
    if (this.cameras) {
      // the demo country allows cameras in full: individual devices, the expiring reports, and no zones
      const camera = (id: string, cameraType: string, p: { lat: number; lng: number }): Json => ({
        kind: 'camera', id, cameraType, lat: p.lat, lng: p.lng, distanceMeters: Math.round(Math.hypot((p.lat - CENTER.lat) * 111_000, (p.lng - CENTER.lng) * 74_000)),
      });
      items.push(
        camera('c1', 'fixedSpeedCamera', at(0.008, -0.01)),
        camera('c2', 'redLightCamera', at(-0.004, 0.004)),
        camera('c3', 'distanceControl', at(0.016, 0.006)),
        hazard('h6', 'mobileSpeedCamera', at(-0.012, -0.006), 5),
        hazard('h7', 'trailerCamera', at(0.001, -0.022), 2),
      );
    }
    if (EMERGENCY) return this.reports;
    return items;
  }

  async callAsync(method: string, argsJson: string): Promise<string> {
    const args = argsJson ? (JSON.parse(argsJson) as Json) : {};
    const ok = (value: unknown) => JSON.stringify({ ok: value });
    const down = () => JSON.stringify({ error: { code: 'network', message: 'every server in the current pool failed' } });
    switch (method) {
      case 'getNearby':
        return ok({ items: this.items() });
      case 'getSpeedLimitAt':
        if (EMERGENCY) return ok(null);
        return ok({ value: 50, unit: 'kmh', segmentId: 's', segmentKey: null, distanceMeters: 4, origin: { kind: 'imported' }, importedValue: null });
      case 'updatePosition':
        return ok({ tiles: ['preview'], changed: false });
      case 'planBootstrap':
        if (EMERGENCY) return down();
        return ok({ partitionsTotal: 40, partitionsPending: 0, bytesTotal: 52_000_000, bytesPending: 0 });
      case 'tick':
        if (EMERGENCY) return down();
        return ok({ synced: true, report: { skipped: false, ok: true, staticDataError: null, dynamicDataError: null, submitted: 0, rejected: 0, pendingWrites: this.reports.length } });
      case 'sync':
        if (EMERGENCY) return down();
        return ok({ skipped: false, ok: true, staticDataError: null, dynamicDataError: null, submitted: 0, rejected: 0, pendingWrites: this.reports.length });
      case 'getSyncStatus':
        if (EMERGENCY) return ok({ connection: 'offline', lastSyncedAtUnixMs: Date.now(), pendingWrites: this.reports.length, subscribedTiles: [], staticDataVersion: null, lastErrorCode: 'network', lastErrorMessage: 'every server in the current pool failed', storageBytes: 114_688 });
        return ok({ connection: 'online', lastSyncedAtUnixMs: Date.now() - 42_000, pendingWrites: this.reports.length, subscribedTiles: ['a', 'b'], staticDataVersion: 3, lastErrorCode: null, lastErrorMessage: null, storageBytes: 48_300_000 });
      case 'getNetworkStatus':
        return ok({
          knownNodes: [
            { nodeId: 'n1', address: 'https://node-a.example', tier: 'trusted', backedOff: false },
            { nodeId: 'n2', address: 'https://node-b.example', tier: 'active', backedOff: false },
            { nodeId: 'n3', address: 'https://node-c.example', tier: 'probation', backedOff: true },
          ],
          activeNodes: ['n1', 'n2'], currentNodes: ['n1'], directoryGeneratedAt: null, configVersion: 2, cameraNamespaceEnabled: this.cameras, onlineNetwork: 1280,
        });
      case 'getCameraPolicy':
        return ok({ hostEnabled: this.cameras, active: this.cameras, enabled: true, maxLevel: EMERGENCY ? 'off' : 'full', defaultLevel: EMERGENCY ? 'off' : 'full', byCountry: EMERGENCY ? {} : { DE: 'full' }, zoneResolution: 7, version: '1', notice: { version: '1', text: {} } });
      case 'submitReport': {
        const p = { lat: args.lat as number, lng: args.lng as number };
        this.reports.push({ kind: 'hazard', id: `local-${this.reports.length}`, hazardType: args.type, lat: p.lat, lng: p.lng, distanceMeters: 0, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), confirmCount: 1, denyCount: 0, pending: true });
        return ok({ localId: `local-${this.reports.length}` });
      }
      case 'reportCameraRemoved':
        return ok({ localId: `removal-${++this.votes}` });
      case 'confirmReport':
        return ok({ localId: `vote-${++this.votes}` });
      case 'pollEvents':
        return ok({ events: [] });
      default:
        return JSON.stringify({ error: { code: 'invalidArgument', message: `unknown method ${method}` } });
    }
  }
  startRealtime() {}
  stopRealtime() {}
  setEventListener() {}
  uniffiDestroy() {}
}
