const CACHE_NAME = 'tc-customer-v13';
const APP_SHELL = [
  'index.html',
  'trips.html',
  'trip.html',
  'free-gifts.html',
  'about.html',
  'contact.html',
  'login.html',
  'dashboard.html',
  'manifest-customer.json',
  'icons/icon-customer-192.png',
  'icons/icon-customer-512.png',
  'the-travel-chapter-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // never touch cross-origin (Supabase, CDN, fonts)

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then((cached) => cached || caches.match('index.html')))
    );
    return;
  }

  // Code assets (i18n.js, page scripts, stylesheets) have no content hash in their
  // URL, so cache-first would strand every future change until CACHE_NAME is bumped.
  // Serve these network-first, falling back to cache only when offline.
  if (req.destination === 'script' || req.destination === 'style' ||
      /\.(?:js|css)$/i.test(url.pathname)) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req))
    );
    return;
  }

  // Everything else (images, icons, manifest) — cache-first.
  event.respondWith(
    caches.match(req).then(
      (cached) =>
        cached ||
        fetch(req).then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
          return res;
        })
    )
  );
});
