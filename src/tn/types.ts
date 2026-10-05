/** Shapes of what the client library returns, as documented in client-lib/docs/api.md (v1.1.0). */

export type SpeedUnit = 'kmh' | 'mph';

export type SpeedLimitAnswer = {
  value: number;
  unit: SpeedUnit;
  segmentId: string;
  segmentKey: string | null;
  distanceMeters: number;
  origin:
    | { kind: 'imported' }
    | { kind: 'locallyProposed'; confirmations: number }
    | { kind: 'communityCorrected'; confirmations: number; needsReview: boolean };
  importedValue: number | null;
};

export type HazardItem = {
  kind: 'hazard';
  id: string;
  hazardType: string;
  lat: number;
  lng: number;
  distanceMeters: number;
  /** Null for this device's own report that has not been delivered yet (measured against the real library). */
  expiresAt: string | null;
  confirmCount: number;
  denyCount: number;
  pending: boolean;
};
export type SignItem = { kind: 'sign'; id: string; signType: string; lat: number; lng: number; distanceMeters: number };
export type CameraItem = { kind: 'camera'; id: string; cameraType: string; lat: number; lng: number; distanceMeters: number };
/** An area, not a point: never draw it as a pin. */
export type CameraZoneItem = {
  kind: 'cameraZone';
  id: string;
  cell: string;
  resolution: number;
  /** [lng, lat] corners */
  outline: [number, number][];
  cameraTypes: string[];
  distanceMeters: number;
};
export type NearbyItem = HazardItem | SignItem | CameraItem | CameraZoneItem;
export type NearbyCategory = 'hazards' | 'signs' | 'cameras';

export type SyncReport = {
  skipped: boolean;
  ok: boolean;
  staticDataError: string | null;
  dynamicDataError: string | null;
  submitted: number;
  rejected: number;
  pendingWrites: number;
};
export type TickResult = { synced: boolean; report: SyncReport | null };
export type PositionUpdate = { tiles: string[]; changed: boolean };

export type SyncStatus = {
  connection: 'never' | 'online' | 'offline';
  lastSyncedAtUnixMs: number | null;
  pendingWrites: number;
  subscribedTiles: string[];
  staticDataVersion: number | null;
  lastErrorCode: string | null;
  lastErrorMessage: string | null;
  storageBytes: number | null;
};

export type NodeView = { nodeId: string; address: string; tier: 'probation' | 'active' | 'trusted'; backedOff: boolean };
export type NetworkStatus = {
  knownNodes: NodeView[];
  activeNodes: string[];
  currentNodes: string[];
  directoryGeneratedAt: string | null;
  configVersion: number | null;
  cameraNamespaceEnabled: boolean;
  onlineNode?: number | null;
  onlineNetwork?: number | null;
  onlineEstimated?: boolean | null;
  onlineAsOf?: string | null;
};

export type BootstrapPlan = { partitionsTotal: number; partitionsPending: number; bytesTotal: number; bytesPending: number };

export type CameraLevel = 'off' | 'zones' | 'full';
export type CameraPolicy = {
  hostEnabled: boolean;
  active: boolean;
  enabled: boolean;
  maxLevel: CameraLevel;
  defaultLevel: CameraLevel;
  byCountry: Record<string, CameraLevel>;
  zoneResolution: number | null;
  version: string | null;
  notice: { version: string; text: Record<string, string> };
};

export type TnEvent =
  | { type: 'bootstrapProgress'; partitionsTotal: number; partitionsDone: number; bytesTotal: number; bytesDone: number }
  | { type: 'dataChanged'; entityType: string; entityId: string; eventType: string }
  | { type: 'syncCompleted'; pendingWrites: number }
  | { type: 'syncFailed'; code: string; message: string }
  | { type: 'storageFull' };

export type ApiErrorCode =
  | 'invalidArgument'
  | 'notConfigured'
  | 'notOffered'
  | 'unknownSegment'
  | 'storageFull'
  | 'storage'
  | 'network'
  | 'auth'
  | 'rejected'
  | 'unavailable'
  | 'closed'
  | 'internal';

/** Credentials the user (or the build) provides: see docs/todo.md, "Gerätezugang". */
export type Credentials =
  | { type: 'client'; clientId: string; clientSecret: string }
  | { type: 'app'; appClientId: string; appClientSecret: string };

export type ClientOptions = {
  storagePath: string;
  nodes?: string[];
  discovery?: boolean;
  seeds?: string[];
  networkRootKey?: string;
  credentials?: Credentials;
  cameraNamespaceEnabled?: boolean;
  syncIntervalSeconds?: number;
  configRefreshSeconds?: number;
};
