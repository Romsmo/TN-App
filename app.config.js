/**
 * app.json stays the source of truth; this file only adds what depends on the build environment.
 *
 * `EXPO_BASE_URL`: the sub-path the web app is served from (GitHub Pages: `/TN-App`). Empty for a local run.
 * Nothing in here is a secret; EXPO_PUBLIC_* values end up in the bundle and anyone can read them.
 */
module.exports = ({ config }) => ({
  ...config,
  experiments: {
    ...config.experiments,
    ...(process.env.EXPO_BASE_URL ? { baseUrl: process.env.EXPO_BASE_URL } : {}),
  },
});
