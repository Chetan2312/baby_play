/* The walkable jungle: an oval path with an animal clearing at every stop,
   a pond with a boardwalk, and a lot of instanced plants. */
import * as THREE from "three";
import * as A from "./assets.js";
import { ANIMALS } from "./data.js";
import { rng, smooth, skyDome, addLights, radial, waterNormals } from "./env.js";

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

/* ---------------- stops ---------------- */
const walkers = ANIMALS.filter(a => a.id !== "duck");      // the ducks live on the pond
const POND_STOP = Math.floor(walkers.length / 2);
const S = walkers.length + 1;
const stopU = i => (i + 0.5) / S;

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

function buildGround() {
  const g = new THREE.PlaneGeometry(460, 460, 230, 230).rotateX(-Math.PI / 2);
  const pos = g.attributes.position, col = new Float32Array(pos.count * 3);
  const c = new THREE.Color(), r = rng(3);
  const grassA = new THREE.Color(0x6fa83c), grassB = new THREE.Color(0x4e8a2e), dark = new THREE.Color(0x365f24);
  const sand = new THREE.Color(0xd9c38c), mud = new THREE.Color(0x3f6f6a), trail = new THREE.Color(0x9b9a4a);
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), z = pos.getZ(i);
    pos.setY(i, groundHeight(x, z));
    const n = 0.5 + 0.5 * Math.sin(x * 0.23 + Math.sin(z * 0.17) * 2) * Math.cos(z * 0.19);
    c.copy(grassA).lerp(grassB, n * 0.8 + r() * 0.2);
    const rr = ringPos(x, z);
    c.lerp(dark, smooth(1.2, 1.9, rr) * 0.7);
    if (rr > 0.8 && rr < 1.25) c.lerp(trail, smooth(5, 1.5, pathDist(x, z)) * 0.5);
    const d = Math.hypot(x - PC.x, z - PC.z);
    if (d < POND_R + 5) {
      c.lerp(sand, smooth(POND_R + 5, POND_R + 1.5, d));
      c.lerp(mud, smooth(POND_R, POND_R - 3, d));
    }
    col.set([c.r, c.g, c.b], i * 3);
  }
  g.setAttribute("color", new THREE.BufferAttribute(col, 3));
  g.computeVertexNormals();
  const m = new THREE.Mesh(g, new THREE.MeshLambertMaterial({ vertexColors: true }));
  m.receiveShadow = true;
  return m;
}

function buildPath() {
  const N = 700, across = [-PATH_W / 2 - 0.6, -PATH_W / 2 + 0.35, 0, PATH_W / 2 - 0.35, PATH_W / 2 + 0.6];
  const alpha = [0, 1, 1, 1, 0];
  const pos = [], col = [], idx = [];
  const dirt = new THREE.Color(0xb48c5a), dirt2 = new THREE.Color(0x9c7446), c = new THREE.Color();
  const r = rng(11);
  for (let i = 0; i <= N; i++) {
    const u = i / N, p = flat(u), t = curve.getTangentAt(u % 1);
    const side = new THREE.Vector3(t.z, 0, -t.x).normalize();
    across.forEach((o, k) => {
      const x = p.x + side.x * o, z = p.z + side.z * o;
      pos.push(x, groundHeight(x, z) + 0.06, z);
      c.copy(dirt).lerp(dirt2, r() * 0.6);
      col.push(c.r, c.g, c.b, alpha[k]);
    });
    if (i < N) for (let k = 0; k < across.length - 1; k++) {
      const a = i * 5 + k, b = a + 5;
      idx.push(a, b, a + 1, a + 1, b, b + 1);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 4));
  g.setIndex(idx);
  g.computeVertexNormals();
  const m = new THREE.Mesh(g, new THREE.MeshLambertMaterial({ vertexColors: true, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }));
  m.receiveShadow = true;
  m.renderOrder = 1;
  return m;
}

