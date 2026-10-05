import { drivePalette } from '@/drive/palette';

import { colors } from './theme';

/** WCAG relative luminance and contrast ratio. */
function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

describe('contrast (WCAG AA: 4.5 for text)', () => {
  it.each(['light', 'dark'] as const)('the %s theme: text, secondary text and button labels are readable', (scheme) => {
    const c = colors[scheme];
    expect(contrast(c.text, c.background)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(c.text, c.surface)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(c.textSecondary, c.background)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(c.textSecondary, c.surface)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(c.onTint, c.tint)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(c.tint, c.surface)).toBeGreaterThanOrEqual(3); // tint as text on surface (links, plain buttons): large/bold text
    expect(contrast(c.danger, c.background)).toBeGreaterThanOrEqual(4.5);
  });

  it('the drive mode: the speed, the warnings and the buttons are readable, and the over-limit colour stands out', () => {
    const d = drivePalette;
    expect(contrast(d.text, d.background)).toBeGreaterThanOrEqual(7);
    expect(contrast(d.textSecondary, d.background)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(d.over, d.background)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(d.warnFirst, d.background)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(d.onTint, d.tint)).toBeGreaterThanOrEqual(4.5);
    expect(contrast(d.text, d.surface)).toBeGreaterThanOrEqual(7);
    expect(contrast(d.text, d.badge)).toBeGreaterThanOrEqual(4.5);
  });

  it('the drive mode is dark, not glaring', () => {
    expect(luminance(drivePalette.background)).toBeLessThan(0.02);
  });
});
