// Learn more: https://docs.expo.dev/guides/customizing-metro/
const path = require('node:path');
const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

/**
 * UI preview (not part of the app): with TN_PREVIEW=1 the native modules are replaced by mocks in preview/mocks, so the
 * real screens can be rendered in a browser (`npm run preview:web`). Without the variable nothing changes.
 */
if (process.env.TN_PREVIEW === '1') {
  const mocks = {
    '@trafficnetwork/react-native': 'trafficnetwork',
    '@maplibre/maplibre-react-native': 'maplibre',
    'expo-secure-store': 'secure-store',
    'expo-file-system': 'file-system',
    'expo-location': 'location',
    'expo-task-manager': 'task-manager',
    'expo-keep-awake': 'noop',
    'expo-audio': 'audio',
    'expo-speech': 'speech',
    'expo-haptics': 'haptics',
    'expo-network': 'network',
  };
  const original = config.resolver.resolveRequest;
  config.resolver.resolveRequest = (context, moduleName, platform) => {
    const mock = mocks[moduleName];
    if (mock) return { type: 'sourceFile', filePath: path.resolve(__dirname, 'preview/mocks', `${mock}.tsx`) };
    return (original ?? context.resolveRequest)(context, moduleName, platform);
  };
}

module.exports = config;
