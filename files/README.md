# Takatak Zoo — build and deploy notes

A 3D jungle walk for children. Walk an oval path past 28 animals, tap any animal to
meet its family (father, mother, babies and — for egg layers — a nest of eggs) on a
stage the child can spin all the way round. Tap the pond to go under water: fish we
eat swim on one side, fish we don't eat on the other, and each fish opens its own
family view with eggs. Names in English, मराठी and हिंदी, spoken aloud.

```
files/
├── index.html              # page, styles, import map
├── js/
│   ├── data.js             # ALL content: names, family sizes, facts  ← edit this
│   ├── app.js              # UI, walking, tapping, labels, info panel, speech
│   ├── jungle.js           # path, ground, pond, plants, animal clearings
│   ├── family.js           # the 360° family stage (land + underwater)
│   ├── fishworld.js        # under the pond
│   ├── assets.js           # model loading, sizing, instancing, eggs, tadpoles
│   └── env.js              # sky, lights, generated textures
├── vendor/three/           # three.js r186, minified, no CDN needed
├── models/                 # 81 GLB models (4.4 MB), credits.json
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

First visit downloads about 6 MB (models 4.4 MB, three.js 0.9 MB, photos, fonts);
after that it runs offline.

## 3. Things to replace before launch

| Where | What |
|---|---|
| `index.html` `canonical`, `og:url`, `og:image` | `https://example.com/` → your domain |
| `icons/` | 192px, 512px and a maskable 512px PNG (the folder does not exist yet) |
| `og-image.png` | 1200×630 social preview — a screenshot of a family view works well |

## 4. Content

Everything a child reads or hears is in `js/data.js`.

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
fish, deer, zebra, wolf, fox and all plants from Quaternius (CC0). They were compressed
with

```bash
npx @gltf-transform/cli optimize in.glb out.glb --compress meshopt --texture-compress webp --texture-size 512
```

and big plants were simplified first (`gltf-transform simplify --ratio 0.3 --error 0.015`).
Keep new models under ~3k triangles; the plants are drawn hundreds of times.

**Honest gaps**: there is no free peacock or lioness model. The lioness is the cougar
model recoloured, and the peacock is left out (the hornbill stands in as the jungle bird).
Male and female of the same species are usually the same model at different sizes —
exceptions: deer (stag + doe), lion (lion + lioness), duck (drake + recoloured duck).

## 5. Performance

- The jungle draws about 400k triangles on phones and ~600k on desktop, ~170 draw
  calls. Plants are instanced; only plants within 125 m and not behind the camera are
  drawn (refreshed when the camera moves 3 m or turns).
- Phones get 35% fewer plants, 1024px shadow maps and a lower pixel ratio.
- Only animals cast real shadows; trees get painted soft spots, which is far cheaper.

## 6. Honest limits of the "safe" claim

A web page cannot lock a child out of the device. The zoo blocks the context menu,
pinch-zoom and text selection, and asks for fullscreen on phones. It cannot stop `Esc`,
the home gesture, Alt+Tab or the power button. Installing to the Home Screen gets closest.

Speech uses the device's own voices. `hi-IN` is common; `mr-IN` often is not, so Marathi
falls back to a Hindi voice. Recorded audio is the single biggest quality upgrade.

## 7. Ads and analytics — read before you monetise

Content made for children is legally special: **COPPA** (US), GDPR-K (EU) and India's
**DPDP Act 2023**, which requires verifiable parental consent before processing a child's
data and bans behavioural advertising to children.

1. **No ads inside the zoo.** A child tapping animals will tap every ad.
2. Put ads only on written pages for parents, marked child-directed, non-personalised.
3. Analytics: cookieless (Plausible, Cloudflare Web Analytics) or GA4 with signals off.
   The credits dialog says nothing leaves the device — keep that true.

None of this is legal advice.
