/**
 * The one place where network addresses and build-time switches live.
 * Nothing in here is a secret: `EXPO_PUBLIC_*` values end up in the app bundle, anyone can read them.
 */

/** The network's domain. The seed hosts below do not exist in DNS yet (see docs/todo.md). */
export const TN_DOMAIN = 'trafficnetwork.info';

/** Where a fresh install starts looking for servers (discovery). */
export const SEED_SERVERS: readonly string[] = [`https://seed1.${TN_DOMAIN}`, `https://seed2.${TN_DOMAIN}`];

/** Root key of the network (base64url public key). Without it a signed network configuration is ignored by the library. */
export const NETWORK_ROOT_KEY: string | undefined = process.env.EXPO_PUBLIC_TN_NETWORK_ROOT_KEY || undefined;

/**
 * Map background: a MapLibre style URL (target: our own PMTiles/vector tiles).
 * There is deliberately no default. `tile.openstreetmap.org` does not permit app use, and no other source's terms
 * have been verified for app use yet (docs/map-sources.md). Without a style the map shows the Trafficnetwork's own
 * data on a plain background.
 */
export const MAP_STYLE_URL: string | undefined = process.env.EXPO_PUBLIC_MAP_STYLE_URL || undefined;

/** Attribution text shown on the map and in the info area. */
export const MAP_ATTRIBUTION = '© OpenStreetMap contributors';

export const SOURCE_REPO_URL = 'https://github.com/Romsmo/Trafficnetwork';

/** How often the app calls the library's `tick` (the library syncs only when it is due). */
export const TICK_INTERVAL_MS = 10_000;

/** Radius of the map's data query around the map centre, in metres (the library caps it at 50 000). */
export const MAP_QUERY_RADIUS_M = 15_000;
