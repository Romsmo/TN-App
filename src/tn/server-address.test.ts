import { normalizeServerAddress } from './server-address';

const strict = { allowInsecure: false };
const dev = { allowInsecure: true };

describe('normalizeServerAddress', () => {
  it.each([
    ['node.example.org', 'https://node.example.org'],
    ['  https://node.example.org/ ', 'https://node.example.org'],
    ['https://node.example.org:8443/tn/', 'https://node.example.org:8443/tn'],
    ['HTTPS://Node.Example.org', 'https://node.example.org'],
  ])('accepts %s', (input, expected) => {
    expect(normalizeServerAddress(input, strict)).toEqual({ ok: true, url: expected });
  });

  it.each([
    ['', 'empty'],
    ['   ', 'empty'],
    ['ftp://node.example.org', 'invalid'],
    ['javascript://x', 'invalid'],
    ['https://', 'invalid'],
    ['https://user:pw@node.example.org', 'credentials'],
    ['http://node.example.org', 'insecure'],
  ] as const)('rejects %j as %s', (input, reason) => {
    expect(normalizeServerAddress(input, strict)).toEqual({ ok: false, reason });
  });

  it('allows plain http only when told to (development builds)', () => {
    expect(normalizeServerAddress('http://localhost:3000', dev)).toEqual({ ok: true, url: 'http://localhost:3000' });
    expect(normalizeServerAddress('http://localhost:3000', strict)).toEqual({ ok: false, reason: 'insecure' });
  });
});
