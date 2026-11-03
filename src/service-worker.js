const CACHE_PREFIX = `tabletop-fc:${self.registration.scope}:`;
const CACHE_NAME = CACHE_PREFIX + "__BUILD_VERSION__";
const ASSETS = __PRECACHE_ASSETS__;

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      cache.addAll(ASSETS.map((path) => new Request(new URL(path, self.registration.scope), { cache: "reload" }))),
    ),
  );
  // Let updates wait until every old game window closes; never reload a match.
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  const root = new URL(self.registration.scope);
  if (event.request.method !== "GET" || url.origin !== root.origin || !url.pathname.startsWith(root.pathname)) return;
  const isEntry = event.request.mode === "navigate" &&
    (url.pathname === root.pathname || url.pathname === root.pathname + "index.html");
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(isEntry ? new URL("index.html", root).href : event.request);
    return cached || fetch(event.request);
  })());
});