/* planks from the path to the water's edge */
function buildBoardwalk(from, to) {
  const g = new THREE.Group();
  const wood = new THREE.MeshLambertMaterial({ color: 0x9a6b3c }), dark = new THREE.MeshLambertMaterial({ color: 0x6b4526 });
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
  g.add(plank);
  const side = new THREE.Vector3(dir.z, 0, -dir.x);
  for (let t = 0.15; t <= 1.001; t += 0.2) for (const s of [-1, 1]) {
    const p = from.clone().addScaledVector(dir, L * t).addScaledVector(side, 1.0 * s);
    const top = deckY(t) + 0.5;
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.08, top + 2, 6), dark);
    post.position.set(p.x, top - (top + 2) / 2, p.z);
    g.add(post);
  }
  return { group: g, deckY };
}

function buildWater() {
  const nm = waterNormals();
  nm.repeat.set(5, 5);
  const mat = new THREE.MeshPhongMaterial({ color: 0x2a86a0, specular: 0x6f9fb0, shininess: 60, transparent: true, opacity: 0.8, normalMap: nm, normalScale: new THREE.Vector2(0.3, 0.3) });
  const m = new THREE.Mesh(new THREE.CircleGeometry(POND_R + 2.6, 64).rotateX(-Math.PI / 2), mat);
  m.position.set(PC.x, WATER_Y, PC.z);
  m.userData.hit = { type: "pond" };
  return m;
}

/* ---------------- plants ---------------- */
const NATURE = {
  tall:   [["tree-1", 7, 11], ["tree-2", 7, 11], ["tree-3", 8, 12], ["tree-5", 6, 9], ["tree-6", 5, 8], ["willow", 5, 7], ["tree-4", 4, 6]],
  palm:   [["palm-1", 5, 8], ["palm-2", 4, 6], ["palm-3", 4, 6.5]],
  bamboo: [["bamboo-1", 3, 5], ["bamboo-2", 5, 7.5], ["bamboo-3", 3.5, 6]],
  bush:   [["bush-1", 1.1, 1.8], ["bush-2", 1.2, 2], ["bush-flowers", 1.1, 1.7], ["bush-berries", 0.9, 1.4], ["fern", 0.9, 1.4], ["plant-1", 1.4, 2.4]],
  low:    [["grass", 0.45, 0.8], ["tall-grass", 0.8, 1.3], ["flowers-1", 0.5, 0.8], ["flowers-2", 0.5, 0.8], ["plant-2", 0.15, 0.25], ["mushroom", 0.25, 0.45]],
  rock:   [["rock-moss", 0.5, 1.4], ["stump", 0.4, 0.6], ["log", 0.5, 0.7], ["rocks-2", 1.2, 2.4]],
};
export const natureUrls = [...new Set(Object.values(NATURE).flat().map(([k]) => A.url("nature", k)).concat(A.url("nature", "lilypad")))];

