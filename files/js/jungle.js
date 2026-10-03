/* The walkable jungle: an oval trail with an animal clearing at every stop and
   a named wild plant between each pair of animals, a pond with a boardwalk, and
   a forest of procedurally grown Indian trees around it all. */
import * as THREE from "three";
import * as A from "./assets.js";
import * as F from "./flora.js";
import { ANIMALS } from "./data.js";
import { PLANTS } from "./plants.js";
import { rng, smooth, skyDome, addLights, radial, waterNormals, realSky, SUN_DIR } from "./env.js";
import { groundMaterial, trailMaterial, grassTuft } from "./terrain.js";

export const EYE = 1.55;
const RX = 62, RZ = 48;                 // path radii
const POND_R = 14, WATER_Y = -0.35;
const PATH_W = 3.2;

/* ---------------- path ---------------- */
const wobble = th => 1 + 0.07 * Math.sin(3 * th + 0.5) + 0.04 * Math.cos(5 * th);
const pathPts = [];
for (let i = 0; i < 240; i++) {
  const th = (i / 240) * Math.PI * 2, r = wobble(th);
  pathPts.push(new THREE.Vector3(RX * r * Math.cos(th), 0, RZ * r * Math.sin(th)));
}
const curve = new THREE.CatmullRomCurve3(pathPts, true, "centripetal");
curve.arcLengthDivisions = 3000;
const flat = u => curve.getPointAt(((u % 1) + 1) % 1);

/* outside (>1) or inside (<1) the path loop */
function ringPos(x, z) {
  const th = Math.atan2(z / RZ, x / RX);
  return Math.hypot(x / RX, z / RZ) / wobble(th);
}
const coarse = Array.from({ length: 200 }, (_, i) => flat(i / 200));
function pathDist(x, z) {
  let best = 1e9;
  for (let i = 0; i < coarse.length; i++) {
    const a = coarse[i], b = coarse[(i + 1) % coarse.length];
    const abx = b.x - a.x, abz = b.z - a.z;
    const t = Math.max(0, Math.min(1, ((x - a.x) * abx + (z - a.z) * abz) / (abx * abx + abz * abz)));
    const dx = x - a.x - abx * t, dz = z - a.z - abz * t;
    const d = dx * dx + dz * dz;
    if (d < best) best = d;
  }
  return Math.sqrt(best);
}

/* ---------------- stops ----------------
   Animals sit at (i + 0.5) / S around the loop, the pond takes one of those
   slots, and the gaps in between hold the plants (except next to the pond). */
const walkers = ANIMALS.filter(a => a.id !== "duck");      // the ducks live on the pond
const POND_STOP = Math.floor(walkers.length / 2);
const S = walkers.length + 1;
const stopU = i => (i + 0.5) / S;

/* plants in walking order; a second id shares the gap (small plant beside a big one) */
const PLANT_ORDER = [
  ["banyan", "fern"], ["mango"], ["ber"], ["peepal"], ["jackfruit"], ["lantana"], ["neem", "mushroom"],
  ["jamun"], ["karonda"], ["teak"], ["tamarind"], ["datura"], ["bamboo"], ["amla"], ["mulberry"],
  ["palash"], ["bael"], ["gunja"], ["sal"], ["gular"], ["phalsa"], ["semal"], ["coconut"],
  ["sitaphal"], ["mahua"], ["banana"], ["mimosa"],
];
/* how far from the trail centre the trunk stands, by plant */
const SETBACK = { banyan: 10, peepal: 7.5, teak: 6, sal: 6, semal: 7, mahua: 6.5, tamarind: 7, mango: 6.5, jackfruit: 6, jamun: 6, gular: 6, neem: 6,
  bamboo: 5.5, coconut: 4.8, palash: 5, amla: 4.5, bael: 4.5, mulberry: 4.2, sitaphal: 4, ber: 3.8, banana: 4, karonda: 3.3, phalsa: 3.4, lantana: 3.2,
  datura: 2.9, gunja: 3, mimosa: 2.6, fern: 3, mushroom: 2.8 };

const pondP = flat(stopU(POND_STOP));
const inward = new THREE.Vector3(-pondP.x, 0, -pondP.z).normalize();
const PC = pondP.clone().addScaledVector(inward, 11 + POND_R);  // pond centre

