# Takatak Zoo — build and deploy notes

A 3D jungle walk for children. Walk an oval trail past 28 animals and 29 named wild
plants. Tap any animal to meet its family (father, mother, babies and — for egg layers —
a nest of eggs) on a stage the child can spin all the way round; tap any plant to see it
with a magnified leaf and its fruit or flower, and learn whether it is safe to eat. Tap the pond to go under water: fish we
eat swim on one side, fish we don't eat on the other, and each fish opens its own
family view with eggs. Names in English, मराठी and हिंदी, spoken aloud.

```
files/
├── index.html              # page, styles, import map
├── js/
│   ├── data.js             # animal + fish content: names, family sizes, facts  ← edit this
│   ├── plants.js           # the 29 jungle plants: names, how to spot, safety  ← edit this
│   ├── flora.js            # grows the plants in code: branches, leaves, fruit, wind
│   ├── terrain.js          # photo-textured ground, dirt trail, grass tufts
│   ├── app.js              # UI, walking, tapping, labels, info panel, speech
│   ├── jungle.js           # path, ground, pond, plants, animal clearings
│   ├── family.js           # the 360° family stage (land + underwater)
│   ├── fishworld.js        # under the pond
│   ├── assets.js           # model loading, sizing, instancing, eggs, tadpoles
│   ├── env.js              # sky, lights, generated textures
│   └── anime.js            # the ✨ anime look: toon shading, outlines, clouds, petals
├── vendor/three/           # three.js r186, minified, no CDN needed
├── models/                 # 86 GLB models (4.8 MB), credits.json; real/ = CC0 scans
├── tex/                    # CC0 photo textures for ground and bark (2.4 MB)
├── pics/                   # photos; 11 are shown in the info panel
├── sw.js                   # offline cache (bump CACHE on every deploy)
├── manifest.webmanifest    # PWA install
└── CREDITS.md              # model + photo licences  ← ship this with the app
```

## 1. Run it locally

ES modules and the service worker need `http(s)`, not `file://`:

```bash
cd files
python3 -m http.server 8080
# open http://localhost:8080
```

The service worker is skipped on `localhost`, so edits show up on refresh.

## 2. Deploy

Any static host (Cloudflare Pages, GitHub Pages, Netlify). No build step: publish the
`files/` folder as the site root. After each deploy bump `const CACHE = "takatak-zoo-v…"`
in `sw.js`, or returning visitors keep the old copy.

First visit downloads about 9 MB (models 4.8 MB, textures 2.4 MB, three.js 0.9 MB, photos, fonts);
after that it runs offline.

## 3. Things to replace before launch

| Where | What |
|---|---|
| `index.html` `canonical`, `og:url`, `og:image` | `https://example.com/` → your domain |
| `icons/` | 192px, 512px and a maskable 512px PNG (the folder does not exist yet) |
| `og-image.png` | 1200×630 social preview — a screenshot of a family view works well |

## 4. Content

Everything a child reads or hears is in `js/data.js` (animals, fish) and `js/plants.js` (plants).

- **Names** are in all three languages. **Fact sheets are English only** — translate the
  `info` blocks to go fully trilingual (the panel shows whichever language is picked).
- **Family size**: `n` is how many babies stand on the stage, `eggs` how many eggs sit in
  the nest. They are chosen to look right, not to be the real average — the real numbers
  are in the `babies` / `eggs` text.
- **Sizes** (`h` or `len`) are display sizes in metres. Small animals are enlarged on
  purpose so a child can see a frog from the path.
- **Add an animal**: drop `models/animals/<key>.glb` in, add an entry to `ANIMALS`, add
  the file to `ASSETS` in `sw.js`. It gets a stop on the path automatically (stops are
  spread evenly, so the path gets a little more crowded). If the model faces sideways,
  set `yaw` (the camel uses `-Math.PI / 2`).
- **Add a fish**: model into `models/fish/`, entry into `FISH` with `edible: true/false`.

### Where the models came from