async function buildPlants(scene, clearings, boardwalk, density) {
  const r = rng(42);
  const culled = [];
  const lists = new Map();                    // key -> [Matrix4]
  const blobs = [];                           // [x, z, radius]
  const push = (key, x, z, h, yaw = r() * 6.28, y) => {
    if (!lists.has(key)) lists.set(key, []);
    const m = new THREE.Matrix4().compose(
      new THREE.Vector3(x, y ?? groundHeight(x, z) - 0.05, z),
      new THREE.Quaternion().setFromEuler(new THREE.Euler(0, yaw, 0)),
      new THREE.Vector3(h, h, h));
    lists.get(key).push(m);
  };
  const pick = arr => arr[(r() * arr.length) | 0];
  const blocked = (x, z, pad) => {
    if (Math.hypot(x - PC.x, z - PC.z) < POND_R + 3 + pad) return true;
    for (const c of clearings) if (Math.hypot(x - c.x, z - c.z) < c.r + pad) return true;
    // boardwalk corridor
    const bx = boardwalk.to.x - boardwalk.from.x, bz = boardwalk.to.z - boardwalk.from.z;
    const t = Math.max(0, Math.min(1, ((x - boardwalk.from.x) * bx + (z - boardwalk.from.z) * bz) / (bx * bx + bz * bz)));
    if (Math.hypot(x - boardwalk.from.x - bx * t, z - boardwalk.from.z - bz * t) < 2.2 + pad) return true;
    return false;
  };
  const place = (group, n, sample, minPath, pad, blob = 0) => {
    n = Math.round(n * density);
    let tries = 0, made = 0;
    while (made < n && tries++ < n * 30) {
      const [x, z] = sample();
      if (pathDist(x, z) < minPath || blocked(x, z, pad)) continue;
      const [key, lo, hi] = pick(NATURE[group]);
      const h = lo + r() * (hi - lo);
      push(key, x, z, h);
      if (blob) blobs.push([x, z, h * blob]);
      made++;
    }
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

  place("tall", 260, ring(1.22, 2.3), 7, 2.5, 0.28);         // deep jungle outside the path
  place("palm", 70, ring(1.15, 2.0), 6, 2, 0.3);
  place("bamboo", 60, ring(1.12, 1.8), 5, 1.5, 0.25);
  place("bush", 260, ring(1.08, 1.9), 3.2, 0.8, 0.45);
  place("tall", 80, ring(0.25, 0.86), 6, 3, 0.28);           // inside the loop, around the pond
  place("palm", 30, ring(0.3, 0.88), 6, 2, 0.3);
  place("bush", 140, ring(0.25, 0.92), 3.2, 0.8, 0.45);
  place("low", 700, nearPath(2.2, 6.5), 2.1, 0.3);            // path edges
  place("low", 500, ring(0.3, 1.8), 2.4, 0.4);
  place("rock", 70, ring(0.3, 1.8), 3, 0.8, 0.5);

  // hedges between neighbouring clearings, so each stop feels like its own place
  for (let i = 0; i < S; i++) {
    const u = i / S, p = flat(u), t = curve.getTangentAt(u);
    const out = new THREE.Vector3(t.z, 0, -t.x);
    if (out.x * p.x + out.z * p.z < 0) out.negate();
    for (let k = 0; k < 5; k++) {
      const d = 3.4 + k * 2.2 + r() * 1.2, j = (r() - 0.5) * 2.5;
      const x = p.x + out.x * d + t.x * j, z = p.z + out.z * d + t.z * j;
      if (blocked(x, z, 0.4)) continue;
      const grp = k < 2 ? "bush" : pick(["bamboo", "palm", "bush"]);
      const [key, lo, hi] = pick(NATURE[grp]);
      const h = lo + r() * (hi - lo);
      push(key, x, z, h);
      blobs.push([x, z, h * 0.3]);
    }
  }
  // reeds and lily pads
  const walkA = Math.atan2(-inward.z, -inward.x);             // where the boardwalk meets the pond
  for (let i = 0; i < 70; i++) {
    const a = r() * Math.PI * 2, d = POND_R + 0.8 + r() * 2.6;
    if (Math.abs(Math.atan2(Math.sin(a - walkA), Math.cos(a - walkA))) < 0.22) continue;
    push(r() < 0.7 ? "tall-grass" : "grass", PC.x + Math.cos(a) * d, PC.z + Math.sin(a) * d, 0.9 + r() * 0.6);
  }
  for (let i = 0; i < 26; i++) {
    const a = r() * Math.PI * 2, d = 2 + r() * (POND_R - 3.5);
    push("lilypad", PC.x + Math.cos(a) * d, PC.z + Math.sin(a) * d, 0.16 + r() * 0.06, r() * 6.28, WATER_Y - 0.01);
  }

  for (const [key, mats] of lists) {
    const gltf = await A.load(A.url("nature", key));
    const g = A.scatter(gltf, mats, { cull: true });
    scene.add(g);
    if (g.userData.cull) culled.push(g.userData.cull);
  }

  // soft dark spots under plants — cheaper than real tree shadows
  const blob = new THREE.InstancedMesh(new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2),
    new THREE.MeshBasicMaterial({ map: radial("rgba(20,40,10,0.55)", "rgba(20,40,10,0)"), transparent: true, depthWrite: false }), blobs.length);
  const m = new THREE.Matrix4();
  blobs.forEach(([x, z, s], i) => blob.setMatrixAt(i, m.compose(new THREE.Vector3(x, groundHeight(x, z) + 0.08, z), new THREE.Quaternion(), new THREE.Vector3(s * 2.4, 1, s * 2.4))));
  blob.renderOrder = 2;
  scene.add(blob);
  return culled;
}