/* ---------------- ground ---------------- */
const baseH = (x, z) => 0.35 * Math.sin(x * 0.11) * Math.cos(z * 0.09) + 0.25 * Math.sin((x + z) * 0.21) + 0.15 * Math.cos(x * 0.37 - z * 0.29);
export function groundHeight(x, z) {
  let h = baseH(x, z);
  const rr = ringPos(x, z);
  const e = smooth(1.55, 2.6, rr);                         // hills that close off the world
  h += e * 16 + e * baseH(x * 2.3, z * 2.3) * 4;
  const d = Math.hypot(x - PC.x, z - PC.z);
  if (d < POND_R + 4) h = THREE.MathUtils.lerp(h, -1.7, smooth(POND_R + 4, POND_R - 3, d));
  return h;
}
const pathPoint = u => { const p = flat(u); p.y = groundHeight(p.x, p.z); return p; };
const noise2 = (x, z) => 0.5 + 0.5 * Math.sin(x * 0.13 + Math.sin(z * 0.11) * 2.2) * Math.cos(z * 0.15 - Math.sin(x * 0.07));

function buildGround(clearings) {
  const g = new THREE.PlaneGeometry(460, 460, 180, 180).rotateX(-Math.PI / 2);
  const pos = g.attributes.position, uv = g.attributes.uv;
  const splat = new Float32Array(pos.count * 4), col = new Float32Array(pos.count * 3);
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), z = pos.getZ(i);
    pos.setY(i, groundHeight(x, z));
    uv.setXY(i, x / 4, z / 4);                                     // world-space tiling, one tile = 4 m
    const rr = ringPos(x, z), n = noise2(x, z);
    let grass = 0.35 + 0.65 * n, forest = smooth(1.12, 1.6, rr) * 1.4 + (1 - n) * 0.5 + (rr < 0.85 ? 0.3 : 0), litter = 0, mud = 0;
    if (rr > 0.7 && rr < 1.35) { const pd = pathDist(x, z); litter = smooth(7, 2.2, pd) * 0.9; grass += smooth(9, 3, pd) * 0.4; }
    for (const c of clearings) { const d = Math.hypot(x - c.x, z - c.z); if (d < c.r + 3) { grass += smooth(c.r + 3, c.r * 0.5, d) * 1.2; forest *= 0.5; } }
    const d = Math.hypot(x - PC.x, z - PC.z);
    if (d < POND_R + 6) { mud = smooth(POND_R + 5, POND_R + 1, d) * 2; grass *= 1 - mud * 0.4; }
    splat.set([grass, forest, litter, mud], i * 4);
    const k = 0.82 + 0.3 * noise2(x * 2.7 + 11, z * 2.7 - 5);       // large-scale colour variation
    col.set([k, k, k * 0.96], i * 3);
  }
  g.setAttribute("splat", new THREE.BufferAttribute(splat, 4));
  g.setAttribute("color", new THREE.BufferAttribute(col, 3));
  g.computeVertexNormals();
  const m = new THREE.Mesh(g, groundMaterial());
  m.receiveShadow = true;
  return m;
}

function buildPath() {
  const N = 700, across = [-PATH_W / 2 - 0.9, -PATH_W / 2 + 0.25, 0, PATH_W / 2 - 0.25, PATH_W / 2 + 0.9];
  const alpha = [0, 1, 1, 1, 0];
  const pos = [], col = [], uvs = [], idx = [];
  const r = rng(11);
  for (let i = 0; i <= N; i++) {
    const u = i / N, p = flat(u), t = curve.getTangentAt(u % 1);
    const side = new THREE.Vector3(t.z, 0, -t.x).normalize();
    across.forEach((o, k) => {
      const wig = k === 0 || k === 4 ? (r() - 0.5) * 0.5 : 0;      // ragged edges
      const x = p.x + side.x * (o + wig), z = p.z + side.z * (o + wig);
      pos.push(x, groundHeight(x, z) + 0.05, z);
      uvs.push(x / 2.6, z / 2.6);
      const c = k === 2 ? 0.82 : 0.95 + r() * 0.08;                // centre worn a bit darker
      col.push(c, c * 0.97, c * 0.93, alpha[k]);
    });
    if (i < N) for (let k = 0; k < across.length - 1; k++) {
      const a = i * 5 + k, b = a + 5;
      idx.push(a, b, a + 1, a + 1, b, b + 1);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 4));
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  const m = new THREE.Mesh(g, trailMaterial());
  m.receiveShadow = true;
  m.renderOrder = 1;
  return m;
}

