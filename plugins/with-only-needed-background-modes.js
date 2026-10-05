/**
 * expo-task-manager adds the iOS background mode "fetch" on its own. This app never uses background fetch, and a background
 * mode that is declared but unused is a review problem. Only `location` (drive mode, while it runs) and `audio`
 * (warnings spoken with the screen off) are kept.
 */
const { withInfoPlist } = require('expo/config-plugins');

const KEEP = new Set(['location', 'audio']);

module.exports = function withOnlyNeededBackgroundModes(config) {
  return withInfoPlist(config, (cfg) => {
    cfg.modResults.UIBackgroundModes = (cfg.modResults.UIBackgroundModes ?? []).filter((mode) => KEEP.has(mode));
    return cfg;
  });
};