/* ---------------- animals ---------------- */
const PEDESTAL = { parrot: ["stump", 0.75], owl: ["stump", 0.75], squirrel: ["stump", 0.55], frog: ["rock-moss", 0.45] };

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

export async function createJungle(isMobile) {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xbfe6f5);
  scene.fog = new THREE.Fog(0xc8e8ee, 40, 160);
  scene.add(skyDome(0x4fb0ec, 0xd8f1f6, 0x9dbf8a));
  const sun = addLights(scene, { mapSize: isMobile ? 1024 : 2048 });

  scene.add(buildGround(), buildPath());

  const from = pathPoint(stopU(POND_STOP)).addScaledVector(inward, PATH_W / 2 - 0.2);
  const to = PC.clone().addScaledVector(inward, -(POND_R - 3));
  to.y = WATER_Y;
  const bw = buildBoardwalk(from, to);
  scene.add(bw.group);
  const water = buildWater();
  scene.add(water);

  const hits = [water];
  const labels = [];
  const movers = [];
  const stops = [];
  const clearings = [];

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
      const ped = A.instance(await A.load(A.url("nature", key)), { h: ph });
      ped.position.set(ax, ay - 0.05, az);
      ped.traverse(o => { if (o.isMesh) o.receiveShadow = true; });
      scene.add(ped);
      ay += ph - 0.1;
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

  const culls = await buildPlants(scene, clearings, { from, to }, isMobile ? 0.65 : 1);
  const lastCull = { p: new THREE.Vector3(1e9, 0, 0), yaw: 1e9 };

  const focus = new THREE.Vector3();
  const nm = water.material.normalMap;
  function update(dt, t, camera) {
    for (const m of movers) { if (m.userData.mixer) { m.userData.mixer.update(dt); skinnedIdle(m, t); } else idle(m, t); }
    // ducks: a slow lap with a gentle bob
    ducks.forEach((dk, k) => {
      const a = t * 0.045 - dk.userData.lag * 6.28 / 6;
      const rr = POND_R - 4.5 + (k % 2) * 0.4;
      const x = PC.x + Math.cos(a) * rr, z = PC.z + Math.sin(a) * rr;
      dk.position.set(x, WATER_Y - 0.08 + Math.sin(t * 2 + k) * 0.02, z);
      dk.rotation.y = Math.atan2(-Math.sin(a), Math.cos(a));             // face along the lap
    });
    duckLabel.pos.copy(drake.position).y += 1.1;
    for (const f of swimmers) {
      const o = f.userData.orbit, a = o.a + t * o.s;
      f.position.set(PC.x + Math.cos(a) * o.r, o.y + Math.sin(t + o.a) * 0.08, PC.z + Math.sin(a) * o.r);
      f.rotation.y = Math.atan2(-Math.sin(a) * Math.sign(o.s), Math.cos(a) * Math.sign(o.s));
      f.userData.mixer && f.userData.mixer.update(dt);
    }
    nm.offset.set(t * 0.012, t * 0.008);
    camera.getWorldDirection(focus);
    const yaw = Math.atan2(focus.x, focus.z);
    if (lastCull.p.distanceToSquared(camera.position) > 9 || Math.abs(Math.atan2(Math.sin(yaw - lastCull.yaw), Math.cos(yaw - lastCull.yaw))) > 0.25) {
      for (const c of culls) c(camera.position, focus, 125);
      lastCull.p.copy(camera.position); lastCull.yaw = yaw;
    }
    focus.multiplyScalar(14).add(camera.position);
    sun.target.position.copy(focus);
    sun.position.copy(focus).add(new THREE.Vector3(30, 50, 20));
  }

  return { scene, stops, hits, labels, update, pondStop: POND_STOP, pathPoint, curve };
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
