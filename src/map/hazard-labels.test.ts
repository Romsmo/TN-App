import { setLanguage } from '@/i18n';

import { hazardLabel } from './hazard-labels';

describe('hazardLabel', () => {
  afterEach(() => setLanguage('de'));

  it('translates the known types', () => {
    setLanguage('de');
    expect(hazardLabel('ice')).toBe('Glätte');
    setLanguage('en');
    expect(hazardLabel('ice')).toBe('Ice');
  });

  it('shows an unknown type as it is', () => {
    expect(hazardLabel('meteorShower')).toBe('meteorShower');
  });

  it('does not mistake other text keys for hazard types', () => {
    expect(hazardLabel('')).toBe('');
  });
});
