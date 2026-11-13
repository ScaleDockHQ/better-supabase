// One service worker per scope: offline shell and Web Push share this file.
const CACHE = 'shell-v1';
// Hashed build files stay across deploys: a tab on the previous build still
// needs its chunks. Bump the suffix only when the matching rule changes.
const STATIC_CACHE = 'next-static-v1';
const STATIC_MAX_ENTRIES = 512;
const OFFLINE = '/offline.html';

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.add(OFFLINE)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE && key !== STATIC_CACHE)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

// Never store a private or no-store response, and never replay a POST:
// experimental.useOffline retries Server Actions.
const storable = (response) =>
  response.ok && !/private|no-store/i.test(response.headers.get('cache-control') ?? '');

// /_next/static/service-worker/ keeps a stable URL and must-revalidate; every
// other file under /_next/static is immutable per URL.
const isHashedStatic = (url) =>
  url.pathname.startsWith('/_next/static/') &&
  !url.pathname.startsWith('/_next/static/service-worker/');

const immutable = (response) =>
  storable(response) && /\bimmutable\b/i.test(response.headers.get('cache-control') ?? '');

async function cacheFirst(request) {
  const cache = await caches.open(STATIC_CACHE);
  const hit = await cache.match(request);

  if (hit) {
    return hit;
  }

  const response = await fetch(request);

  if (immutable(response)) {
    try {
      await cache.put(request, response.clone());
      const keys = await cache.keys();
      await Promise.all(
        keys.slice(0, Math.max(0, keys.length - STATIC_MAX_ENTRIES)).map((key) => cache.delete(key)),
      );
    } catch {
      await caches.delete(STATIC_CACHE);
    }
  }

  return response;
}

self.addEventListener('fetch', (event) => {
  const { request } = event;

  if (request.method !== 'GET') {
    return;
  }

  const url = new URL(request.url);

  if (url.origin === self.location.origin && isHashedStatic(url)) {
    event.respondWith(cacheFirst(request));

    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE)));
  }
});

self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(self.registration.showNotification(data.title ?? 'Notification', { body: data.body }));
});
