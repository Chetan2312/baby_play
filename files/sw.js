/* Takatak service worker — bump CACHE on every deploy */
const CACHE = "takatak-v3";

const PICS = [
  "./pics/anvil.webp",
  "./pics/apple.webp",
  "./pics/arrow.webp",
  "./pics/ball.webp",
  "./pics/bear.webp",
  "./pics/bow.webp",
  "./pics/building.webp",
  "./pics/camel.webp",
  "./pics/cat.webp",
  "./pics/chalk.webp",
  "./pics/chariot.webp",
  "./pics/clock.webp",
  "./pics/cloud.webp",
  "./pics/coconut.webp",
  "./pics/damru.webp",
  "./pics/deer.webp",
  "./pics/dhol.webp",
  "./pics/diya.webp",
  "./pics/dog.webp",
  "./pics/duck.webp",
  "./pics/elephant.webp",
  "./pics/fish.webp",
  "./pics/flag.webp",
  "./pics/flatbread.webp",
  "./pics/flock.webp",
  "./pics/flowerpot.webp",
  "./pics/forest.webp",
  "./pics/fruit.webp",
  "./pics/ganpati.webp",
  "./pics/garlic.webp",
  "./pics/goat.webp",
  "./pics/grapes.webp",
  "./pics/hill.webp",
  "./pics/house.webp",
  "./pics/igloo.webp",
  "./pics/jackfruit.webp",
  "./pics/jug.webp",
  "./pics/kite.webp",
  "./pics/knowledge.webp",
  "./pics/lion.webp",
  "./pics/lips.webp",
  "./pics/lotus.webp",
  "./pics/mango.webp",
  "./pics/medicine.webp",
  "./pics/mortar.webp",
  "./pics/mother.webp",
  "./pics/nest.webp",
  "./pics/owl.webp",
  "./pics/parrot.webp",
  "./pics/plough.webp",
  "./pics/pomegranate.webp",
  "./pics/queen.webp",
  "./pics/rabbit.webp",
  "./pics/ram-sheep.webp",
  "./pics/ring.webp",
  "./pics/school.webp",
  "./pics/schoolbag.webp",
  "./pics/ship.webp",
  "./pics/spectacles.webp",
  "./pics/spinning-top.webp",
  "./pics/spoon.webp",
  "./pics/stamp.webp",
  "./pics/stream.webp",
  "./pics/sugarcane.webp",
  "./pics/sun.webp",
  "./pics/sweet-lime.webp",
  "./pics/sword.webp",
  "./pics/tamarind.webp",
  "./pics/tap.webp",
  "./pics/tiger.webp",
  "./pics/tomato.webp",
  "./pics/umbrella.webp",
  "./pics/van.webp",
  "./pics/warrior.webp",
  "./pics/watch.webp",
  "./pics/watermelon.webp",
  "./pics/wise-one.webp",
  "./pics/wool.webp",
  "./pics/xylophone.webp",
  "./pics/yajna.webp",
  "./pics/yak.webp",
  "./pics/zebra.webp"
];

const SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png"
].concat(typeof PICS === "undefined" ? [] : PICS);

self.addEventListener("install", e => {
  e.waitUntil(
    // One missing picture must not throw away the whole precache, so each URL
    // is added on its own and failures are tolerated.
    caches.open(CACHE)
      .then(c => Promise.allSettled(SHELL.map(u => c.add(u))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;

  // Navigations: network first, fall back to the cached shell so the toy always opens.
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req).catch(() => caches.match("./index.html"))
    );
    return;
  }

  // Everything else (including Google Fonts): cache first, then fill the cache.
  e.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
      return res;
    }).catch(() => new Response("", { status: 504, statusText: "Offline" })))
  );
});
