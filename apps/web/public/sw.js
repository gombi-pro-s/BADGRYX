// Hand-written, dependency-free service worker.
//
// Scope is deliberately narrow and honest about what this app can offer
// offline: almost every page needs a live Supabase round-trip (auth,
// lessons, labs, CTF, Mentor), so this worker never touches API routes or
// navigations to authenticated pages beyond a fallback. It only:
//   1. Precaches the static /offline page on install.
//   2. Falls back to /offline for a navigation that fails due to no network.
//   3. Serves /_next/static/ build assets cache-first (immutable, versioned
//      by build hash -- safe to cache forever) with a network fallback.
// It never intercepts API routes, Supabase calls, or any other dynamic page,
// so authenticated content is never served stale from the cache.

const CACHE_NAME = "icorepen-static-v1";
const OFFLINE_URL = "/offline";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.add(OFFLINE_URL)),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))),
    ),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(() => caches.match(OFFLINE_URL).then((cached) => cached ?? Response.error())),
    );
    return;
  }

  if (url.pathname.startsWith("/_next/static/")) {
    event.respondWith(
      caches.open(CACHE_NAME).then(async (cache) => {
        const cached = await cache.match(request);
        if (cached) return cached;
        const response = await fetch(request);
        if (response.ok) cache.put(request, response.clone());
        return response;
      }),
    );
  }
});
