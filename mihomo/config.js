// Point metacubexd at the mihomo external-controller that nginx reverse-proxies
// on this same origin+path. Deriving the backend from window.location means it
// works behind HA ingress (rotating token path, any HA hostname/scheme) with no
// build-time or per-start substitution: API/websocket calls stay same-origin, so
// there is no CORS and no secret to manage.
(function () {
  var path = window.location.pathname.replace(/\/+$/, '');
  window.__METACUBEXD_CONFIG__ = {
    defaultBackendURL: window.location.origin + path,
    githubToken: '',
  };
})();
