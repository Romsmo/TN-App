// TNViewer Web: loads the Trafficnetwork client library (WebAssembly) and registers the service worker.
// A plain script on purpose: Metro never sees the library, and the Content-Security-Policy stays `script-src 'self'`.
// Copied next to the app by scripts/web-postbuild.mjs; no logging in here.
(function () {
  var script = document.currentScript;
  if (!script) return;
  var base = script.src.replace(/[^/]*$/, ''); // e.g. https://romsmo.github.io/TN-App/
  window.__tnBase = base;
  window.__tnLibReady = import(base + 'tnlib/index.js');
  window.__tnLibReady.catch(function () {}); // the app reports a failed load on its first call

  if (!('serviceWorker' in navigator)) return;
  var reloading = false;
  function announce(worker) {
    window.__tnWaiting = worker;
    window.dispatchEvent(new Event('tn-update-available'));
  }
  navigator.serviceWorker
    .register(base + 'sw.js', { scope: base })
    .then(function (registration) {
      if (registration.waiting && navigator.serviceWorker.controller) announce(registration.waiting);
      registration.addEventListener('updatefound', function () {
        var installing = registration.installing;
        if (!installing) return;
        installing.addEventListener('statechange', function () {
          if (installing.state === 'installed' && navigator.serviceWorker.controller) announce(installing);
        });
      });
    })
    .catch(function () {});
  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (reloading) return;
    reloading = true;
    location.reload();
  });
  window.__tnApplyUpdate = function () {
    if (window.__tnWaiting) window.__tnWaiting.postMessage('SKIP_WAITING');
  };
})();