/* planks from the path to the water's edge */
function buildBoardwalk(from, to) {
  const g = new THREE.Group();
  const woodTex = F.photo("bark012_color");
  const wood = new THREE.MeshStandardMaterial({ color: 0xb08a66, map: woodTex, roughness: 0.9 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x6b4a30, map: woodTex, roughness: 0.95 });
  const dir = to.clone().sub(from); dir.y = 0;
  const L = dir.length(); dir.normalize();
  const yaw = Math.atan2(dir.x, dir.z);
  const n = Math.floor(L / 0.36);
  const plank = new THREE.InstancedMesh(new THREE.BoxGeometry(1.9, 0.08, 0.3), wood, n);
  const m = new THREE.Matrix4(), q = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, yaw, 0));
  const deckY = t => Math.max(THREE.MathUtils.lerp(from.y + 0.15, WATER_Y + 0.45, t), groundHeight(from.x + dir.x * L * t, from.z + dir.z * L * t) + 0.12);
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const p = from.clone().addScaledVector(dir, L * t);
    p.y = deckY(t);
    plank.setMatrixAt(i, m.compose(p, q, new THREE.Vector3(1, 1, 1)));
  }
  plank.receiveShadow = true;
  plank.castShadow = true;
  g.add(plank);
  const side = new THREE.Vector3(dir.z, 0, -dir.x);
  for (let t = 0.15; t <= 1.001; t += 0.2) for (const s of [-1, 1]) {
    const p = from.clone().addScaledVector(dir, L * t).addScaledVector(side, 1.0 * s);
    const top = deckY(t) + 0.5;
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.08, top + 2, 6), dark);
    post.position.set(p.x, top - (top + 2) / 2, p.z);
    post.castShadow = true;
    g.add(post);
  }
  return { group: g, deckY };
}

function buildWater() {
  const nm = waterNormals();
  nm.repeat.set(6, 6);
  const mat = new THREE.MeshStandardMaterial({ color: 0x264f4a, roughness: 0.06, metalness: 0, transparent: true, opacity: 0.9, normalMap: nm, normalScale: new THREE.Vector2(0.25, 0.25), envMapIntensity: 1.3 });
  const m = new THREE.Mesh(new THREE.CircleGeometry(POND_R + 2.6, 64).rotateX(-Math.PI / 2), mat);
  m.position.set(PC.x, WATER_Y, PC.z);
  m.receiveShadow = true;
  m.userData.hit = { type: "pond" };
  mat.userData.noToon = true;
  return m;
}

/* anime look: a white foam line round the shore and rings spreading on the water */
function buildFoam() {
  const g = new THREE.Group();
  const white = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.85, depthWrite: false });
  const shore = new THREE.Mesh(new THREE.RingGeometry(POND_R + 1.55, POND_R + 2.05, 96).rotateX(-Math.PI / 2), white);
  g.add(shore);
  const rings = [];
  const r = rng(8);
  for (let i = 0; i < 6; i++) {
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.92, 1, 48).rotateX(-Math.PI / 2), white.clone());
    const a = r() * Math.PI * 2, d = 2 + r() * (POND_R - 4);
    ring.userData = { x: Math.cos(a) * d, z: Math.sin(a) * d, o: i / 6 };
    g.add(ring);
    rings.push(ring);
  }
  g.position.set(PC.x, WATER_Y + 0.03, PC.z);
  g.renderOrder = 3;
  g.visible = false;
  g.userData.update = t => {
    shore.scale.setScalar(1 + Math.sin(t * 1.2) * 0.004);
    for (const ring of rings) {
      const k = (t * 0.25 + ring.userData.o) % 1;
      ring.position.set(ring.userData.x, 0, ring.userData.z);
      ring.scale.setScalar(0.3 + k * 2.4);
      ring.material.opacity = (1 - k) * 0.7;
    }
  };
  return g;
}

/* ---------------- the forest ---------------- */
export const natureUrls = [A.url("nature", "lilypad"), ...["fern", "weed_plant", "shrub_sorrel", "rock_moss_set", "tree_stump"].map(k => A.url("real", k))];
const FILLER_TREES = [["teak", 2], ["sal", 2], ["neem", 1], ["mango", 1], ["jamun", 1], ["mahua", 1], ["tamarind", 1], ["peepal", 1], ["jackfruit", 1], ["gular", 1], ["palash", 1]];

