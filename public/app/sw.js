// Service worker della PWA Bot Spesa.
// Guscio dell'app (/app/*): stale-while-revalidate -> si apre subito anche offline,
// la versione nuova arriva in background e si vede al lancio successivo.
// Chiamate API: sempre rete, mai in cache (i dati offline li gestisce app.js).

const CACHE = 'spesa-shell-v4';
const SHELL = [
  './',
  'app.css',
  'app.js',
  'manifest.json',
  'icons/icon-192.png',
  'icons/apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  const isShell = event.request.method === 'GET' &&
    url.origin === self.location.origin &&
    url.pathname.startsWith('/app/');
  if (!isShell) return;

  event.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(event.request, { ignoreSearch: true });
      const network = fetch(event.request, { cache: 'no-cache' })
        .then((response) => {
          if (response.ok) cache.put(event.request, response.clone());
          return response;
        })
        .catch(() => cached);
      if (cached) {
        event.waitUntil(network);
        return cached;
      }
      return network;
    })
  );
});
