import { CAMERA_TYPES } from '@/map/camera-types';

/**
 * The hazard types a user can report. The library offers no list yet (wish for client-lib 1.2, docs/todo.md), so this
 * is the documented set from server/docs/api.md behind a small interface that a library method can replace.
 *
 * Camera types are not in this list: they are offered by `mapReportTypes` and the drive mode, only where the user
 * switched cameras on and the country policy allows them in full.
 */
export interface ReportCatalog {
  types(): readonly string[];
}

export const interimCatalog: ReportCatalog = {
  types: () => ['traffic', 'accident', 'construction', 'ice', 'breakdown', 'obstacle'],
};

/**
 * What the report sheet on the map offers: the common hazards, plus every camera type, but only where the user has
 * switched cameras on and the country policy allows them in full (never under `zones` or `off`).
 */
export function mapReportTypes(camerasActive: boolean, maxLevel: 'off' | 'zones' | 'full' | null): string[] {
  return [...interimCatalog.types(), ...(camerasActive && maxLevel === 'full' ? CAMERA_TYPES : [])];
}
