import { CAMERA_NOTICE, DRIVE_NOTICE_EXTRA, LOCK_WARNING, plain } from './texts';

// The client's wording, character for character. If one of these fails, somebody edited a legally relevant text.
const CAMERA_DE =
  'Hinweis: Das Nutzen von Blitzer-Warnungen während der Fahrt ist in Deutschland verboten — auch, wenn ein Beifahrer sie bedient. In der Schweiz sind solche Hinweise generell unzulässig, in Frankreich nur als allgemeine Gefahrenzonen. Bitte informiere dich über die Regeln in deinem Land.';
const LOCK_DE =
  'Warnung: Die Bedienung eines Smartphones während der Fahrt lenkt ab und ist in vielen Ländern verboten, in Deutschland unter anderem als Handynutzung am Steuer. Wenn du die Fahrsperre abschaltest, bist du allein dafür verantwortlich. Bediene die App nur im Stand oder als Beifahrer.';

describe('legal texts', () => {
  it('has the camera notice in German exactly as specified', () => {
    expect(plain(CAMERA_NOTICE.de)).toBe(CAMERA_DE);
  });

  it('emphasises exactly "während der Fahrt" / "while driving"', () => {
    expect(CAMERA_NOTICE.de.filter((s) => s.strong).map((s) => s.text)).toEqual(['während der Fahrt']);
    expect(CAMERA_NOTICE.en.filter((s) => s.strong).map((s) => s.text)).toEqual(['while driving']);
  });

  it('has the speed lock warning in German exactly as specified', () => {
    expect(LOCK_WARNING.de).toBe(LOCK_DE);
  });

  it('has an English version of every text that says the same things', () => {
    expect(plain(CAMERA_NOTICE.en)).toMatch(/Germany/);
    expect(plain(CAMERA_NOTICE.en)).toMatch(/Switzerland/);
    expect(plain(CAMERA_NOTICE.en)).toMatch(/France/);
    expect(plain(CAMERA_NOTICE.en)).toMatch(/passenger/);
    expect(LOCK_WARNING.en).toMatch(/solely responsible/);
    expect(LOCK_WARNING.en).toMatch(/stationary or as a passenger/);
  });

  it('adds only the operating hint at the first start of the drive mode', () => {
    expect(DRIVE_NOTICE_EXTRA.de).toBe('Bediene die App nur als Beifahrer oder im Stand.');
    expect(DRIVE_NOTICE_EXTRA.en.length).toBeGreaterThan(10);
  });
});
