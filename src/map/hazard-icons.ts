import type { IconName } from '@/components/icon';

const ICONS: Record<string, IconName> = {
  traffic: 'car',
  accident: 'warning',
  construction: 'construct',
  ice: 'snow',
  breakdown: 'build',
  obstacle: 'alert-circle',
  fixedSpeedCamera: 'camera',
  mobileSpeedCamera: 'camera',
  trailerCamera: 'camera',
  redLightCamera: 'camera',
  distanceControl: 'camera',
  cameras: 'camera',
  zone: 'scan-circle',
};

/** The symbol of a hazard type; an unknown type (a newer server) gets a neutral one. */
export function hazardIcon(type: string): IconName {
  return ICONS[type] ?? 'alert-circle';
}