async function buildForest(scene, clearings, boardwalk, density) {
  const r = rng(42);
  const culled = [];
  const blobs = [];
  const blocked = (x, z, pad) => {
    if (Math.hypot(x - PC.x, z - PC.z) < POND_R + 3 + pad) return true;
    for (const c of clearings) if (Math.hypot(x - c.x, z - c.z) < c.r + pad) return true;
    const bx = boardwalk.to.x - boardwalk.from.x, bz = boardwalk.to.z - boardwalk.from.z;
    const t = Math.max(0, Math.min(1, ((x - boardwalk.from.x) * bx + (z - boardwalk.from.z) * bz) / (bx * bx + bz * bz)));
    return Math.hypot(x - boardwalk.from.x - bx * t, z - boardwalk.from.z - bz * t) < 2.2 + pad;
  };
  const ring = (lo, hi) => () => {
    const th = r() * Math.PI * 2, rr = lo + r() * (hi - lo), w = wobble(th);
    return [RX * w * rr * Math.cos(th), RZ * w * rr * Math.sin(th)];
  };
  const nearPath = (lo, hi) => () => {
    const u = r(), p = flat(u), t = curve.getTangentAt(u);
    const s = (r() < 0.5 ? -1 : 1) * (lo + r() * (hi - lo));
    return [p.x + t.z * s, p.z - t.x * s];
  };
  const around = (lo, hi) => () => { const a = r() * Math.PI * 2, d = POND_R + lo + r() * (hi - lo); return [PC.x + Math.cos(a) * d, PC.z + Math.sin(a) * d]; };

  // one kind of plant = one model (built or loaded) + its list of placements
  const kinds = [];
  const kind = (model, h, spread, maxD, blob = 0, name = "") => { const k = { model, h, spread, maxD, blob, mats: [], name }; kinds.push(k); return k; };
  const trees = FILLER_TREES.flatMap(([id, n]) => [...Array(n)].map((_, s) => { const g = F.build(id, 100 + s, true); return kind(F.asModel(g), g.userData.info.h, 0.3, 115, 0.35, id + s); }));
  const bamboo = [1, 2].map(s => { const g = F.build("bamboo", 200 + s, true); return kind(F.asModel(g), g.userData.info.h, 0.25, 105, 0.25, "bamboo" + s); });
  const palms = [1, 2].map(s => { const g = F.build("coconut", 300 + s, true); return kind(F.asModel(g), g.userData.info.h, 0.2, 115, 0.2, "palm" + s); });
  const banana = kind(F.asModel(F.build("banana", 401, true)), 4, 0.2, 70, 0.2);
  const bushes = ["karonda", "lantana", "ber", "phalsa"].map((id, s) => { const g = F.build(id, 500 + s, true); return kind(F.asModel(g), g.userData.info.h, 0.3, 70, 0.45, id); });
  const real = {};
  for (const k of ["fern", "weed_plant", "shrub_sorrel", "rock_moss_set", "tree_stump"]) real[k] = await A.load(A.url("real", k));
  const fern = kind(real.fern, 1.1, 0.35, 45), weeds = kind(real.weed_plant, 0.7, 0.35, 40), sorrel = kind(real.shrub_sorrel, 0.35, 0.3, 32);
  const rocks = kind(real.rock_moss_set, 1.2, 0.6, 80, 0.4), stumps = kind(real.tree_stump, 0.8, 0.3, 60);
  const grass = kind(F.asModel(grassTuft()), 0.55, 0.45, 38, 0, "grass");

  const pick = arr => arr[(r() * arr.length) | 0];
  const put = (k, x, z, hMul = 1) => {
    const h = k.h * (1 - k.spread / 2 + r() * k.spread) * hMul;
    k.mats.push(new THREE.Matrix4().compose(new THREE.Vector3(x, groundHeight(x, z) - 0.06, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, r() * 6.28, 0)), new THREE.Vector3(h, h, h)));
    if (k.blob) blobs.push([x, z, h * k.blob]);
  };
  const scatterN = (list, n, sample, minPath, pad, hMul) => {
    n = Math.round(n * density);
    let tries = 0, made = 0;
    while (made < n && tries++ < n * 30) {
      const [x, z] = sample();
      if (pathDist(x, z) < minPath || blocked(x, z, pad)) continue;
      put(Array.isArray(list) ? pick(list) : list, x, z, hMul);
      made++;
    }
  };

  scatterN(trees, 210, ring(1.22, 2.25), 8, 3);                 // deep jungle outside the loop
  scatterN(bamboo, 34, ring(1.15, 1.9), 6, 2);
  scatterN(trees, 55, ring(0.28, 0.84), 7, 3.5);                // inside the loop, round the pond
  scatterN(palms, 16, around(5, 13), 5, 1.5);
  scatterN(palms, 8, ring(0.35, 0.85), 6, 2);
  scatterN(banana, 10, around(4, 11), 4, 1);
  scatterN(bamboo, 8, ring(0.3, 0.8), 6, 2);
  scatterN(bushes, 150, ring(1.08, 1.9), 3.4, 1);
  scatterN(bushes, 60, ring(0.28, 0.92), 3.4, 1);
  scatterN(fern, 130, nearPath(2.4, 9), 2.3, 0.6);
  scatterN(fern, 60, ring(0.3, 1.7), 3, 0.6);
  scatterN(weeds, 110, nearPath(2.2, 10), 2.1, 0.4);
  scatterN(sorrel, 70, nearPath(2.1, 7), 2.0, 0.3);
  scatterN(rocks, 40, ring(0.3, 1.7), 3.2, 1);
  scatterN(stumps, 12, ring(0.3, 1.7), 3.5, 1);
  scatterN(grass, 4200, nearPath(1.9, 11), 1.9, 0.1);
  scatterN(grass, 1600, ring(0.3, 1.6), 2, 0.1);
  for (let i = 0; i < 900 * density; i++) {                     // lush tufts in every animal clearing
    const c = clearings[(r() * clearings.length) | 0];
    const a = r() * Math.PI * 2, d = c.r * (0.4 + r() * 0.9);
    put(grass, c.x + Math.cos(a) * d, c.z + Math.sin(a) * d);
  }
  // hedges between neighbouring animal clearings
  for (let i = 0; i < S; i++) {
    const u = i / S, p = flat(u), t = curve.getTangentAt(u);
    const out = new THREE.Vector3(t.z, 0, -t.x);
    if (out.x * p.x + out.z * p.z < 0) out.negate();
    for (let k = 0; k < 5; k++) {
      const d = 3.6 + k * 2.3 + r() * 1.2, j = (r() - 0.5) * 2.5;
      const x = p.x + out.x * d + t.x * j, z = p.z + out.z * d + t.z * j;
      if (blocked(x, z, 0.4)) continue;
      put(k < 2 ? pick(bushes) : pick([bamboo[0], bushes[0], bushes[3], trees[0]]), x, z);
    }
  }
  // reeds round the pond, lily pads on it
  const walkA = Math.atan2(-inward.z, -inward.x);
  for (let i = 0; i < 160; i++) {
    const a = r() * Math.PI * 2, d = POND_R + 0.6 + r() * 2.8;
    if (Math.abs(Math.atan2(Math.sin(a - walkA), Math.cos(a - walkA))) < 0.22) continue;
    put(r() < 0.6 ? grass : weeds, PC.x + Math.cos(a) * d, PC.z + Math.sin(a) * d, 1.6);
  }
  const lily = kind(await A.load(A.url("nature", "lilypad")), 0.18, 0.3, 90);
  for (let i = 0; i < 26; i++) {
    const a = r() * Math.PI * 2, d = 2 + r() * (POND_R - 3.5);
    lily.mats.push(new THREE.Matrix4().compose(new THREE.Vector3(PC.x + Math.cos(a) * d, WATER_Y - 0.01, PC.z + Math.sin(a) * d), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, r() * 6.28, 0)), new THREE.Vector3(0.18, 0.18, 0.18)));
  }

  for (const k of kinds) {
    if (!k.mats.length || !k.model) continue;
    const g = A.scatter(k.model, k.mats, { cull: true });
    g.name = k.name + "×" + k.mats.length;
    g.traverse(o => { if (o.isMesh) o.receiveShadow = true; });
    scene.add(g);
    if (g.userData.cull) culled.push({ fn: g.userData.cull, maxD: k.maxD });
  }

  // soft dark spots under the forest — cheaper than real shadows from every tree
  const blob = new THREE.InstancedMesh(new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2),
    new THREE.MeshBasicMaterial({ map: radial("rgba(18,26,8,0.5)", "rgba(18,26,8,0)"), transparent: true, depthWrite: false }), blobs.length);
  const m = new THREE.Matrix4();
  blobs.forEach(([x, z, s], i) => blob.setMatrixAt(i, m.compose(new THREE.Vector3(x, groundHeight(x, z) + 0.08, z), new THREE.Quaternion(), new THREE.Vector3(s * 2.4, 1, s * 2.4))));
  blob.renderOrder = 2;
  scene.add(blob);
  return culled;
}

