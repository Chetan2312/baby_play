# Takatak — build and deploy notes

A single-file fullscreen tapping toy for toddlers. Every tap (touch, mouse, or any key) shows one
big letter or number, its word, a picture of that word, and speaks it aloud. English A–Z, मराठी मुळाक्षरे, हिंदी वर्णमाला.

```
takatak/
├── index.html              # whole app: markup + CSS + JS + letter data
├── manifest.webmanifest    # PWA: installs as a fullscreen app
├── sw.js                   # offline cache (bump CACHE on every deploy)
├── pics/                   # 82 word photos, 512px square WebP, freely licensed
├── CREDITS.md              # source + licence for every photo  ← ship this with the app
└── icons/                  # icon-192.png, icon-512.png, icon-maskable-512.png  ← you must add
```

## 1. Run it locally

Service workers and fullscreen need `http(s)`, not `file://`:

```bash
cd takatak
python3 -m http.server 8080
# open http://localhost:8080
```

## 2. Put it on your domain

Cheapest and fastest path: **Cloudflare Pages** (free, global CDN, free TLS).

```bash
git init && git add . && git commit -m "Takatak v0.1"
# push to GitHub, then in Cloudflare dashboard:
# Workers & Pages → Create → Pages → Connect to Git
# Framework preset: None. Build command: (empty). Output directory: /
# Custom domains → add your domain → follow the CNAME/nameserver step
```

Alternatives, same effort: GitHub Pages, Netlify, Vercel. Any static host works — there is no
backend, no database, no build step.

After each deploy, bump `const CACHE = "takatak-v…"` in `sw.js`, or returning visitors keep the
old cached copy. Bump it whenever a picture changes too, not just the HTML.

## 3. Things you must replace before launch

| Where | What |
|---|---|
| `index.html` `<title>`, `<meta description>` | your real name and pitch |
| `index.html` `canonical`, `og:url`, `og:image` | `https://example.com/` → your domain |
| `icons/` | 192px, 512px, and a maskable 512px PNG (safe area: keep art inside the middle 80%) |
| `og-image.png` | 1200×630 social preview |
| `#curtain h1` | the product name, in two spans so the second half takes the accent colour |

## 4. Customising the content

All content lives in one object, `DATA`, at the top of the script. Shape:

```js
["क", "कमळ", "kamal — lotus", "pics/lotus.webp", "🪷"]
//  glyph, word, pronunciation + meaning, photo, emoji fallback
```

- **Pictures** are real photos in `pics/`, 512px square WebP, precached by the service worker so
  the toy still shows them with the plane in flight mode. All are freely licensed but under
  *different* licences — about two thirds CC0 / public domain, the rest CC BY or CC BY-SA.
  [CREDITS.md](CREDITS.md) lists every source and flags the 21 share-alike files to swap if you
  ever need a uniformly CC0 set. Ship CREDITS.md with the app and attribution is covered.
- **The emoji is a fallback**, not decoration: if a photo 404s or fails to decode, that card
  (and every later card using the same file) quietly falls back to the emoji instead of going
  blank. Swap a photo by dropping a new square file at the same path.
- **Numbers** get their picture from `COUNT_PIC` (just below `DATA`), repeated by the number's
  position: ३ shows three mangoes, not the digit again — something a toddler can actually count.
  Zero shows nothing, which is the point. The grid is `ceil(sqrt(n))` wide, so ९ is a tidy 3×3.
- **Adding pictures for a new language:** point the fourth field at any square image in `pics/`
  and add the filename to `PICS` at the top of `sw.js` so it caches offline.

- **Add a language:** add a key with `voice` (a BCP-47 tag such as `gu-IN`), optional `fallback`,
  plus `letters` and `numbers` arrays. Then add one checkbox in the `#langs` block with the same key.
- **Add a mode** (shapes, colours, animals): add the array to each language, add `"shapes"` to the
  `sets` list in `buildDeck()`, add a radio in `#mode`.
- **ण, ळ, ङ, ञ** do not start words. Those rows use a word that *contains* the letter (बाण, बाळ).
  ङ and ञ are left out entirely — add them if you want the complete 48-letter chart.

Design tokens are the CSS variables at the top: `--mango`, `--peacock`, `--rani`, `--lapis`,
`--cream` over `--ink`. Each script also gets its own glyph tint (`.lang-mr`, `.lang-hi`) so a
parent can tell at a glance which chart is on screen.

## 5. Honest limits of the "safe" claim

A web page cannot lock a child out of the device. What this does:

- blocks context menu, text selection, drag, pinch-zoom, scroll, and swipe
- swallows plain keystrokes so typing does nothing but play
- requests fullscreen and a screen wake lock

What it cannot do: stop `Esc`, the iPad home gesture, Alt+Tab, or the power button. Browsers
deliberately forbid that. Installing to the Home Screen (`display: fullscreen`) gets you closest.
Say this plainly on the site — parents trust honest copy, and overclaiming invites bad reviews.

Speech uses the device's own voices. `hi-IN` is common on Android and iOS; `mr-IN` often is not, so
Marathi falls back to a Hindi voice, which mispronounces some words. If Marathi audio matters,
record ~50 short MP3s in a real voice and swap `say()` for an `Audio()` playback map. That is the
single biggest quality upgrade available.

## 6. Ads and analytics — read before you monetise

Content made for children is legally special: **COPPA** in the US, GDPR-K in the EU, and India's
**DPDP Act 2023**, which requires verifiable parental consent before processing a child's data and
bans behavioural advertising to children outright.

Practical rules:

1. **No ads on the toy screen.** Not just for law — a toddler mashing keys will click every ad, and
   ad networks ban accounts for invalid traffic.
2. Put AdSense only on the **written pages for parents** (guides, about, blog). Mark the child-facing
   URLs as child-directed in AdSense and disable personalised ads for them.
3. Analytics: GA4 with `allow_google_signals: false` and IP anonymisation, or a cookieless tool like
   Plausible / Cloudflare Web Analytics. Store no IDs, no fingerprinting — then the privacy line at
   the bottom of the page is true.
4. Better revenue fits for this audience: a paid "premium chart pack", brand sponsorships from
   toy/parenting companies, or an affiliate link to a real letter-chart product.

None of this is legal advice — get an actual lawyer's read before you turn ads on.

## 7. Content pages for SEO (next build)

The toy alone ranks for nothing; the written pages do the ranking and feed the toy.

```
/                 the toy (thin text on purpose)
/about            who made it, why, privacy in plain words
/guides/          hub
  marathi-mulakshare-chart-for-kids
  hindi-varnamala-with-pictures
  screen-time-for-toddlers-what-actually-helps
  keyboard-safe-websites-for-babies
/videos           embedded parent videos + a "tag us" call to action
```

Each guide: one clear question in the H1, a real answer in the first 100 words, an embedded
Takatak link, `Article` + `FAQPage` JSON-LD. Trilingual pages need `hreflang` (`en-IN`, `mr`, `hi`)
and separate URLs — never machine-translate and never stack three languages on one URL.

## 8. Roadmap, in the order I would build it

1. Icons, real domain, deploy. Ship it this week.
2. Recorded Marathi and Hindi audio (biggest felt improvement).
3. Themes as JSON asset packs — same swap pattern as a persona-based product, so a theme is data,
   not code.
4. "Chart mode": after every 26 taps, show the full varnamala grid for two seconds.
5. Parent report: taps per day, letters seen most — all local, nothing sent anywhere.
6. Content pages, then ads on those pages only.
