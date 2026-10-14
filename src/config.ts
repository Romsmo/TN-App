/**
 * The one place where network addresses and build-time switches live.
 * Nothing in here is a secret: `EXPO_PUBLIC_*` values end up in the app bundle, anyone can read them.
 */

/** The network's domain. The seed hosts below do not exist in DNS yet (see docs/todo.md). */
export const TN_DOMAIN = 'trafficnetwork.info';

/** Where a fresh install starts looking for servers (discovery). */
export const SEED_SERVERS: readonly string[] = [`https://seed1.${TN_DOMAIN}`, `https://seed2.${TN_DOMAIN}`];

/**
 * A server the app tries first, besides the discovery from the seeds. Set by the build (`EXPO_PUBLIC_TN_DEFAULT_NODE`);
 * the web test app uses it to find the operator's server. The user can still enter another address under "Server verbinden".
 */
export const DEFAULT_NODE: string | undefined = process.env.EXPO_PUBLIC_TN_DEFAULT_NODE || undefined;

/**
 * An app key of the network (scope `device-registration`) that lets a fresh install register itself, for builds that are
 * open to everyone (the web test app). **It is public by nature:** it ends up in the bundle and anyone can read it, so it
 * must be an app key of its own with the server's per-key daily cap (`DEVICE_REGISTRATION_RATE_LIMIT_MAX_PER_DAY`), never
 * a personal credential. It is given to the build as a CI variable, never committed.
 */
export const PUBLIC_APP_KEY: { id: string; secret: string } | undefined =
  process.env.EXPO_PUBLIC_TN_APP_CLIENT_ID && process.env.EXPO_PUBLIC_TN_APP_CLIENT_SECRET
    ? { id: process.env.EXPO_PUBLIC_TN_APP_CLIENT_ID, secret: process.env.EXPO_PUBLIC_TN_APP_CLIENT_SECRET }
    : undefined;

/** Root key of the network (base64url public key). Without it a signed network configuration is ignored by the library. */
export const NETWORK_ROOT_KEY: string | undefined = process.env.EXPO_PUBLIC_TN_NETWORK_ROOT_KEY || undefined;

/**
 * Map background: a MapLibre style URL (target: our own PMTiles/vector tiles).
 * There is deliberately no default. `tile.openstreetmap.org` does not permit app use, and no other source's terms
 * have been verified for app use yet (docs/map-sources.md). Without a style the map shows the Trafficnetwork's own
 * data on a plain background.
 */
export const MAP_STYLE_URL: string | undefined = process.env.EXPO_PUBLIC_MAP_STYLE_URL || undefined;
/** Optional second style for the dark appearance; without it the one style is used in both. */
export const MAP_STYLE_URL_DARK: string | undefined = process.env.EXPO_PUBLIC_MAP_STYLE_URL_DARK || undefined;

/** Attribution text shown on the map and in the info area. */
export const MAP_ATTRIBUTION = '© OpenStreetMap contributors';

export const SOURCE_REPO_URL = 'https://github.com/Romsmo/Trafficnetwork';

/** How often the app calls the library's `tick` (the library syncs only when it is due). */
export const TICK_INTERVAL_MS = 10_000;

/** Radius of the map's data query around the map centre, in metres (the library caps it at 50 000). */
export const MAP_QUERY_RADIUS_M = 15_000;

/**
 * Whether the user may switch the speed lock off at all. Default: yes (with the confirmed warning). A build with
 * `EXPO_PUBLIC_ALLOW_DISABLE_DRIVE_LOCK=false` has the lock always on and shows no option, which is the cautious
 * variant for an App Store review build (docs/store-risks.md).
 */
export const ALLOW_DISABLE_DRIVE_LOCK: boolean = process.env.EXPO_PUBLIC_ALLOW_DISABLE_DRIVE_LOCK !== 'false';
