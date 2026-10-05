import { LICENSES } from './licenses';

describe('licences of the direct dependencies', () => {
  it('has a known licence for every package', () => {
    for (const entry of LICENSES) expect([entry.name, entry.license]).not.toEqual([entry.name, 'unknown']);
  });

  it('lists the Trafficnetwork library and the map library', () => {
    expect(LICENSES.find((e) => e.name === '@trafficnetwork/react-native')?.license).toBe('Apache-2.0');
    expect(LICENSES.some((e) => e.name === '@maplibre/maplibre-react-native')).toBe(true);
  });

  it('contains only permissive licences (no copyleft that would need more than a notice)', () => {
    for (const entry of LICENSES) expect(entry.license).toMatch(/^(MIT|Apache-2\.0|BSD-[23]-Clause|ISC)$/);
  });
});
