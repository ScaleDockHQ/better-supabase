// The app's one service worker: Web Push and an offline fallback.
//
// It never stores a private response. Anything whose Cache-Control says
// `private` or `no-store` (every signed-in page, `_rsc` payload and API
// answer) goes to the network only, so a shared device can't show one user's
// data to the next. Offline soft navigations and Server Actions are retried by
// Next.js (`experimental.useOffline`), not by this worker.

const CACHE = "acme-shell-v1";
// Hashed build files live apart from the shell so a deploy never clears them:
// a tab on the previous build still needs its chunks. Bump the suffix only
// when the matching rule changes.
const STATIC_CACHE = "acme-next-static-v1";
const STATIC_MAX_ENTRIES = 512;
const CACHES = new Set([CACHE, STATIC_CACHE]);
const PRECACHE = [
  "/",
  "/offline.html",
  "/manifest.webmanifest",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
];

function storable(response) {
  if (!response.ok || response.type !== "basic") {
    return false;
  }

  const control = response.headers.get("cache-control") ?? "";

  return !/\b(private|no-store)\b/i.test(control);
}

async function precache() {
  const cache = await caches.open(CACHE);

  await Promise.all(
    PRECACHE.map(async (url) => {
      try {
        const response = await fetch(url, { cache: "reload" });

        if (storable(response)) {
          await cache.put(url, response);
        }
      } catch {
        // A URL that fails now is fetched again on the next install.
      }
    }),
  );
}

self.addEventListener("install", (event) => {
  event.waitUntil(precache().then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => !CACHES.has(key))
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

async function networkFirst(request) {
  const cache = await caches.open(CACHE);

  try {
    const response = await fetch(request);

    if (storable(response)) {
      await cache.put(request, response.clone());
    }

    return response;
  } catch (error) {
    const cached = await cache.match(request);

    if (cached) {
      return cached;
    }

    if (request.mode === "navigate") {
      return (
        (await cache.match("/")) ??
        (await cache.match("/offline.html")) ??
        Response.error()
      );
    }

    throw error;
  }
}

// `/_next/static/service-worker/` keeps a stable URL and `must-revalidate`;
// every other file under `/_next/static` is immutable per URL.
function isHashedStatic(url) {
  return (
    url.pathname.startsWith("/_next/static/") &&
    !url.pathname.startsWith("/_next/static/service-worker/")
  );
}

function immutable(response) {
  return (
    storable(response) &&
    /\bimmutable\b/i.test(response.headers.get("cache-control") ?? "")
  );
}

async function trim(cache) {
  const keys = await cache.keys();

  await Promise.all(
    keys
      .slice(0, Math.max(0, keys.length - STATIC_MAX_ENTRIES))
      .map((key) => cache.delete(key)),
  );
}

async function cacheFirst(request) {
  const cache = await caches.open(STATIC_CACHE);
  const cached = await cache.match(request);

  if (cached) {
    return cached;
  }

  const response = await fetch(request);

  if (immutable(response)) {
    try {
      await cache.put(request, response.clone());
      await trim(cache);
    } catch {
      // Out of quota: drop the build cache rather than fail the request.
      await caches.delete(STATIC_CACHE);
    }
  }

  return response;
}

self.addEventListener("fetch", (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== "GET" || url.origin !== self.location.origin) {
    return;
  }

  if (isHashedStatic(url)) {
    event.respondWith(cacheFirst(request));

    return;
  }

  if (url.pathname.startsWith("/api/")) {
    return;
  }

  event.respondWith(networkFirst(request));
});

// The payload is the JSON a Web Push sender writes: { title, body, actionPath }.
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {};

  event.waitUntil(
    self.registration.showNotification(data.title ?? "New notification", {
      body: data.body,
      icon: "/icons/icon-192.png",
      data: { actionPath: data.actionPath ?? "/" },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(self.clients.openWindow(event.notification.data.actionPath));
});