/* ---------------- animals ---------------- */
const PEDESTAL = { parrot: ["tree_stump", 0.8], owl: ["tree_stump", 0.8], squirrel: ["tree_stump", 0.6], frog: ["rock_moss_set", 0.5] };

function idle(obj, t) {
  const u = obj.userData;
  if (u.mixer) return;
  u.inner.scale.y = u.base * (1 + 0.018 * Math.sin(t * 2.1 + u.phase));
  obj.rotation.y = u.yaw + 0.14 * Math.sin(t * 0.33 + u.phase);
  if (u.hop) obj.position.y = u.y + Math.pow(Math.max(0, Math.sin(t * 2.4 + u.phase)), 6) * u.dims.h * 0.35;
}

function skinnedIdle(obj, t) {
  const u = obj.userData;
  if (!u.mixer || t < (u.nextSwap || 0)) return;
  u.nextSwap = t + 7 + Math.random() * 7;
  const opts = ["Idle", "Idle_2", "Eating", "Idle_2_HeadLow", "Idle_Headlow"].filter(n => u.actions[n]);
  A.play(obj, [opts[(Math.random() * opts.length) | 0]], 0.6);
}

export async function createJungle(isMobile, renderer) {
  const scene = new THREE.Scene();
  scene.userData.kind = "land";
  scene.userData.tone = { mapping: THREE.ACESFilmicToneMapping, exposure: 0.9 };
  scene.background = new THREE.Color(0xb7cdd2);
  scene.fog = new THREE.Fog(0xb4c8c6, 30, 140);
  const sky = realSky(scene, renderer);
  const dome = skyDome(0x4fb0ec, 0xd8f1f6, 0x9dbf8a);        // used by the anime look only
  dome.visible = false;
  scene.add(dome);
  const sun = addLights(scene, { sky: 0xdfe6c8, ground: 0x4a5424, hemi: 1.05, sun: 0xffeccc, sunI: 3.3, mapSize: isMobile ? 1024 : 2048, span: 30 });

  const from = pathPoint(stopU(POND_STOP)).addScaledVector(inward, PATH_W / 2 - 0.2);
  const to = PC.clone().addScaledVector(inward, -(POND_R - 3));
  to.y = WATER_Y;
  const bw = buildBoardwalk(from, to);
  scene.add(bw.group);
  const water = buildWater();
  scene.add(water);
  const foam = buildFoam();
  scene.add(foam);
  const classicWater = { color: water.material.color.clone(), opacity: water.material.opacity, rough: water.material.roughness };
  scene.userData.onStyle = on => {
    foam.visible = on;
    sky.visible = !on;
    dome.visible = on;
    scene.environment = on ? null : scene.userData.env;
    water.material.color.set(on ? 0x46c4e4 : classicWater.color);
    water.material.roughness = on ? 0.35 : classicWater.rough;
    water.material.opacity = on ? 0.9 : classicWater.opacity;
  };

  const hits = [water];
  const labels = [];
  const movers = [];
  const stops = [];
  const clearings = [];
  const flora = [];                                              // the named plants
  const realPed = {};

  let wi = 0;
  for (let i = 0; i < S; i++) {
    const u = stopU(i);
    const p = pathPoint(u);
    if (i === POND_STOP) {
      const cam = to.clone().addScaledVector(inward, -1.2);
      cam.y = bw.deckY(0.93) + EYE;
      stops.push({ i, u, kind: "pond", id: "pond", cam, look: PC.clone().setY(WATER_Y + 0.6), detourFrom: from.clone() });
      continue;
    }
    const sp = walkers[wi++];
    const gltf = await A.load(A.url("animals", sp.models.m));
    const obj = A.instance(gltf, { h: sp.h, len: sp.len, yaw: sp.yaw });
    const d = obj.userData.dims;
    const out = new THREE.Vector3(p.x, 0, p.z).normalize();
    const t = curve.getTangentAt(u);
    const dist = 3.6 + Math.max(d.w, d.l) * 0.55;
    const ax = p.x + out.x * dist + t.x * (i % 2 ? 0.8 : -0.8), az = p.z + out.z * dist + t.z * (i % 2 ? 0.8 : -0.8);
    let ay = groundHeight(ax, az);
    if (PEDESTAL[sp.id]) {
      const [key, ph] = PEDESTAL[sp.id];
      realPed[key] ||= await A.load(A.url("real", key));
      const ped = A.instance(realPed[key], { h: ph });
      ped.position.set(ax, ay - 0.05, az);
      ped.traverse(o => { if (o.isMesh) { o.receiveShadow = true; o.userData.character = false; } });
      scene.add(ped);
      ay += ph - 0.12;
    }
    obj.position.set(ax, ay, az);
    const toCam = Math.atan2(p.x - ax, p.z - az);
    const yaw = toCam + (i % 2 ? 1.05 : -1.05);
    obj.rotation.y = yaw;
    Object.assign(obj.userData, { yaw, y: ay, base: obj.userData.inner.scale.y, phase: i * 1.7, hop: !!sp.hop });
    scene.add(obj);
    if (obj.userData.mixer) A.play(obj, ["Idle", "Idle_2"]);
    movers.push(obj);
    clearings.push({ x: ax, z: az, r: Math.max(d.w, d.l) * 0.6 + 2.2 });

    const hit = new THREE.Mesh(new THREE.BoxGeometry(Math.max(d.w, 0.8) * 1.2, Math.max(d.h, 0.8) * 1.15, Math.max(d.l, 0.8) * 1.2), new THREE.MeshBasicMaterial());
    hit.visible = false;
    hit.position.y = Math.max(d.h, 0.8) * 0.55;
    obj.add(hit);
    hit.userData.hit = { type: "animal", id: sp.id };
    hits.push(hit);

    const look = new THREE.Vector3(ax, ay + d.h * 0.55, az);
    stops.push({ i, u, kind: "animal", id: sp.id, cam: null, look });
    labels.push({ id: sp.id, pos: new THREE.Vector3(ax, ay + d.h + 0.35, az) });
  }
  labels.push({ id: "pond", pos: PC.clone().setY(WATER_Y + 1.6) });

  // the named plants, one gap at a time, on the inner side of the trail
  const gaps = [];
  for (let i = 0; i < S; i++) if (i !== POND_STOP && i !== POND_STOP + 1) gaps.push(i / S);
  const fernModel = await A.load(A.url("real", "fern")), stumpModel = await A.load(A.url("real", "tree_stump"));
  PLANT_ORDER.forEach((ids, gi) => {
    const u = gaps[gi % gaps.length];
    const p = pathPoint(u), t = curve.getTangentAt(u);
    const inn = new THREE.Vector3(-p.x, 0, -p.z).normalize();
    const look = new THREE.Vector3();
    ids.forEach((id, k) => {
      const back = SETBACK[id] || 4;
      const along = k === 0 ? 0 : 3.2;
      const x = p.x + inn.x * back + t.x * along, z = p.z + inn.z * back + t.z * along;
      const y = groundHeight(x, z);
      let g;
      if (id === "fern") { g = A.instance(fernModel, { h: 1.2 }); g.traverse(o => { if (o.isMesh) o.userData.character = false; }); }
      else if (id === "mushroom") {
        g = F.build("mushroom", 1);
        const stump = A.instance(stumpModel, { h: 0.7 });
        stump.traverse(o => { if (o.isMesh) { o.userData.character = false; o.castShadow = o.receiveShadow = true; } });
        stump.position.set(-0.6, -0.05, -0.3);
        g.add(stump);
      } else g = F.build(id, 1);
      g.position.set(x, y - 0.05, z);
      g.rotation.y = Math.atan2(p.x - x, p.z - z);
      g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      scene.add(g);
      const box = new THREE.Box3().setFromObject(g), size = box.getSize(new THREE.Vector3());
      const h = size.y, crownR = Math.max(size.x, size.z) / 2;
      flora.push({ id, group: g });
      clearings.push({ x, z, r: h > 6 ? Math.min(crownR * 0.55, 6) + 1 : Math.max(1.2, crownR * 0.8) });
      // tap target: the trunk and lower crown (or the whole small plant)
      const hw = h > 6 ? Math.min(Math.max(crownR * 0.9, 2), 6) : Math.max(crownR * 2, 1.2);
      const hh = h > 6 ? Math.min(h, 7) : Math.max(h * 1.2, 0.8);
      const hit = new THREE.Mesh(new THREE.BoxGeometry(hw, hh, hw), new THREE.MeshBasicMaterial());
      hit.visible = false;
      hit.position.set(x, y + hh / 2, z);
      hit.userData.hit = { type: "plant", id };
      scene.add(hit);
      hits.push(hit);
      const tag = h > 6 ? Math.min(h * 0.4, 3.4) : h + 0.35;
      const towardPath = new THREE.Vector3(p.x - x, 0, p.z - z).normalize().multiplyScalar(h > 6 ? 1.2 : 0.2);
      labels.push({ id: "p:" + id, pos: new THREE.Vector3(x + towardPath.x, y + tag, z + towardPath.z) });
      look.add(new THREE.Vector3(x, y + Math.min(h * 0.45, 3.2), z));
    });
    look.divideScalar(ids.length);
    stops.push({ u, kind: "plant", id: "p:" + ids[0], ids, cam: null, look });
  });
  stops.sort((a, b) => a.u - b.u);

  // ducks paddle round the pond, one behind the other
  const duckSp = ANIMALS.find(a => a.id === "duck");
  const ducks = [];
  const duckG = await A.load(A.url("animals", "duck")), lingG = await A.load(A.url("animals", "duckling"));
  const drake = A.instance(duckG, { h: 0.75 });
  const hen = A.instance(duckG, { h: 0.7, tint: duckSp.tint.f });
  ducks.push(drake, hen);
  for (let k = 0; k < 4; k++) ducks.push(A.instance(lingG, { h: 0.34 }));
  ducks.forEach((dk, k) => { dk.userData.lag = k < 2 ? k * 0.09 : 0.17 + (k - 2) * 0.055; scene.add(dk); });
  const duckHit = new THREE.Mesh(new THREE.BoxGeometry(1.4, 1.2, 1.6), new THREE.MeshBasicMaterial());
  duckHit.visible = false;
  duckHit.position.y = 0.4;
  duckHit.userData.hit = { type: "animal", id: "duck" };
  drake.add(duckHit);
  hits.push(duckHit);
  const duckLabel = { id: "duck", pos: new THREE.Vector3() };
  labels.push(duckLabel);

  // koi and goldfish glide under the surface
  const swimmers = [];
  for (let k = 0; k < 7; k++) {
    const f = A.instance(await A.load(A.url("fish", k % 2 ? "koi" : "goldfish")), { len: 0.55 + (k % 3) * 0.1 });
    A.play(f, ["Swimming_Normal", "Swim"]);
    f.userData.orbit = { r: 3 + k * 1.3, s: (k % 2 ? 1 : -1) * (0.12 + k * 0.01), a: k * 0.9, y: WATER_Y - 0.55 - (k % 3) * 0.15 };
    scene.add(f);
    swimmers.push(f);
  }

  scene.add(buildGround(clearings), buildPath());
  const culls = await buildForest(scene, clearings, { from, to }, isMobile ? 0.6 : 1);
  const lastCull = { p: new THREE.Vector3(1e9, 0, 0), yaw: 1e9 };

  const focus = new THREE.Vector3();
  const nm = water.material.normalMap;
  const mimosa = flora.find(f => f.id === "mimosa");
  function update(dt, t, camera) {
    F.wind.value = t;
    sky.material.uniforms.time.value = t;
    for (const m of movers) { if (m.userData.mixer) { m.userData.mixer.update(dt); skinnedIdle(m, t); } else idle(m, t); }
    ducks.forEach((dk, k) => {
      const a = t * 0.045 - dk.userData.lag * 6.28 / 6;
      const rr = POND_R - 4.5 + (k % 2) * 0.4;
      const x = PC.x + Math.cos(a) * rr, z = PC.z + Math.sin(a) * rr;
      dk.position.set(x, WATER_Y - 0.08 + Math.sin(t * 2 + k) * 0.02, z);
      dk.rotation.y = Math.atan2(-Math.sin(a), Math.cos(a));
    });
    duckLabel.pos.copy(drake.position).y += 1.1;
    for (const f of swimmers) {
      const o = f.userData.orbit, a = o.a + t * o.s;
      f.position.set(PC.x + Math.cos(a) * o.r, o.y + Math.sin(t + o.a) * 0.08, PC.z + Math.sin(a) * o.r);
      f.rotation.y = Math.atan2(-Math.sin(a) * Math.sign(o.s), Math.cos(a) * Math.sign(o.s));
      f.userData.mixer && f.userData.mixer.update(dt);
    }
    if (mimosa) F.updateFold(mimosa.group, t);
    nm.offset.set(t * 0.01, t * 0.007);
    if (foam.visible) foam.userData.update(t);
    camera.getWorldDirection(focus);
    const yaw = Math.atan2(focus.x, focus.z);
    if (lastCull.p.distanceToSquared(camera.position) > 9 || Math.abs(Math.atan2(Math.sin(yaw - lastCull.yaw), Math.cos(yaw - lastCull.yaw))) > 0.25) {
      for (const c of culls) c.fn(camera.position, focus, c.maxD);
      lastCull.p.copy(camera.position); lastCull.yaw = yaw;
    }
    focus.multiplyScalar(16).add(camera.position);
    sun.target.position.copy(focus);
    sun.position.copy(focus).addScaledVector(SUN_DIR, 70);
  }

  return { scene, stops, hits, labels, update, flora, pondStop: POND_STOP, pathPoint, curve, foldMimosa: t => mimosa && F.fold(mimosa.group, t) };
}

