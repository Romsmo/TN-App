import type { ExpressionSpecification } from '@maplibre/maplibre-gl-style-spec';

/** Marker colours per hazard type. Distinct hues that stay readable on light and dark backgrounds; unknown types are grey. */
export const HAZARD_COLORS: Record<string, string> = {
  traffic: '#E8590C',
  ice: '#1C7ED6',
  accident: '#C92A2A',
  construction: '#F59F00',
  breakdown: '#7048E8',
  obstacle: '#0CA678',
  fixedSpeedCamera: '#862E9C',
  mobileSpeedCamera: '#862E9C',
  trailerCamera: '#862E9C',
  redLightCamera: '#862E9C',
  distanceControl: '#862E9C',
  cameras: '#862E9C',
};
export const UNKNOWN_HAZARD_COLOR = '#868E96';

export function hazardColor(type: string): string {
  return HAZARD_COLORS[type] ?? UNKNOWN_HAZARD_COLOR;
}

/** A `match` expression over the feature property `type`. */
export function hazardColorExpression(): ExpressionSpecification {
  const pairs = Object.entries(HAZARD_COLORS).flatMap(([type, color]) => [type, color]);
  return ['match', ['get', 'type'], ...pairs, UNKNOWN_HAZARD_COLOR] as unknown as ExpressionSpecification;
}
