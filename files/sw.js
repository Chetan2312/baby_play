/* Takatak Zoo service worker — bump CACHE on every deploy.
   ASSETS is the whole app: page, code, three.js, every 3D model, the ground and bark
   textures and the photos
   the info panel shows. Regenerate the list if you add models. */
const CACHE = "takatak-zoo-v3";

const ASSETS = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./CREDITS.md",
  "./models/credits.json",
  "./js/anime.js",
  "./js/app.js",
  "./js/assets.js",
  "./js/data.js",
  "./js/env.js",
  "./js/family.js",
  "./js/fishworld.js",
  "./js/flora.js",
  "./js/jungle.js",
  "./js/plants.js",
  "./js/terrain.js",
  "./vendor/three/addons/controls/OrbitControls.js",
  "./vendor/three/addons/effects/OutlineEffect.js",
  "./vendor/three/addons/libs/meshopt_decoder.module.js",
  "./vendor/three/addons/loaders/GLTFLoader.js",
  "./vendor/three/addons/objects/Sky.js",
  "./vendor/three/addons/utils/BufferGeometryUtils.js",
  "./vendor/three/addons/utils/SkeletonUtils.js",
  "./vendor/three/three.core.js",
  "./vendor/three/three.module.js",
  "./models/animals/bear-cub.glb",
  "./models/animals/bear.glb",
  "./models/animals/camel.glb",
  "./models/animals/cheetah.glb",
  "./models/animals/chimpanzee.glb",
  "./models/animals/cobra.glb",
  "./models/animals/crocodile.glb",
  "./models/animals/doe.glb",
  "./models/animals/duck.glb",
  "./models/animals/duckling.glb",
  "./models/animals/elephant.glb",
  "./models/animals/fox.glb",
  "./models/animals/frog.glb",
  "./models/animals/giraffe.glb",
  "./models/animals/gorilla.glb",
  "./models/animals/hippo.glb",
  "./models/animals/hornbill.glb",
  "./models/animals/kangaroo.glb",
  "./models/animals/koala.glb",
  "./models/animals/lion.glb",
  "./models/animals/lioness.glb",
  "./models/animals/monkey.glb",
  "./models/animals/owl.glb",
  "./models/animals/panda.glb",
  "./models/animals/parrot.glb",
  "./models/animals/rabbit.glb",
  "./models/animals/rhino.glb",
  "./models/animals/squirrel.glb",
  "./models/animals/stag.glb",
  "./models/animals/tiger.glb",
  "./models/animals/turtle.glb",
  "./models/animals/wolf.glb",
  "./models/animals/zebra.glb",
  "./models/fish/betta.glb",
  "./models/fish/blue-tang.glb",
  "./models/fish/butterfly-fish.glb",
  "./models/fish/catfish.glb",
  "./models/fish/clownfish.glb",
  "./models/fish/goldfish.glb",
  "./models/fish/grouper.glb",
  "./models/fish/koi.glb",
  "./models/fish/mandarin.glb",
  "./models/fish/moorish-idol.glb",
  "./models/fish/puffer.glb",
  "./models/fish/red-snapper.glb",
  "./models/fish/swordfish.glb",
  "./models/fish/trout.glb",
  "./models/fish/tuna.glb",
  "./models/fish/turbot.glb",
  "./models/nature/bamboo-1.glb",
  "./models/nature/bamboo-2.glb",
  "./models/nature/bamboo-3.glb",
  "./models/nature/bush-1.glb",
  "./models/nature/bush-2.glb",
  "./models/nature/bush-berries.glb",
  "./models/nature/bush-flowers.glb",
  "./models/nature/fern.glb",
  "./models/nature/flowers-1.glb",
  "./models/nature/flowers-2.glb",
  "./models/nature/grass.glb",
  "./models/nature/lilypad.glb",
  "./models/nature/log.glb",
  "./models/nature/mushroom.glb",
  "./models/nature/palm-1.glb",
  "./models/nature/palm-2.glb",
  "./models/nature/palm-3.glb",
  "./models/nature/plant-1.glb",
  "./models/nature/plant-2.glb",
  "./models/nature/rock-moss.glb",
  "./models/nature/rocks-1.glb",
  "./models/nature/rocks-2.glb",
  "./models/nature/stump.glb",
  "./models/nature/tall-grass.glb",
  "./models/nature/tree-1.glb",
  "./models/nature/tree-2.glb",
  "./models/nature/tree-3.glb",
  "./models/nature/tree-4.glb",
  "./models/nature/tree-5.glb",
  "./models/nature/tree-6.glb",
  "./models/nature/vines.glb",
  "./models/nature/willow.glb",
  "./models/real/fern.glb",
  "./models/real/rock_moss_set.glb",
  "./models/real/shrub_sorrel.glb",
  "./models/real/tree_stump.glb",
  "./models/real/weed_plant.glb",
  "./tex/bark001_color.webp",
  "./tex/bark001_normal.webp",
  "./tex/bark005_color.webp",
  "./tex/bark005_normal.webp",
  "./tex/bark012_color.webp",
  "./tex/bark012_normal.webp",
  "./tex/bark013_color.webp",
  "./tex/bark013_normal.webp",
  "./tex/grass004_color.webp",
  "./tex/grass004_normal.webp",
  "./tex/ground020_color.webp",
  "./tex/ground020_normal.webp",
  "./tex/ground024_color.webp",
  "./tex/ground024_normal.webp",
  "./tex/ground037_color.webp",
  "./tex/ground037_normal.webp",
  "./pics/bear.webp",
  "./pics/camel.webp",
  "./pics/coconut.webp",
  "./pics/deer.webp",
  "./pics/duck.webp",
  "./pics/elephant.webp",
  "./pics/jackfruit.webp",
  "./pics/lion.webp",
  "./pics/mango.webp",
  "./pics/owl.webp",
  "./pics/parrot.webp",
  "./pics/rabbit.webp",
  "./pics/tamarind.webp",
  "./pics/tiger.webp",
  "./pics/zebra.webp",
  "./icons/icon-192.png",
  "./icons/icon-512.png"
];

self.addEventListener("install", e => {
  e.waitUntil(
    // One missing file must not throw away the whole precache, so each URL
    // is added on its own and failures are tolerated.
    caches.open(CACHE)
      .then(c => Promise.allSettled(ASSETS.map(u => c.add(u))))
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

  // Navigations: network first, fall back to the cached shell so the zoo always opens.
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
