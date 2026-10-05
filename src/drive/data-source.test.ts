import type { TnService } from '@/tn/service';

import { libraryDataSource } from './data-source';

describe('libraryDataSource', () => {
  it('reads from the library client that is current at the time of the call', async () => {
    const first = { getNearby: jest.fn().mockResolvedValue(['a']), getSpeedLimitAt: jest.fn().mockResolvedValue(null) } as unknown as TnService;
    const second = { getNearby: jest.fn().mockResolvedValue(['b']), getSpeedLimitAt: jest.fn().mockResolvedValue(null) } as unknown as TnService;
    let current: TnService | null = first;
    const source = libraryDataSource(() => current);
    await expect(source.nearby(1, 2, 100)).resolves.toEqual(['a']);
    current = second; // the client was rebuilt during the drive
    await expect(source.nearby(1, 2, 100)).resolves.toEqual(['b']);
    expect((first.getNearby as jest.Mock).mock.calls).toHaveLength(1);
  });

  it('answers empty while there is no client', async () => {
    const source = libraryDataSource(() => null);
    await expect(source.nearby(1, 2, 100)).resolves.toEqual([]);
    await expect(source.speedLimit(1, 2, 90)).resolves.toBeNull();
  });

  it('passes the heading on, and leaves it out when unknown', async () => {
    const service = { getNearby: jest.fn(), getSpeedLimitAt: jest.fn().mockResolvedValue(null) } as unknown as TnService;
    const source = libraryDataSource(() => service);
    await source.speedLimit(1, 2, 90);
    await source.speedLimit(1, 2, null);
    expect((service.getSpeedLimitAt as jest.Mock).mock.calls).toEqual([[1, 2, 90], [1, 2, undefined]]);
  });
});
