import { de } from './de';
import { en } from './en';
import { pickLanguage, setLanguage, t } from './index';

describe('i18n', () => {
  afterEach(() => setLanguage('de'));

  it('has the same keys in German and English', () => {
    expect(Object.keys(en).sort()).toEqual(Object.keys(de).sort());
  });

  it('has no empty texts', () => {
    for (const table of [de, en]) {
      for (const [key, text] of Object.entries(table)) {
        expect([key, text.trim().length > 0]).toEqual([key, true]);
      }
    }
  });

  it('uses the same placeholders in both languages', () => {
    const placeholders = (text: string) => (text.match(/\{\w+\}/g) ?? []).sort();
    for (const key of Object.keys(de) as (keyof typeof de)[]) {
      expect([key, placeholders(en[key])]).toEqual([key, placeholders(de[key])]);
    }
  });

  it('picks German only for German devices', () => {
    expect(pickLanguage('de')).toBe('de');
    expect(pickLanguage('fr')).toBe('en');
    expect(pickLanguage(null)).toBe('en');
    expect(pickLanguage(undefined)).toBe('en');
  });

  it('fills placeholders and leaves unknown ones alone', () => {
    setLanguage('en');
    expect(t('settings.version', { version: '1.2.3' })).toBe('Version 1.2.3');
    expect(t('settings.version')).toBe('Version {version}');
  });
});