Poly Pizza (<https://poly.pizza>): land animals from "Poly by Google" (CC-BY 3.0),
fish, deer, zebra, wolf, fox and the lily pads from Quaternius (CC0). Ferns, weeds,
rocks and stumps are CC0 scans from Poly Haven (`models/real/`). They were compressed
with

```bash
npx @gltf-transform/cli optimize in.glb out.glb --compress meshopt --texture-compress webp --texture-size 512
```

and scans were welded and simplified first (`gltf-transform weld`, then `simplify --ratio 0.2–0.35`).
Keep new models under ~3k triangles; the plants are drawn hundreds of times.

**Honest gaps**: there is no free peacock or lioness model. The lioness is the cougar
model recoloured, and the peacock is left out (the hornbill stands in as the jungle bird).
Male and female of the same species are usually the same model at different sizes —
exceptions: deer (stag + doe), lion (lion + lioness), duck (drake + recoloured duck).

## 5. Plants

The trail alternates animal, plant, animal. The plants are listed in `js/plants.js`
(names in 3 languages, how to spot it, season, who eats it, uses, a wow fact, and
`eat: "yes" | "no" | "—"`), and their walking order is `PLANT_ORDER` in `js/jungle.js`.

Every plant is **grown in code** by `js/flora.js` — there are no free models of Indian
jungle species. A recipe (`TREES`, `BUSHES`, or a special builder for palm, banana,
bamboo, vine, touch-me-not and mushrooms) sets height, branching, crown shape, bark, leaf
shape and where fruit or flowers grow. Leaves are painted on a canvas per species
(`LEAF`), so a peepal really has heart-shaped leaves with a drip tip and neem really has
leaflets. The same recipes, with fewer branches (`lite`), fill the forest.

- **Add a plant**: add it to `PLANTS`, give it a recipe in `TREES` or `BUSHES` and a leaf
  in `LEAF`, add it to `PLANT_ORDER` and a `SETBACK` distance.
- **Safety**: poisonous plants (`cat: "danger"`) get an orange tag and a warning in the
  panel. Every panel reminds children never to taste a wild plant without a grown-up.
- **Touch-me-not** folds its leaves when tapped, in the jungle and on its stage.

## 6. Anime look (✨ button)

A switch in the top bar, remembered per device. All in `js/anime.js`, fully reversible:

- soft 3-band cel shading (`MeshToonMaterial`) on everything
- smoothed normals on animals and plants, so low-poly facets become rounded shading
- dark ink outlines on animals only — anime backgrounds are painted without lines
- warm rim light on animals, painted-style sky with cartoon clouds, drifting petals
- pond: bright water, white foam line and ripples; scene changes wipe with a wave pattern

Cost: the outline pass redraws only the animals (~20k triangles). It is a prototype
built on the same models — the next step for a real anime look is new animal models
(big eyes, rounder bodies), e.g. AI image-to-3D from anime-style concept art.

## 7. Performance

- The jungle draws roughly 0.85–1.4M triangles on desktop (more under the big banyan),
  ~210–320 draw calls. Background plants are instanced and culled on the CPU by
  distance (trees 115 m, bushes 70 m, grass 38 m) and by direction, refreshed when the
  camera moves 3 m or turns.
- Phones get 40% fewer plants, 1024px shadow maps and a lower pixel ratio. **This has
  only been checked in a software renderer — test on a real mid-range tablet**, and if it
  stutters, lower the plant counts in `buildForest()` first.
- Only animals and the 29 named plants cast real shadows; the forest gets painted soft
  spots, which is far cheaper.
- Fruit is the hidden cost: each berry is geometry. Keep fruit primitives low-poly.

## 8. Honest limits of the "safe" claim

A web page cannot lock a child out of the device. The zoo blocks the context menu,
pinch-zoom and text selection, and asks for fullscreen on phones. It cannot stop `Esc`,
the home gesture, Alt+Tab or the power button. Installing to the Home Screen gets closest.

Speech uses the device's own voices. `hi-IN` is common; `mr-IN` often is not, so Marathi
falls back to a Hindi voice. Recorded audio is the single biggest quality upgrade.

## 9. Ads and analytics — read before you monetise

Content made for children is legally special: **COPPA** (US), GDPR-K (EU) and India's
**DPDP Act 2023**, which requires verifiable parental consent before processing a child's
data and bans behavioural advertising to children.

1. **No ads inside the zoo.** A child tapping animals will tap every ad.
2. Put ads only on written pages for parents, marked child-directed, non-personalised.
3. Analytics: cookieless (Plausible, Cloudflare Web Analytics) or GA4 with signals off.
   The credits dialog says nothing leaves the device — keep that true.

None of this is legal advice.
