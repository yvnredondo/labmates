// LabMates service worker: lets the app open without a connection.
// Network first, so a new version on GitHub shows up as soon as you're online.
// Only the app's own files and its fonts are cached. Sign-in and roster data
// always go straight to Supabase and are never stored here.
const CACHE = 'labmates-v4';
const SHELL = [
  './', './index.html', './app.js', './config.js', './manifest.webmanifest',
  './vendor/supabase-2.117.3.js', './vendor/jspdf-4.2.1.umd.min.js', './icons/icon-192.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;
  const fonts = url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com';
  if (!sameOrigin && !fonts) return; // Supabase and anything else: network only, never cached
  if (sameOrigin && url.search) return; // sign-in links carry one-time codes; don't cache them

  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req).then((hit) => hit || (req.mode === 'navigate' ? caches.match('./index.html') : Response.error())))
  );
});