/* ---------------- walking ----------------
   A route is a list of points; each point remembers its path parameter u,
   or null when it is off the path (the boardwalk). */
export function route(stops, fromPos, fromU, onBoardwalk, target) {
  const b = stops[target];
  const pts = [{ p: fromPos.clone(), u: onBoardwalk ? null : fromU }];
  const pond = stops.find(s => s.kind === "pond");
  let u0 = fromU;
  if (onBoardwalk) { pts.push({ p: pond.detourFrom.clone().setY(groundHeight(pond.detourFrom.x, pond.detourFrom.z) + EYE), u: null }); u0 = pond.u; }
  let du = b.u - u0;
  if (du > 0.5) du -= 1;
  if (du < -0.5) du += 1;
  const n = Math.max(2, Math.ceil(Math.abs(du) * 400));
  for (let k = 1; k <= n; k++) {
    const u = u0 + (du * k) / n;
    const p = pathPoint(u); p.y += EYE;
    pts.push({ p, u: ((u % 1) + 1) % 1 });
  }
  if (b.kind === "pond") {
    pts.push({ p: b.detourFrom.clone().setY(groundHeight(b.detourFrom.x, b.detourFrom.z) + EYE), u: null });
    pts.push({ p: b.cam.clone(), u: null });
  }
  let len = 0;
  pts.forEach((q, k) => { q.d = k ? (len += q.p.distanceTo(pts[k - 1].p)) : 0; });
  return { pts, len };
}

export function camAtStop(stop) {
  if (stop.cam) return stop.cam.clone();
  const p = pathPoint(stop.u); p.y += EYE;
  return p;
}
