import { afterUserMove, nextFollowMode, shouldMoveWithPosition } from './follow-mode';

describe('follow mode', () => {
  it('cycles off -> centred -> follows -> off', () => {
    expect(nextFollowMode('off')).toBe('centered');
    expect(nextFollowMode('centered')).toBe('follow');
    expect(nextFollowMode('follow')).toBe('off');
  });

  it('ends when the user moves the map themselves, from every state', () => {
    for (const mode of ['off', 'centered', 'follow'] as const) expect(afterUserMove(mode)).toBe('off');
  });

  it('moves the map with a new position only while following', () => {
    expect(shouldMoveWithPosition('follow')).toBe(true);
    expect(shouldMoveWithPosition('centered')).toBe(false);
    expect(shouldMoveWithPosition('off')).toBe(false);
  });
});
