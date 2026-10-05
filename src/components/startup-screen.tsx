import { useEffect, useState } from 'react';
import { Animated, Image, StyleSheet, useColorScheme, View } from 'react-native';

/** The overlay uses the splash colours of app.json (white / black), not the app's grouped background, so nothing jumps. */
/** Same size as the native splash image (app.json, `imageWidth`), so the hand-over from the system splash is seamless. */
const LOGO_SIZE = 200;
const FADE_MS = 280;

type Props = {
  /** The first connection attempt has finished (successfully or not). */
  ready: boolean;
  /** The logo stays at least this long, so it never just flashes... */
  minMs?: number;
  /** ...and at most this long, however slow the first attempt is. The app is usable behind it. */
  maxMs?: number;
  children: React.ReactNode;
};

/**
 * The start screen: the logo on the system background, over the app, until the first connection attempt is done
 * (at least `minMs`, at most `maxMs`), then a short fade. It carries no text and asks for nothing.
 */
export function StartupGate({ ready, minMs = 900, maxMs = 3000, children }: Props) {
  const dark = useColorScheme() === 'dark';
  const [minElapsed, setMinElapsed] = useState(false);
  const [maxElapsed, setMaxElapsed] = useState(false);
  const [gone, setGone] = useState(false);
  const [opacity] = useState(() => new Animated.Value(1));

  const done = maxElapsed || (minElapsed && ready);

  useEffect(() => {
    const min = setTimeout(() => setMinElapsed(true), minMs);
    const max = setTimeout(() => setMaxElapsed(true), maxMs);
    return () => {
      clearTimeout(min);
      clearTimeout(max);
    };
  }, [minMs, maxMs]);

  useEffect(() => {
    if (!done) return;
    Animated.timing(opacity, { toValue: 0, duration: FADE_MS, useNativeDriver: true }).start(() => setGone(true));
  }, [done, opacity]);

  return (
    <View style={styles.root}>
      {children}
      {gone ? null : (
        <Animated.View
          pointerEvents={done ? 'none' : 'auto'}
          accessibilityElementsHidden={done}
          importantForAccessibility={done ? 'no-hide-descendants' : 'auto'}
          style={[styles.overlay, { backgroundColor: dark ? '#000000' : '#FFFFFF', opacity }]}>
          <Image
            accessibilityLabel="Trafficnetwork"
            source={dark ? require('../../assets/images/splash-icon-dark.png') : require('../../assets/images/splash-icon.png')}
            style={styles.logo}
            resizeMode="contain"
          />
        </Animated.View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  overlay: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center', zIndex: 10 },
  logo: { width: LOGO_SIZE, height: LOGO_SIZE },
});
