import { act, render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';

import { StartupGate } from './startup-screen';

beforeEach(() => jest.useFakeTimers());
afterEach(() => jest.useRealTimers());

const logo = () => screen.queryByLabelText('Trafficnetwork');

describe('StartupGate', () => {
  it('shows the logo over the app at first', async () => {
    await render(
      <StartupGate ready={false}>
        <Text>app</Text>
      </StartupGate>,
    );
    expect(logo()).toBeTruthy();
    expect(screen.getByText('app')).toBeTruthy();
  });

  it('keeps the logo for the minimum time even if the app is ready at once, then fades it out', async () => {
    await render(
      <StartupGate ready minMs={900} maxMs={3000}>
        <Text>app</Text>
      </StartupGate>,
    );
    await act(async () => void jest.advanceTimersByTime(500));
    expect(logo()).toBeTruthy();
    await act(async () => void jest.advanceTimersByTime(500)); // 1000 ms: past the minimum, the fade runs
    await act(async () => void jest.advanceTimersByTime(600));
    expect(logo()).toBeNull();
  });

  it('waits for the first attempt, but never longer than the maximum', async () => {
    await render(
      <StartupGate ready={false} minMs={900} maxMs={3000}>
        <Text>app</Text>
      </StartupGate>,
    );
    await act(async () => void jest.advanceTimersByTime(2500));
    expect(logo()).toBeTruthy();
    await act(async () => void jest.advanceTimersByTime(1000));
    await act(async () => void jest.advanceTimersByTime(600));
    expect(logo()).toBeNull();
  });
});
