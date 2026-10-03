/* Procedural plants. No free models exist for Indian jungle species, so each
   one is grown here from a recipe: a branching skeleton wrapped in photo bark,
   leaf "sprays" painted per species (heart-shaped peepal, neem leaflets, teak
   giants…), and fruits or flowers placed where they really grow.

   build(id, seed) -> THREE.Group { bark, leaves, fruit? } with userData.info
   Every vertex carries `aSway` (metres of wind movement), used by the wind shader. */
import * as THREE from "three";
import { rng } from "./env.js";

export const wind = { value: 0 };
const V = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const UP = V(0, 1, 0);

/* ------------------------------------------------------------------ textures */
const loader = new THREE.TextureLoader();
const texCache = new Map();
const pending = [];
export const photosReady = () => Promise.all(pending);
export function photo(name, srgb = true) {
  if (!texCache.has(name)) {
    let done;
    pending.push(new Promise(res => { done = res; }));
    const t = loader.load(`tex/${name}.webp`, () => done(), undefined, () => done());
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.anisotropy = 4;
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    texCache.set(name, t);
  }
  return texCache.get(name);
}

/* ----- leaf sprays painted on a canvas ----- */
function leafPath(g, L, W, shape) {
  // leaf points up the canvas (-y) from the stalk at the origin; W is the half-width
  const N = 20, edge = [];
  for (let i = 0; i <= N; i++) {
    const t = i / N;
    let w, dy = 0;
    if (shape === "lance") w = Math.pow(Math.sin(Math.PI * t), 0.85) * (1 - 0.25 * t);
    else if (shape === "oval") w = Math.pow(Math.sin(Math.PI * (0.02 + t * 0.96)), 0.6);
    else if (shape === "round") w = Math.sqrt(Math.sin(Math.PI * t));
    else if (shape === "heart") {
      // broad rounded lobes that sit below the stalk, narrowing into a long drip tip
      if (t < 0.3) w = 0.72 + 0.28 * Math.sin((t / 0.3) * Math.PI / 2);
      else if (t < 0.82) w = Math.max(0.06, Math.pow(Math.cos(((t - 0.3) / 0.52) * Math.PI / 2), 0.9));
      else w = 0.06 * (1 - (t - 0.82) / 0.18);
      if (t < 0.2) dy = L * 0.12 * Math.sin(Math.PI * t / 0.2);
    } else if (shape === "strap") w = Math.min(1, t * 6) * (t > 0.85 ? (1 - t) / 0.15 : 1);
    else w = Math.sin(Math.PI * t);
    edge.push([W * w, -L * t + dy]);
  }
  g.beginPath();
  g.moveTo(0, 0);
  for (const [x, y] of edge) g.lineTo(x, y);
  for (let i = edge.length - 1; i >= 0; i--) g.lineTo(-edge[i][0], edge[i][1]);
  g.closePath();
}

function drawLeaf(g, x, y, ang, L, W, shape, col, col2, r, opts = {}) {
  L *= 1.3; W *= 1.3;
  g.save();
  g.translate(x, y);
  g.rotate(ang);
  leafPath(g, L, W, shape, r);
  const gr = g.createLinearGradient(-W, 0, W, 0);
  gr.addColorStop(0, col); gr.addColorStop(0.5, col2); gr.addColorStop(1, col);
  g.fillStyle = gr;
  g.fill();
  if (opts.serrate) {                                               // tiny teeth along the edge
    g.strokeStyle = col; g.lineWidth = 1.2; g.setLineDash([2, 2]); g.stroke(); g.setLineDash([]);
  }
  g.strokeStyle = "rgba(255,255,230,0.35)";                         // midrib
  g.lineWidth = Math.max(1, W * 0.08);
  g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -L * 0.97); g.stroke();
  g.lineWidth = Math.max(0.6, W * 0.035);
  g.strokeStyle = "rgba(255,255,220,0.18)";
  for (let k = 1; k < 7; k++) {                                     // side veins
    const t = k / 7;
    g.beginPath(); g.moveTo(0, -L * t); g.lineTo(W * 0.85, -L * (t + 0.08)); g.moveTo(0, -L * t); g.lineTo(-W * 0.85, -L * (t + 0.08)); g.stroke();
  }
  if (opts.tail) { g.fillStyle = col; g.beginPath(); g.moveTo(-W * 0.06, -L * 0.97); g.lineTo(0, -L * 1.25); g.lineTo(W * 0.06, -L * 0.97); g.fill(); }
  g.restore();
}

function compound(g, x, y, ang, len, pairs, lL, lW, shape, col, col2, r, opts) {
  g.save();
  g.translate(x, y); g.rotate(ang);
  g.strokeStyle = "#5b6b2a"; g.lineWidth = 2;
  g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -len); g.stroke();
  for (let i = 0; i < pairs; i++) {
    const t = 0.12 + (i / pairs) * 0.85;
    for (const s of [-1, 1]) drawLeaf(g, 0, -len * t, s * (1.15 - t * 0.35), lL, lW, shape, col, col2, r, opts);
  }
  drawLeaf(g, 0, -len, 0, lL, lW, shape, col, col2, r, opts);       // terminal leaflet
  g.restore();
}

const LEAF = {
  banyan:   { shape: "oval", n: 7, L: 70, W: 26, col: "#2c5a1c", col2: "#4d7c2b" },
  peepal:   { shape: "heart", n: 6, L: 70, W: 34, col: "#3b6a20", col2: "#6a9632", tail: true },
  neem:     { pinnate: [9, 26, 7], n: 5, len: 110, shape: "lance", col: "#3a7a22", col2: "#69a238", serrate: true },
  teak:     { shape: "oval", n: 3, L: 118, W: 58, col: "#5a7a2a", col2: "#86a03e" },
  sal:      { shape: "oval", n: 6, L: 72, W: 26, col: "#3a6a24", col2: "#5e8a34" },
  mango:    { shape: "lance", n: 10, L: 92, W: 14, col: "#1d4a18", col2: "#3a6c25", rosette: true },
  jackfruit:{ shape: "oval", n: 8, L: 62, W: 20, col: "#1a4617", col2: "#33632a" },
  jamun:    { shape: "lance", n: 8, L: 58, W: 13, col: "#275a20", col2: "#4a7c30" },
  tamarind: { pinnate: [13, 11, 4], n: 6, len: 100, shape: "oval", col: "#4a7a26", col2: "#6f9c36" },
  amla:     { pinnate: [18, 7, 2.5], n: 7, len: 105, shape: "oval", col: "#6a9a30", col2: "#8dbb45" },
  bael:     { tri: [34, 12], n: 7, shape: "lance", col: "#3f7024", col2: "#64963a" },
  gular:    { shape: "lance", n: 8, L: 60, W: 18, col: "#2e5f1f", col2: "#4f8030" },
  mahua:    { shape: "oval", n: 9, L: 62, W: 20, col: "#34601f", col2: "#577f2e", rosette: true },
  palash:   { tri: [36, 28], n: 4, shape: "round", col: "#4f7a2a", col2: "#79a040" },
  semal:    { palmate: [6, 44, 11], n: 4, shape: "lance", col: "#3f6f24", col2: "#62923a" },
  mulberry: { shape: "heart", n: 7, L: 46, W: 24, col: "#3f7a26", col2: "#6aa33c", serrate: true },
  sitaphal: { shape: "oval", n: 8, L: 48, W: 15, col: "#5a8a35", col2: "#82ab4c" },
  ber:      { shape: "round", n: 14, L: 18, W: 9, col: "#4d6e2e", col2: "#7a9848" },
  karonda:  { shape: "oval", n: 14, L: 20, W: 8, col: "#1f4a1a", col2: "#3e6d2a" },
  phalsa:   { shape: "heart", n: 8, L: 34, W: 20, col: "#4a7229", col2: "#6f963a" },
  lantana:  { shape: "oval", n: 12, L: 22, W: 10, col: "#3a5f24", col2: "#5e8436", serrate: true },
  datura:   { shape: "oval", n: 5, L: 56, W: 26, col: "#2f5f24", col2: "#4f8036", serrate: true },
  gunja:    { pinnate: [10, 9, 3], n: 6, len: 80, shape: "oval", col: "#4f8a2c", col2: "#78aa44" },
  mimosa:   { bipinnate: true, col: "#4d8a2e", col2: "#78b045" },
  bamboo:   { shape: "strap", n: 9, L: 80, W: 7, col: "#6a9a2a", col2: "#9cc244", fan: true },
  filler:   { shape: "oval", n: 8, L: 46, W: 17, col: "#2f5f22", col2: "#548436" },
};

const sprayCache = new Map();
function spray(kind) {
  if (sprayCache.has(kind)) return sprayCache.get(kind);
  const S = 256, c = document.createElement("canvas");
  c.width = c.height = S;
  const g = c.getContext("2d");
  const L = LEAF[kind] || LEAF.filler, r = rng(kind.length * 97 + kind.charCodeAt(0));
  const shade = () => {                                              // each leaf a slightly different green
    const k = 0.85 + r() * 0.3;
    return [L.col, L.col2].map(h => {
      const n = parseInt(h.slice(1), 16);
      const cl = v => Math.min(255, Math.round(v * k));
      return `rgb(${cl(n >> 16)},${cl((n >> 8) & 255)},${cl(n & 255)})`;
    });
  };
  const bx = S / 2, by = S - 6;
  if (L.bipinnate) {                                                 // touch-me-not: fans of feathery pinnae
    g.strokeStyle = "#7a3b2a"; g.lineWidth = 2.5;
    for (let p = 0; p < 4; p++) {
      const a = -0.55 + p * 0.37;
      const [c1, c2] = shade();
      compound(g, bx, by - 40, a, 150, 16, 11, 3.5, "oval", c1, c2, r, {});
    }
    g.beginPath(); g.moveTo(bx, by); g.lineTo(bx, by - 40); g.stroke();
  } else if (L.fan || L.rosette) {                                   // leaves radiating from a twig tip
    const tipY = L.fan ? by - 40 : by - 70;
    g.strokeStyle = "#5c4a2a"; g.lineWidth = 3;
    g.beginPath(); g.moveTo(bx, by); g.lineTo(bx, tipY); g.stroke();
    for (let i = 0; i < L.n; i++) {
      const a = -1.25 + (i / (L.n - 1)) * 2.5 + (r() - 0.5) * 0.2;
      const [c1, c2] = shade();
      drawLeaf(g, bx, tipY, a, L.L * (0.85 + r() * 0.3), L.W, L.shape, c1, c2, r, L);
    }
  } else {                                                           // alternate leaves along a twig
    const twig = S * 0.78;
    g.strokeStyle = "#5c4a2a"; g.lineWidth = 3;
    g.beginPath(); g.moveTo(bx, by); g.quadraticCurveTo(bx + 10, by - twig * 0.5, bx - 4, by - twig); g.stroke();
    for (let i = 0; i < L.n; i++) {
      const t = 0.18 + (i / L.n) * 0.82, s = i % 2 ? 1 : -1;
      const x = bx + 6 * Math.sin(t * 3), y = by - twig * t;
      const [c1, c2] = shade();
      const ang = s * (0.9 - t * 0.45) + (r() - 0.5) * 0.25;
      if (L.pinnate) compound(g, x, y, ang * 0.8, L.len * (0.8 + r() * 0.3), L.pinnate[0], L.pinnate[1], L.pinnate[2], L.shape, c1, c2, r, L);
      else if (L.tri) { g.save(); g.translate(x, y); g.rotate(ang * 0.8); for (const a of [-0.8, 0, 0.8]) drawLeaf(g, 0, -12, a, L.tri[0] * (a ? 0.85 : 1), L.tri[1], L.shape, c1, c2, r, L); g.restore(); }
      else if (L.palmate) { g.save(); g.translate(x, y); g.rotate(ang * 0.8); for (let k = 0; k < L.palmate[0]; k++) drawLeaf(g, 0, -14, -1 + k * (2 / (L.palmate[0] - 1)), L.palmate[1], L.palmate[2], L.shape, c1, c2, r, L); g.restore(); }
      else drawLeaf(g, x, y, ang, L.L * (0.8 + r() * 0.35), L.W, L.shape, c1, c2, r, L);
    }
    if (!L.pinnate && !L.tri && !L.palmate) { const [c1, c2] = shade(); drawLeaf(g, bx - 4, by - twig, 0, L.L * 0.8, L.W * 0.9, L.shape, c1, c2, r, L); }
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  sprayCache.set(kind, t);
  return t;
}

/* one big leaf (or one whole compound leaf) for the plant stage close-up */
function leafOnly(kind) {
  const key = "one:" + kind;
  if (sprayCache.has(key)) return sprayCache.get(key);
  const S = 256, c = document.createElement("canvas");
  c.width = c.height = S;
  const g = c.getContext("2d");
  const Lf = LEAF[kind] || LEAF.filler, r = rng(5);
  const bx = S / 2, by = S - 8;
  if (Lf.bipinnate) { for (let p = 0; p < 4; p++) compound(g, bx, by - 30, -0.55 + p * 0.37, 190, 16, 16, 5, "oval", Lf.col, Lf.col2, r, {}); }
  else if (Lf.pinnate) compound(g, bx, by, 0, 230, Math.min(Lf.pinnate[0], 12), 60 * Math.min(1, 22 / Lf.pinnate[0] * 0.6 + 0.4) / 1.3, 60 * Lf.pinnate[2] / Lf.pinnate[1] / 1.3, Lf.shape, Lf.col, Lf.col2, r, Lf);
  else if (Lf.tri) { g.save(); g.translate(bx, by); for (const a of [-0.75, 0, 0.75]) drawLeaf(g, 0, -40, a, 130 / 1.3 * (a ? 0.85 : 1), 130 / 1.3 * Lf.tri[1] / Lf.tri[0], Lf.shape, Lf.col, Lf.col2, r, Lf); g.strokeStyle = "#5c4a2a"; g.lineWidth = 4; g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -40); g.stroke(); g.restore(); }
  else if (Lf.palmate) { g.save(); g.translate(bx, by - 30); for (let k = 0; k < Lf.palmate[0]; k++) drawLeaf(g, 0, 0, -1.15 + k * (2.3 / (Lf.palmate[0] - 1)), 150 / 1.3, 150 / 1.3 * Lf.palmate[2] / Lf.palmate[1], Lf.shape, Lf.col, Lf.col2, r, Lf); g.restore(); }
  else {
    const len = (Lf.tail ? 170 : 200) / 1.3;
    g.strokeStyle = "#5c4a2a"; g.lineWidth = 4; g.beginPath(); g.moveTo(bx, by); g.lineTo(bx, by - 18); g.stroke();
    drawLeaf(g, bx, by - 16, 0, len, Math.min(len * Lf.W / Lf.L, 88 / 1.3), Lf.shape, Lf.col, Lf.col2, r, Lf);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  sprayCache.set(key, t);
  return t;
}

/* ----- palm frond, banana leaf, grass blades ----- */
function frondTexture() {
  if (sprayCache.has("frond")) return sprayCache.get("frond");
  const W = 128, H = 512, c = document.createElement("canvas");
  c.width = W; c.height = H;
  const g = c.getContext("2d"), r = rng(3);
  g.strokeStyle = "#6b6a2a"; g.lineWidth = 4;
  g.beginPath(); g.moveTo(W / 2, H); g.lineTo(W / 2, 0); g.stroke();
  for (let y = H - 20; y > 6; y -= 9) {
    const len = W * 0.48 * Math.min(1, (H - y) / 90) * Math.min(1, y / 60 + 0.25);
    for (const s of [-1, 1]) {
      g.strokeStyle = `rgb(${60 + r() * 25},${110 + r() * 30},${40 + r() * 15})`;
      g.lineWidth = 5.5;
      g.beginPath(); g.moveTo(W / 2, y); g.quadraticCurveTo(W / 2 + s * len * 0.6, y - 10, W / 2 + s * len, y - 26 + r() * 6); g.stroke();
    }
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  sprayCache.set("frond", t);
  return t;
}
function bananaLeafTexture() {
  if (sprayCache.has("banana")) return sprayCache.get("banana");
  const W = 128, H = 512, c = document.createElement("canvas");
  c.width = W; c.height = H;
  const g = c.getContext("2d"), r = rng(5);
  g.beginPath();
  g.moveTo(W / 2, H);
  for (let y = H; y >= 0; y -= 8) g.lineTo(W / 2 + W * 0.47 * Math.pow(Math.sin(Math.PI * (1 - y / H) * 0.98 + 0.02), 0.35), y);
  for (let y = 0; y <= H; y += 8) g.lineTo(W / 2 - W * 0.47 * Math.pow(Math.sin(Math.PI * (1 - y / H) * 0.98 + 0.02), 0.35), y);
  g.closePath();
  const gr = g.createLinearGradient(0, 0, W, 0);
  gr.addColorStop(0, "#3f7f26"); gr.addColorStop(0.5, "#6fae3c"); gr.addColorStop(1, "#3f7f26");
  g.fillStyle = gr; g.fill();
  g.globalCompositeOperation = "destination-out";                    // wind tears
  for (let i = 0; i < 9; i++) {
    const y = 40 + r() * (H - 90), s = r() < 0.5 ? -1 : 1;
    g.fillRect(W / 2 + s * (6 + r() * 4), y, s * W, 1.6);
  }
  g.globalCompositeOperation = "source-over";
  g.strokeStyle = "rgba(230,240,180,0.35)"; g.lineWidth = 1;
  for (let y = H - 10; y > 10; y -= 6) { g.beginPath(); g.moveTo(W / 2, y); g.lineTo(0, y - 18); g.moveTo(W / 2, y); g.lineTo(W, y - 18); g.stroke(); }
  g.strokeStyle = "#c9d68a"; g.lineWidth = 5; g.beginPath(); g.moveTo(W / 2, H); g.lineTo(W / 2, 0); g.stroke();
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  sprayCache.set("banana", t);
  return t;
}
export function grassTexture() {
  if (sprayCache.has("grass")) return sprayCache.get("grass");
  const S = 256, c = document.createElement("canvas");
  c.width = c.height = S;
  const g = c.getContext("2d"), r = rng(9);
  for (let i = 0; i < 70; i++) {
    const x = 10 + r() * (S - 20), h = S * (0.45 + r() * 0.55), bend = (r() - 0.5) * 60;
    g.strokeStyle = `rgb(${70 + r() * 50},${110 + r() * 50},${35 + r() * 25})`;
    g.lineWidth = 2 + r() * 2.5;
    g.beginPath(); g.moveTo(x, S); g.quadraticCurveTo(x + bend * 0.3, S - h * 0.6, x + bend, S - h); g.stroke();
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  sprayCache.set("grass", t);
  return t;
}

/* ------------------------------------------------------------------ materials */
function windify(mat, leafy) {
  mat.onBeforeCompile = sh => {
    sh.uniforms.uWind = wind;
    sh.vertexShader = "uniform float uWind;\nattribute float aSway;\n" + sh.vertexShader.replace("#include <begin_vertex>", `#include <begin_vertex>
      vec3 ip = vec3(0.0);
      #ifdef USE_INSTANCING
        ip = instanceMatrix[3].xyz;
      #endif
      float ph = ip.x * 0.21 + ip.z * 0.17;
      transformed.x += sin(uWind * 1.1 + ph) * aSway;
      transformed.z += cos(uWind * 0.87 + ph * 1.3) * aSway * 0.7;
      ${leafy ? "transformed.y += sin(uWind * 4.2 + position.x * 2.3 + position.z * 1.9 + ph) * aSway * 0.3;" : ""}`);
  };
  mat.customProgramCacheKey = () => (leafy ? "wind-leaf" : "wind-bark");
  return mat;
}
const matCache = new Map();
function mat(key, make) { if (!matCache.has(key)) matCache.set(key, make()); return matCache.get(key); }
export const BARK = { rough: "bark001", fissured: "bark012", smooth: "bark005", mossy: "bark013" };
function barkMat(kind, tint) {
  return mat("bark:" + kind + ":" + tint, () => windify(new THREE.MeshStandardMaterial({
    map: photo(BARK[kind] + "_color"), normalMap: photo(BARK[kind] + "_normal", false), normalScale: new THREE.Vector2(1.2, 1.2),
    // the photo texture is already dark: a half-strength tint keeps bark brown instead of
    // so dark that the sky's blue reflection takes over
    color: new THREE.Color(0xffffff).lerp(new THREE.Color(tint), 0.5).multiply(new THREE.Color(0xe8c49a)), roughness: 1, metalness: 0, vertexColors: true, envMapIntensity: 0.12,
  }), false));
}
function leafMat(kind, map) {
  return mat("leaf:" + kind, () => windify(new THREE.MeshStandardMaterial({
    map: map || spray(kind), alphaTest: 0.42, side: THREE.DoubleSide, roughness: 0.9, metalness: 0,
    vertexColors: true, envMapIntensity: 0.55,
  }), true));
}
export const windMaterial = (key, map) => leafMat(key, map);
const fruitMat = () => mat("fruit", () => windify(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5, metalness: 0 }), true));

/* ------------------------------------------------------------------ geometry builder */
class Geo {
  constructor() { this.p = []; this.n = []; this.u = []; this.c = []; this.s = []; this.i = []; }
  get count() { return this.p.length / 3; }
  vert(pos, nor, u, v, sway, col = [1, 1, 1]) {
    this.p.push(pos.x, pos.y, pos.z); this.n.push(nor.x, nor.y, nor.z); this.u.push(u, v); this.s.push(sway); this.c.push(col[0], col[1], col[2]);
  }
  /* append another geometry transformed by m, tinted by col */
  add(geo, m, col, sway) {
    const base = this.count, g = geo.index ? geo : geo;
    const P = g.attributes.position, N = g.attributes.normal, U = g.attributes.uv;
    const nm = new THREE.Matrix3().getNormalMatrix(m), v = V(), n = V();
    for (let k = 0; k < P.count; k++) {
      v.fromBufferAttribute(P, k).applyMatrix4(m);
      n.fromBufferAttribute(N, k).applyMatrix3(nm).normalize();
      this.vert(v, n, U ? U.getX(k) : 0, U ? U.getY(k) : 0, typeof sway === "function" ? sway(v) : sway, col);
    }
    if (g.index) for (let k = 0; k < g.index.count; k++) this.i.push(base + g.index.getX(k));
    else for (let k = 0; k < P.count; k++) this.i.push(base + k);
  }
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(this.p, 3));
    g.setAttribute("normal", new THREE.Float32BufferAttribute(this.n, 3));
    g.setAttribute("uv", new THREE.Float32BufferAttribute(this.u, 2));
    g.setAttribute("color", new THREE.Float32BufferAttribute(this.c, 3));
    g.setAttribute("aSway", new THREE.Float32BufferAttribute(this.s, 1));
    g.setIndex(this.i);
    g.computeBoundingBox(); g.computeBoundingSphere();
    return g;
  }
}

/* A tapered tube along points, with bark UVs that don't stretch. */
function tube(G, pts, radii, segs, swayOf, col) {
  const base = G.count;
  let T = pts[1].clone().sub(pts[0]).normalize();
  let N = Math.abs(T.y) < 0.9 ? V(0, 1, 0) : V(1, 0, 0);
  N.sub(T.clone().multiplyScalar(N.dot(T))).normalize();
  const B = V().crossVectors(T, N);
  let len = 0;
  const around = Math.max(1, Math.round((Math.PI * 2 * radii[0]) / 0.7));
  for (let i = 0; i < pts.length; i++) {
    if (i > 0) {
      const Tn = (i < pts.length - 1 ? pts[i + 1].clone().sub(pts[i - 1]) : pts[i].clone().sub(pts[i - 1])).normalize();
      const ax = V().crossVectors(T, Tn), s = ax.length();
      if (s > 1e-6) N.applyAxisAngle(ax.divideScalar(s), Math.asin(Math.min(1, s)));
      T = Tn; B.crossVectors(T, N);
      len += pts[i].distanceTo(pts[i - 1]);
    }
    const sw = swayOf(pts[i]);
    for (let j = 0; j <= segs; j++) {
      const a = (j / segs) * Math.PI * 2;
      const n = N.clone().multiplyScalar(Math.cos(a)).addScaledVector(B, Math.sin(a));
      G.vert(pts[i].clone().addScaledVector(n, radii[i]), n, (j / segs) * around, len / 0.7, sw, col ? col(i, j) : undefined);
    }
  }
  for (let i = 0; i < pts.length - 1; i++) for (let j = 0; j < segs; j++) {
    const a = base + i * (segs + 1) + j, b = a + segs + 1;
    G.i.push(a, b, a + 1, a + 1, b, b + 1);
  }
}

/* One leaf card (a quad) with its base at `at`, pointing along `up`. */
function card(G, at, up, w, h, sway, nrm, tint, r) {
  const side = V().crossVectors(up, V(r() - 0.5, r() - 0.5, r() - 0.5).normalize()).normalize().multiplyScalar(w / 2);
  const top = at.clone().addScaledVector(up, h);
  const base = G.count;
  const col = [tint, tint * (0.95 + r() * 0.1), tint];
  G.vert(at.clone().sub(side), nrm, 0, 0, sway * 0.6, col);
  G.vert(at.clone().add(side), nrm, 1, 0, sway * 0.6, col);
  G.vert(top.clone().add(side), nrm, 1, 1, sway, col);
  G.vert(top.clone().sub(side), nrm, 0, 1, sway, col);
  G.i.push(base, base + 1, base + 2, base, base + 2, base + 3);
}

/* A bent strip (palm frond, banana leaf) along a curve. */
function strip(G, pts, widths, sideDir, sway, col = [1, 1, 1]) {
  const base = G.count;
  for (let i = 0; i < pts.length; i++) {
    const t = i / (pts.length - 1);
    const tan = (i < pts.length - 1 ? pts[i + 1].clone().sub(pts[i]) : pts[i].clone().sub(pts[i - 1])).normalize();
    const nrm = V().crossVectors(tan, sideDir).normalize();
    if (nrm.y < 0) nrm.negate();
    const half = sideDir.clone().multiplyScalar(widths[i] / 2);
    G.vert(pts[i].clone().sub(half), nrm, 0, t, sway(t), col);
    G.vert(pts[i].clone().add(half), nrm, 1, t, sway(t), col);
  }
  for (let i = 0; i < pts.length - 1; i++) { const a = base + i * 2; G.i.push(a, a + 1, a + 3, a, a + 3, a + 2); }
}

/* ------------------------------------------------------------------ fruit & flower parts */
/* Fruit primitives are tiny and numerous, so they stay very low-poly; background
   (lite) plants drop to the lowest level and carry a third of the fruit. */
const G_ICO0 = new THREE.IcosahedronGeometry(1, 0), G_ICO1 = new THREE.IcosahedronGeometry(1, 1), G_UV = new THREE.SphereGeometry(1, 8, 6);
let LOW = false;
const G = { get S0() { return G_ICO0; }, get S1() { return LOW ? G_ICO0 : G_ICO1; }, get S2() { return LOW ? G_ICO0 : G_UV; } };
const G_CONE = new THREE.ConeGeometry(1, 1, 7, 1, true).translate(0, 0.5, 0);
const G_CYL = new THREE.CylinderGeometry(1, 1, 1, 5, 1).translate(0, 0.5, 0);
const G_TRUMPET = new THREE.LatheGeometry([...Array(9)].map((_, i) => new THREE.Vector2(0.12 + Math.pow(i / 8, 3) * 0.9, i / 8)), 10);
const JACK = new THREE.IcosahedronGeometry(1, 2);
const hex = h => { const c = new THREE.Color(h); return [c.r, c.g, c.b]; };
const M = (p, s, q = new THREE.Quaternion()) => new THREE.Matrix4().compose(p, q, typeof s === "number" ? V(s, s, s) : s);
const qLook = dir => new THREE.Quaternion().setFromUnitVectors(UP, dir.clone().normalize());

/* each adds one fruit/flower at `p` into F, scaled by k (1 = real size) */
export const PART = {
  mango(F, p, k, r, sw) {
    F.add(G_CYL, M(p, V(0.006 * k, 0.12 * k, 0.006 * k), qLook(V(0, 1, 0))), hex("#5d4a1f"), sw);
    const ripe = r() < 0.5;
    F.add(G.S2, M(p.clone().add(V(0, -0.07 * k, 0)), V(0.045 * k, 0.07 * k, 0.04 * k), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, r() * 6, 0.2))), hex(ripe ? "#e6a12a" : "#7aa33a"), sw);
  },
  jack(F, p, k, r, sw, out) {
    const q = qLook(V(out.x, -0.9, out.z));
    const bump = LOW ? G_ICO1 : JACK;
    F.add(bump, M(p, V(0.12 * k, 0.2 * k, 0.12 * k), q), hex(r() < 0.5 ? "#5f7a22" : "#7a8a2a"), sw);
  },
  berry(F, p, k, r, sw, _o, col = "#3b1a4a", n = 9, rad = 0.012) {
    for (let i = 0; i < n; i++) F.add(G.S0, M(p.clone().add(V((r() - 0.5) * 0.06 * k, -r() * 0.08 * k, (r() - 0.5) * 0.06 * k)), rad * k * (0.8 + r() * 0.4)), hex(r() < 0.8 ? col : "#6a2a5a"), sw);
  },
  jamun(F, p, k, r, sw) { PART.berry(F, p, k, r, sw, null, "#2e1238", 10, 0.016); },
  karonda(F, p, k, r, sw) { PART.berry(F, p, k, r, sw, null, r() < 0.5 ? "#3a1030" : "#c2407a", 5, 0.012); },
  phalsa(F, p, k, r, sw) { PART.berry(F, p, k, r, sw, null, "#4a1e55", 7, 0.008); },
  lantanaBerry(F, p, k, r, sw) { PART.berry(F, p, k, r, sw, null, "#111", 6, 0.005); },
  mulberry(F, p, k, r, sw) {
    for (let i = 0; i < 3; i++) F.add(G.S1, M(p.clone().add(V((r() - 0.5) * 0.05 * k, -r() * 0.04 * k, (r() - 0.5) * 0.05 * k)), V(0.008 * k, 0.018 * k, 0.008 * k)), hex(["#1d0a1a", "#8a1428", "#4a0e22"][i]), sw);
  },
  round(F, p, k, r, sw, _o, col = "#b7c96a", rad = 0.05) {
    F.add(G.S2, M(p.clone().add(V(0, -rad * k, 0)), rad * k * (0.9 + r() * 0.2)), hex(col), sw);
  },
  amla(F, p, k, r, sw) { for (let i = 0; i < 3; i++) PART.round(F, p.clone().add(V((r() - 0.5) * 0.08 * k, 0, (r() - 0.5) * 0.08 * k)), k, r, sw, null, "#b9d27a", 0.02); },
  bael(F, p, k, r, sw) { PART.round(F, p, k, r, sw, null, r() < 0.5 ? "#a8a95a" : "#c9b458", 0.07); },
  ber(F, p, k, r, sw) { for (let i = 0; i < 2; i++) PART.round(F, p.clone().add(V((r() - 0.5) * 0.06 * k, 0, (r() - 0.5) * 0.06 * k)), k, r, sw, null, ["#d88a2a", "#b8452a", "#9fb040"][(r() * 3) | 0], 0.014); },
  fig(F, p, k, r, sw) { for (let i = 0; i < 5; i++) F.add(G.S0, M(p.clone().add(V((r() - 0.5) * 0.14 * k, (r() - 0.5) * 0.14 * k, (r() - 0.5) * 0.14 * k)), 0.022 * k), hex(["#c2482c", "#d97a3a", "#8fa04a"][(r() * 3) | 0]), sw); },
  smallFig(F, p, k, r, sw) { for (let i = 0; i < 4; i++) F.add(G.S0, M(p.clone().add(V((r() - 0.5) * 0.08 * k, (r() - 0.5) * 0.06 * k, (r() - 0.5) * 0.08 * k)), 0.009 * k), hex(r() < 0.5 ? "#b8322a" : "#7a2a4a"), sw); },
  neemFruit(F, p, k, r, sw) { PART.berry(F, p, k, r, sw, null, "#c6c24a", 6, 0.009); },
  pod(F, p, k, r, sw) {                                            // tamarind: curved brown pods
    const pts = [], rad = [];
    const bend = (r() - 0.5) * 0.08;
    for (let i = 0; i <= 6; i++) { pts.push(p.clone().add(V(Math.sin(i / 6 * 2) * bend * k, -i * 0.03 * k, i * 0.004 * k))); rad.push(0.011 * k * (i === 0 || i === 6 ? 0.6 : 1)); }
    const T = new Geo();
    tube(T, pts, rad, 5, () => 0);
    F.add(T.build(), new THREE.Matrix4(), hex("#7a5230"), sw);
  },
  sitaphal(F, p, k, r, sw) { F.add(G_ICO1, M(p.clone().add(V(0, -0.05 * k, 0)), 0.05 * k), hex("#9ab46a"), sw); },
  coconut(F, p, k, r, sw) { for (let i = 0; i < 7; i++) F.add(G.S2, M(p.clone().add(V(Math.cos(i * 0.9) * 0.2 * k, -0.1 * k - (i % 2) * 0.1 * k, Math.sin(i * 0.9) * 0.2 * k)), V(0.11 * k, 0.13 * k, 0.11 * k)), hex(r() < 0.7 ? "#6a8a2a" : "#8a6a2a"), sw); },
  palash(F, p, k, r, sw) {
    for (let i = 0; i < 7; i++) {
      const d = V(r() - 0.5, 0.4 + r() * 0.6, r() - 0.5).normalize();
      F.add(G_CONE, M(p.clone().add(V((r() - 0.5) * 0.12 * k, (r() - 0.3) * 0.1 * k, (r() - 0.5) * 0.12 * k)), V(0.012 * k, 0.06 * k, 0.012 * k), qLook(d)), hex(r() < 0.8 ? "#f2641e" : "#ff8a2a"), sw);
    }
  },
  semal(F, p, k, r, sw) { F.add(G_CONE, M(p, V(0.05 * k, 0.07 * k, 0.05 * k), qLook(V(r() - 0.5, 1, r() - 0.5))), hex("#d6242a"), sw); },
  cotton(F, p, k, r, sw) { F.add(G.S1, M(p.clone().add(V(0, -0.05 * k, 0)), V(0.05 * k, 0.04 * k, 0.05 * k)), hex("#f4f1ea"), sw); },
  mahuaFlower(F, p, k, r, sw) { for (let i = 0; i < 4; i++) F.add(G.S0, M(p.clone().add(V((r() - 0.5) * 0.07 * k, -r() * 0.05 * k, (r() - 0.5) * 0.07 * k)), 0.013 * k), hex("#efe2b4"), sw); },
  teakFlower(F, p, k, r, sw) { for (let i = 0; i < 8; i++) F.add(G.S0, M(p.clone().add(V((r() - 0.5) * 0.25 * k, r() * 0.18 * k, (r() - 0.5) * 0.25 * k)), 0.012 * k), hex("#f2efe0"), sw); },
  salFlower(F, p, k, r, sw) { for (let i = 0; i < 6; i++) F.add(G.S0, M(p.clone().add(V((r() - 0.5) * 0.15 * k, -r() * 0.1 * k, (r() - 0.5) * 0.15 * k)), 0.01 * k), hex("#efe3b0"), sw); },
  mangoFlower(F, p, k, r, sw) { F.add(G_CONE, M(p, V(0.05 * k, 0.16 * k, 0.05 * k), qLook(V(r() - 0.5, 1, r() - 0.5))), hex("#d8c56a"), sw); },
  lantana(F, p, k, r, sw) {
    const cols = ["#f5d23a", "#f07a2a", "#e8488a", "#f6a2c8"];
    for (let i = 0; i < 8; i++) {
      const a = i * 2.4, d = Math.sqrt(i / 8) * 0.03 * k;
      F.add(G.S0, M(p.clone().add(V(Math.cos(a) * d, 0.01 * k, Math.sin(a) * d)), 0.007 * k), hex(cols[Math.min(3, Math.floor(d / (0.03 * k) * 4))]), sw);
    }
  },
  datura(F, p, k, r, sw, out) { F.add(G_TRUMPET, M(p, V(0.07 * k, 0.16 * k, 0.07 * k), qLook(V(out.x, 0.3, out.z))), hex("#f4f2ea"), sw); },
  daturaFruit(F, p, k, r, sw) {
    F.add(G.S1, M(p, 0.035 * k), hex("#6f9a3a"), sw);
    for (let i = 0; i < 14; i++) { const d = V(r() - 0.5, r() - 0.5, r() - 0.5).normalize(); F.add(G_CONE, M(p.clone().addScaledVector(d, 0.03 * k), V(0.004 * k, 0.018 * k, 0.004 * k), qLook(d)), hex("#7aa04a"), sw); }
  },
  gunja(F, p, k, r, sw) {
    F.add(G.S1, M(p, V(0.012 * k, 0.03 * k, 0.012 * k)), hex("#8a7a4a"), sw);
    for (let i = 0; i < 4; i++) {
      const q = p.clone().add(V((r() - 0.5) * 0.03 * k, -0.01 * k - i * 0.008 * k, 0.012 * k));
      F.add(G.S2, M(q, 0.006 * k), hex("#d4141a"), sw);
      F.add(G.S0, M(q.clone().add(V(0, 0.004 * k, 0.002 * k)), 0.0028 * k), hex("#111"), sw);
    }
  },
  mimosaFlower(F, p, k, r, sw) {
    F.add(G.S1, M(p, 0.012 * k), hex("#e49ad0"), sw);
    for (let i = 0; i < 16; i++) { const d = V(r() - 0.5, r() - 0.5, r() - 0.5).normalize(); F.add(G_CYL, M(p, V(0.0012 * k, 0.02 * k, 0.0012 * k), qLook(d)), hex("#f0b6e2"), sw); }
  },
  bananaBunch(F, p, k, r, sw) {
    F.add(G_CYL, M(p.clone().add(V(0, -0.8 * k, 0)), V(0.025 * k, 0.8 * k, 0.025 * k)), hex("#6a7a2a"), sw);
    for (let h = 0; h < 6; h++) for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      const at = p.clone().add(V(Math.cos(a) * 0.08 * k, -0.15 * k - h * 0.1 * k, Math.sin(a) * 0.08 * k));
      F.add(G_CYL, M(at, V(0.018 * k, 0.16 * k, 0.018 * k), qLook(V(Math.cos(a), 1.4, Math.sin(a)))), hex(h < 2 ? "#b8c24a" : "#8ab03a"), sw);
    }
    F.add(G_CONE, M(p.clone().add(V(0, -1.1 * k, 0)), V(0.08 * k, 0.22 * k, 0.08 * k), qLook(V(0, -1, 0))), hex("#6a1f3a"), sw);
  },
};

/* ------------------------------------------------------------------ trees */
/* Recipes. h height (m), trunk: fraction of height before branching,
   r0 trunk radius, angle: branch lean from vertical per level,
   kids: branches per level, len: length ratio per level, leaves per twig,
   card: leaf card size (m), crown droop, bark kind + tint, fruit placement. */
const TREES = {
  banyan:   { h: 13, trunk: 0.3, r0: 0.9, depth: 3, kids: [6, 3, 3], angle: [1.25, 0.9, 0.8], len: [0.72, 0.5, 0.45], lean: 0.1, leaves: 14, card: 1.1, bark: "smooth", tint: "#a89478", fruit: ["fig", 40, "twigs"], roots: 26, spread: 1.4 },
  peepal:   { h: 14, trunk: 0.28, r0: 0.7, depth: 3, kids: [5, 3, 3], angle: [0.85, 0.85, 0.7], len: [0.6, 0.5, 0.5], leaves: 12, card: 1.1, bark: "smooth", tint: "#a0927c", fruit: ["smallFig", 40, "twigs"], flute: true },
  neem:     { h: 11, trunk: 0.35, r0: 0.45, depth: 3, kids: [5, 3, 3], angle: [0.7, 0.8, 0.7], len: [0.55, 0.5, 0.45], leaves: 12, card: 1.0, bark: "rough", tint: "#8a7e70", fruit: ["neemFruit", 40, "twigs"] },
  teak:     { h: 16, trunk: 0.55, r0: 0.45, depth: 2, kids: [6, 4], angle: [0.6, 0.8], len: [0.42, 0.5], leaves: 10, card: 1.5, bark: "fissured", tint: "#b8a890", fruit: ["teakFlower", 20, "top"] },
  sal:      { h: 17, trunk: 0.6, r0: 0.5, depth: 2, kids: [6, 4], angle: [0.55, 0.7], len: [0.38, 0.5], leaves: 12, card: 1.1, bark: "fissured", tint: "#8a7a68", fruit: ["salFlower", 26, "top"] },
  palash:   { h: 8, trunk: 0.3, r0: 0.28, depth: 3, kids: [4, 3, 2], angle: [0.9, 0.8, 0.7], len: [0.6, 0.5, 0.45], lean: 0.25, crooked: 0.4, leaves: 3, card: 0.9, bark: "rough", tint: "#8a8278", fruit: ["palash", 110, "twigs"] },
  semal:    { h: 16, trunk: 0.85, r0: 0.55, depth: 2, kids: [9, 3], angle: [1.35, 0.6], len: [0.45, 0.45], tiers: true, leaves: 4, card: 1.2, bark: "smooth", tint: "#a59a88", thorns: 70, fruit: ["semal", 70, "twigs"], fruit2: ["cotton", 14, "twigs"] },
  mahua:    { h: 12, trunk: 0.3, r0: 0.55, depth: 3, kids: [5, 3, 3], angle: [0.95, 0.8, 0.7], len: [0.6, 0.5, 0.45], leaves: 11, card: 1.0, bark: "fissured", tint: "#7a6a5a", fruit: ["mahuaFlower", 45, "twigs"] },
  mango:    { h: 11, trunk: 0.28, r0: 0.45, depth: 3, kids: [5, 3, 3], angle: [0.9, 0.8, 0.7], len: [0.6, 0.5, 0.45], leaves: 15, card: 1.0, bark: "rough", tint: "#6a6258", dense: 1.2, fruit: ["mango", 45, "tips"], fruit2: ["mangoFlower", 10, "top"] },
  jackfruit:{ h: 11, trunk: 0.35, r0: 0.45, depth: 3, kids: [5, 3, 2], angle: [0.8, 0.8, 0.7], len: [0.55, 0.5, 0.45], leaves: 14, card: 1.0, bark: "rough", tint: "#7a6a58", fruit: ["jack", 12, "trunk"] },
  jamun:    { h: 12, trunk: 0.35, r0: 0.45, depth: 3, kids: [5, 3, 3], angle: [0.7, 0.8, 0.7], len: [0.55, 0.5, 0.45], leaves: 13, card: 1.0, bark: "smooth", tint: "#8a8070", fruit: ["jamun", 60, "tips"] },
  tamarind: { h: 13, trunk: 0.3, r0: 0.6, depth: 3, kids: [6, 3, 3], angle: [1.05, 0.9, 0.8], len: [0.65, 0.5, 0.45], leaves: 13, card: 1.0, bark: "rough", tint: "#5e5850", fruit: ["pod", 90, "tips"], spread: 1.2 },
  amla:     { h: 7, trunk: 0.3, r0: 0.22, depth: 3, kids: [4, 3, 3], angle: [0.85, 0.8, 0.7], len: [0.6, 0.5, 0.45], leaves: 9, card: 0.85, bark: "smooth", tint: "#9a8a78", fruit: ["amla", 50, "branches"] },
  bael:     { h: 8, trunk: 0.3, r0: 0.28, depth: 3, kids: [4, 3, 2], angle: [0.8, 0.8, 0.7], len: [0.6, 0.5, 0.45], leaves: 10, card: 0.8, bark: "rough", tint: "#8a8070", fruit: ["bael", 16, "tips"] },
  gular:    { h: 11, trunk: 0.3, r0: 0.5, depth: 3, kids: [5, 3, 3], angle: [0.95, 0.85, 0.7], len: [0.6, 0.5, 0.45], leaves: 12, card: 1.0, bark: "smooth", tint: "#9c8a72", fruit: ["fig", 30, "trunk"] },
  mulberry: { h: 6, trunk: 0.3, r0: 0.18, depth: 3, kids: [4, 3, 3], angle: [0.8, 0.8, 0.7], len: [0.6, 0.5, 0.45], leaves: 10, card: 0.7, bark: "smooth", tint: "#8a7a68", fruit: ["mulberry", 60, "tips"] },
  sitaphal: { h: 5, trunk: 0.25, r0: 0.14, depth: 3, kids: [4, 3, 2], angle: [0.8, 0.8, 0.7], len: [0.6, 0.5, 0.45], leaves: 9, card: 0.7, bark: "smooth", tint: "#9a9488", fruit: ["sitaphal", 14, "tips"] },
  ber:      { h: 4, trunk: 0.18, r0: 0.14, depth: 3, kids: [5, 3, 3], angle: [1.0, 0.9, 0.8], len: [0.65, 0.55, 0.5], leaves: 9, card: 0.55, bark: "rough", tint: "#6a6258", thorns: 30, fruit: ["ber", 34, "tips"] },
  filler:   { h: 12, trunk: 0.38, r0: 0.45, depth: 3, kids: [5, 3, 2], angle: [0.8, 0.8, 0.7], len: [0.55, 0.5, 0.45], leaves: 12, card: 1.0, bark: "rough", tint: "#7a7066" },
};
/* bushes: many stems from the ground */
const BUSHES = {
  karonda: { h: 2.2, stems: 7, leaves: 12, card: 0.55, fruit: ["karonda", 40], bark: "rough", tint: "#5a5248", thorny: true },
  phalsa:  { h: 3, stems: 6, leaves: 10, card: 0.65, fruit: ["phalsa", 40], bark: "smooth", tint: "#8a7a68" },
  lantana: { h: 1.8, stems: 8, leaves: 12, card: 0.5, fruit: ["lantana", 45], fruit2: ["lantanaBerry", 14], bark: "rough", tint: "#7a6a58" },
  datura:  { h: 1.3, stems: 5, leaves: 7, card: 0.6, fruit: ["datura", 12], fruit2: ["daturaFruit", 6], bark: "smooth", tint: "#6a8a4a" },
};

function swayFn(H, amp) { return p => Math.pow(Math.max(0, p.y) / H, 2) * H * amp; }

function growTree(R, r) {
  const B = new Geo(), L = new Geo(), F = new Geo();
  const H = R.h * (0.85 + r() * 0.3);
  const sw = swayFn(H, 0.006), swL = swayFn(H, 0.012);
  const tips = [], twigs = [], trunkPts = [];
  const barkCol = () => { const k = 0.85 + r() * 0.3; return [k, k, k]; };

  function branch(p0, dir, len, rad, depth) {
    const segs = depth === 0 ? 8 : depth === 1 ? 5 : 3;
    const pts = [p0.clone()], radii = [rad];
    const d = dir.clone(), p = p0.clone();
    for (let s = 1; s <= segs; s++) {
      d.add(V(r() - 0.5, r() - 0.5, r() - 0.5).multiplyScalar(depth === 0 ? (R.crooked || 0.08) : 0.3));
      if (depth > 0) d.y += depth === 1 ? 0.08 : -0.02;             // main limbs reach up, twigs droop a little
      d.normalize();
      p.addScaledVector(d, len / segs);
      pts.push(p.clone());
      radii.push(rad * (1 - (s / segs) * 0.72));
    }
    const segsR = depth === 0 ? 10 : depth === 1 ? 7 : 4;
    tube(B, pts, radii, segsR, sw, (i, j) => barkCol());
    if (depth === 0) trunkPts.push(...pts);
    if (depth < R.depth) {
      const n = R.kids[depth];
      const start = depth === 0 ? R.trunk / (R.trunk + 0.001) * 0.999 : 0.3;
      for (let k = 0; k < n; k++) {
        const t = depth === 0 ? (R.tiers ? 0.35 + (k / n) * 0.6 : 0.82 + r() * 0.18) : start + (k + r() * 0.7) / n * (1 - start);
        const idx = Math.min(pts.length - 2, Math.floor(t * (pts.length - 1)));
        const f = t * (pts.length - 1) - idx;
        const at = pts[idx].clone().lerp(pts[idx + 1], f);
        const az = k * 2.39996 + r() * 0.6;                          // spiral like real branching
        const lean = R.angle[depth] + (r() - 0.5) * 0.25;
        const cd = V(Math.sin(lean) * Math.cos(az), Math.cos(lean), Math.sin(lean) * Math.sin(az));
        if (depth > 0) cd.lerp(d, 0.35).normalize();
        const cl = len * R.len[depth] * (depth === 0 ? H / len * (R.spread || 1) : 1) * (0.8 + r() * 0.4) * (R.tiers ? 1 - t * 0.6 : 1);
        branch(at, cd, cl, rad * (depth === 0 ? 0.55 : 0.6) * (1 - t * 0.3), depth + 1);
      }
    } else {
      twigs.push(pts);
      tips.push(pts[pts.length - 1]);
    }
  }
  const trunkLen = H * R.trunk;
  branch(V(0, -0.3, 0), V(R.lean ? (r() - 0.5) * R.lean : 0, 1, R.lean ? (r() - 0.5) * R.lean : 0).normalize(), trunkLen + 0.3, R.r0, 0);

  // leaves: clumps of cards around the outer part of every twig, darker deep
  // inside the crown (cheap self-shadowing), sized to the tree
  const crown = V();
  tips.forEach(t => crown.add(t));
  crown.divideScalar(Math.max(1, tips.length));
  crown.y -= H * 0.05;
  const reach = tips.reduce((m, t) => Math.max(m, t.distanceTo(crown)), 1);
  const per = Math.round(R.leaves * (R.dense || 1));
  const cs = R.card * Math.max(1, H / 8.5) * 1.1;
  for (const tw of twigs) {
    for (let c = 0; c < 2; c++) {
      const t = c === 0 ? 1 : 0.5 + r() * 0.3;
      const idx = Math.min(tw.length - 2, Math.floor(t * (tw.length - 1)));
      const ctr = tw[idx].clone().lerp(tw[idx + 1], Math.min(1, t * (tw.length - 1) - idx));
      for (let k = 0; k < Math.ceil(per * 0.9); k++) {
        const at = ctr.clone().add(V(r() - 0.5, (r() - 0.5) * 0.8, r() - 0.5).multiplyScalar(cs * 1.1));
        const out = at.clone().sub(crown);
        const depth01 = Math.min(1, out.length() / reach);
        out.normalize();
        const up = out.clone().multiplyScalar(0.55).add(V(r() - 0.5, r() * 0.6, r() - 0.5)).normalize();
        const s = cs * (0.75 + r() * 0.5);
        const nrm = out.clone().add(V(0, 0.45, 0)).normalize();
        card(L, at.clone().addScaledVector(up, -s * 0.45), up, s, s, swL(at), nrm, (0.42 + 0.6 * depth01) * (0.9 + r() * 0.2), r);
      }
    }
  }
  // fruit & flowers
  const place = (spec) => {
    if (!spec) return;
    const [kind, n0, where] = spec;
    const n = LOW ? Math.ceil(n0 / 3) : n0;
    for (let k = 0; k < n; k++) {
      let p, out;
      if (where === "trunk") {
        const i = 1 + Math.floor(r() * (trunkPts.length - 2));
        const a = r() * Math.PI * 2;
        out = V(Math.cos(a), 0, Math.sin(a));
        p = trunkPts[i].clone().addScaledVector(out, R.r0 * (1 - i / trunkPts.length * 0.5) * 0.95);
      } else {
        const tw = twigs[(r() * twigs.length) | 0];
        if (!tw) return;
        const t = where === "tips" ? 0.8 + r() * 0.2 : where === "top" ? 1 : where === "branches" ? 0.2 + r() * 0.6 : 0.4 + r() * 0.6;
        const idx = Math.min(tw.length - 2, Math.floor(t * (tw.length - 1)));
        p = tw[idx].clone().lerp(tw[idx + 1], t * (tw.length - 1) - idx);
        out = p.clone().sub(crown).setY(0).normalize();
        if (where === "tips") p.addScaledVector(out, R.card * 0.4).y -= R.card * 0.25;
        if (where === "top" && p.y < crown.y) continue;
      }
      PART[kind](F, p, 2.2, r, swL(p), out);      // fruits enlarged ×2.2 so a child can spot them from the path
    }
  };
  place(R.fruit); place(R.fruit2);
  // thorns
  if (R.thorns) for (let k = 0; k < R.thorns; k++) {
    const i = Math.floor(r() * (trunkPts.length - 1));
    const a = r() * Math.PI * 2, out = V(Math.cos(a), 0.2, Math.sin(a)).normalize();
    F.add(G_CONE, M(trunkPts[i].clone().addScaledVector(out, R.r0 * (1 - i / trunkPts.length * 0.6) * 0.9), V(0.03, 0.09, 0.03), qLook(out)), hex("#6a5a48"), 0);
  }
  // banyan: aerial roots dropping from the limbs, some already thick pillars
  if (R.roots) for (let k = 0; k < R.roots; k++) {
    const tw = twigs[(r() * twigs.length) | 0];
    const top = tw[0].clone();
    if (top.y < H * 0.35) continue;
    const reach = r() < 0.4;                                          // reached the soil → thick new trunk
    const bottom = reach ? top.clone().setY(-0.2) : top.clone().setY(top.y * (0.2 + r() * 0.5));
    const pts = [], rad = [];
    for (let i = 0; i <= 6; i++) { pts.push(top.clone().lerp(bottom, i / 6).add(V((r() - 0.5) * 0.08, 0, (r() - 0.5) * 0.08))); rad.push(reach ? 0.12 + r() * 0.08 : 0.025); }
    tube(B, pts, rad, reach ? 6 : 3, sw, () => [0.85, 0.82, 0.78]);
  }
  // fluted trunk base (peepal, banyan): a few flaring buttress roots
  if (R.flute || R.roots) for (let k = 0; k < 5; k++) {
    const a = (k / 5) * Math.PI * 2 + r();
    const out = V(Math.cos(a), 0, Math.sin(a));
    const pts = [V(0, 1.2, 0).addScaledVector(out, R.r0 * 0.5), V(0, 0.3, 0).addScaledVector(out, R.r0 * 1.2), V(0, -0.2, 0).addScaledVector(out, R.r0 * 1.9)];
    tube(B, pts, [R.r0 * 0.35, R.r0 * 0.3, R.r0 * 0.15], 6, sw, () => [0.9, 0.9, 0.9]);
  }
  return { B, L, F, H, crown, crownR: tips.reduce((m, t) => Math.max(m, Math.hypot(t.x, t.z)), 1) + R.card };
}

function growBush(R, r) {
  const B = new Geo(), L = new Geo(), F = new Geo();
  const H = R.h * (0.85 + r() * 0.3);
  const sw = swayFn(H, 0.02), swL = swayFn(H, 0.03);
  const twigs = [];
  for (let s = 0; s < R.stems; s++) {
    const a = (s / R.stems) * Math.PI * 2 + r() * 0.5, lean = 0.25 + r() * 0.45;
    let d = V(Math.sin(lean) * Math.cos(a), Math.cos(lean), Math.sin(lean) * Math.sin(a));
    const pts = [V(Math.cos(a) * 0.05, -0.05, Math.sin(a) * 0.05)], rad = [0.03 * H];
    const p = pts[0].clone();
    for (let i = 1; i <= 5; i++) { d.add(V(r() - 0.5, -0.05, r() - 0.5).multiplyScalar(0.3)).normalize(); p.addScaledVector(d, H / 5 * (0.9 + r() * 0.2)); pts.push(p.clone()); rad.push(0.03 * H * (1 - i / 6)); }
    tube(B, pts, rad, 4, sw);
    twigs.push(pts);
    for (let k = 0; k < 2; k++) {                                     // side shoots
      const at = pts[2 + k].clone(), sd = V(r() - 0.5, 0.6, r() - 0.5).normalize(), q = [at];
      for (let i = 1; i <= 3; i++) q.push(at.clone().addScaledVector(sd, H * 0.14 * i));
      tube(B, q, [0.012 * H, 0.009 * H, 0.006 * H, 0.004 * H], 3, sw);
      twigs.push(q);
    }
  }
  const crown = V(0, H * 0.55, 0);
  for (const tw of twigs) for (let k = 0; k < R.leaves; k++) {
    const t = 0.3 + r() * 0.7, idx = Math.min(tw.length - 2, Math.floor(t * (tw.length - 1)));
    const at = tw[idx].clone().lerp(tw[idx + 1], t * (tw.length - 1) - idx).add(V(r() - 0.5, r() - 0.5, r() - 0.5).multiplyScalar(R.card * 0.5));
    const out = at.clone().sub(crown).normalize();
    const up = out.clone().multiplyScalar(0.5).add(V(r() - 0.5, r() * 0.7, r() - 0.5)).normalize();
    const s = R.card * (0.8 + r() * 0.4);
    card(L, at.clone().addScaledVector(up, -s * 0.4), up, s, s, swL(at), out.clone().add(V(0, 0.4, 0)).normalize(), (0.5 + 0.55 * Math.min(1, at.distanceTo(crown) / (H * 0.7))) * (0.9 + r() * 0.2), r);
  }
  const place = spec => {
    if (!spec) return;
    for (let k = 0; k < (LOW ? Math.ceil(spec[1] / 3) : spec[1]); k++) {
      const tw = twigs[(r() * twigs.length) | 0], t = 0.55 + r() * 0.45, idx = Math.min(tw.length - 2, Math.floor(t * (tw.length - 1)));
      const p = tw[idx].clone().lerp(tw[idx + 1], t * (tw.length - 1) - idx);
      const out = p.clone().sub(crown).setY(0).normalize();
      p.addScaledVector(out, R.card * 0.35);
      PART[spec[0]](F, p, 1.8, r, swL(p), out);
    }
  };
  place(R.fruit); place(R.fruit2);
  if (R.thorny) for (let k = 0; k < 40; k++) {
    const tw = twigs[(r() * twigs.length) | 0], p = tw[1 + ((r() * (tw.length - 1)) | 0)], d = V(r() - 0.5, r() - 0.2, r() - 0.5).normalize();
    F.add(G_CONE, M(p, V(0.006, 0.03, 0.006), qLook(d)), hex("#c8b89a"), swL(p));
  }
  return { B, L, F, H, crown, crownR: H * 0.7 };
}

function growPalm(r) {
  const B = new Geo(), L = new Geo(), F = new Geo();
  const H = 11 + r() * 3, lean = V(r() - 0.5, 0, r() - 0.5).normalize().multiplyScalar(0.25 + r() * 0.2);
  const sw = swayFn(H, 0.012);
  const pts = [], rad = [];
  for (let i = 0; i <= 12; i++) {
    const t = i / 12;
    pts.push(V(lean.x * H * t * t, t * H - 0.2, lean.z * H * t * t));
    rad.push(0.22 * (1 - t * 0.35) + (i === 0 ? 0.08 : 0));
  }
  tube(B, pts, rad, 8, sw, i => (i % 2 ? [0.75, 0.72, 0.68] : [1, 0.96, 0.9]));   // ring bands
  const top = pts[pts.length - 1];
  for (let k = 0; k < 20; k++) {
    const a = k * 2.39996, up = 0.9 - (k % 3) * 0.45;
    const dir = V(Math.cos(a), up, Math.sin(a)).normalize();
    const fp = [], fw = [];
    const len = 4 + r() * 1.2;
    for (let i = 0; i <= 10; i++) {
      const t = i / 10;
      fp.push(top.clone().addScaledVector(dir.clone().setY(0).normalize(), len * t).add(V(0, dir.y * len * t - t * t * len * 0.85, 0)));
      fw.push(2.3 * Math.sin(Math.PI * Math.min(1, t * 1.05 + 0.05)) + 0.3);
    }
    const side = V(-Math.sin(a), 0, Math.cos(a));
    strip(L, fp, fw, side, t => 0.05 + t * t * 0.35);
  }
  PART.coconut(F, top.clone().add(V(0, -0.35, 0)), 1, r, 0.05);
  return { B, L, F, H, crown: top, crownR: 5, leafMap: frondTexture(), leafKey: "frond" };
}

function growBanana(r) {
  const B = new Geo(), L = new Geo(), F = new Geo();
  const H = 3.6 + r() * 0.8;
  const pts = [], rad = [];
  for (let i = 0; i <= 5; i++) { pts.push(V(0, (i / 5) * H * 0.42 - 0.1, 0)); rad.push(0.17 * (1 - i / 10)); }
  tube(B, pts, rad, 8, p => p.y * 0.01, () => [0.55, 0.75, 0.4]);
  const top = pts[pts.length - 1];
  for (let k = 0; k < 8; k++) {
    const a = k * 2.39996, lift = 0.55 + r() * 0.6;
    const out = V(Math.cos(a), 0, Math.sin(a));
    const fp = [], fw = [];
    const len = 2.7 + r() * 0.7;
    for (let i = 0; i <= 10; i++) {
      const t = i / 10;
      fp.push(top.clone().addScaledVector(out, len * t * 0.8).add(V(0, lift * len * t - t * t * len * 0.7 + 0.2, 0)));
      fw.push(0.78 * Math.pow(Math.sin(Math.PI * Math.min(1, t * 0.95 + 0.04)), 0.4));
    }
    strip(L, fp, fw, V(-Math.sin(a), 0.15, Math.cos(a)).normalize(), t => 0.03 + t * 0.12);
  }
  PART.bananaBunch(F, top.clone().add(V(0.3, 0.1, 0)), 1, r, 0.02);
  return { B, L, F, H, crown: top, crownR: 2.2, leafMap: bananaLeafTexture(), leafKey: "banana", barkPlain: "#7a9a4a" };
}

function growBamboo(r) {
  const B = new Geo(), L = new Geo(), F = new Geo();
  const n = 16 + ((r() * 8) | 0);
  const H = 11 + r() * 3;
  const tips = [];
  for (let k = 0; k < n; k++) {
    const a = r() * Math.PI * 2, d0 = r() * 0.9;
    const base = V(Math.cos(a) * d0, -0.1, Math.sin(a) * d0);
    const lean = 0.08 + r() * 0.2;
    const hh = H * (0.6 + r() * 0.45);
    const pts = [], rad = [];
    for (let i = 0; i <= 10; i++) {
      const t = i / 10;
      pts.push(base.clone().add(V(Math.cos(a) * (lean * hh * t * t * 1.4), t * hh, Math.sin(a) * (lean * hh * t * t * 1.4))));
      rad.push(0.07 * (1 - t * 0.6));
    }
    tube(B, pts, rad, 6, p => Math.pow(Math.max(0, p.y) / H, 2) * 0.35, i => (i % 2 ? [0.72, 0.8, 0.45] : [0.86, 0.92, 0.55]));
    for (let i = 4; i <= 10; i++) tips.push({ p: pts[i], out: V(Math.cos(a), 0, Math.sin(a)) });
  }
  for (const { p, out } of tips) for (let k = 0; k < 3; k++) {
    const at = p.clone().add(V((r() - 0.5) * 0.8, (r() - 0.5) * 0.6, (r() - 0.5) * 0.8));
    const up = out.clone().multiplyScalar(0.7).add(V(r() - 0.5, -0.2 + r() * 0.5, r() - 0.5)).normalize();
    const s = 0.9 + r() * 0.4;
    card(L, at, up, s, s, Math.pow(at.y / H, 2) * 0.4, out.clone().add(V(0, 0.4, 0)).normalize(), 0.85 + r() * 0.3, r);
  }
  return { B, L, F, H, crown: V(0, H * 0.7, 0), crownR: 3, leafKind: "bamboo", barkPlain: "#b8c070" };
}

function growMimosa(r) {
  const B = new Geo(), L = new Geo(), F = new Geo();
  for (let s = 0; s < 7; s++) {
    const a = (s / 7) * Math.PI * 2 + r() * 0.4;
    const pts = [], rad = [];
    for (let i = 0; i <= 5; i++) { const t = i / 5; pts.push(V(Math.cos(a) * t * 0.7, 0.05 + Math.sin(t * 3) * 0.12, Math.sin(a) * t * 0.7)); rad.push(0.008); }
    tube(B, pts, rad, 4, () => 0.004, () => [1, 0.6, 0.55]);
    for (let i = 1; i <= 5; i++) {
      const out = V(Math.cos(a + (r() - 0.5)), 0.5 + r() * 0.5, Math.sin(a + (r() - 0.5))).normalize();
      card(L, pts[i], out, 0.26, 0.26, 0.01, V(0, 1, 0), 0.85 + r() * 0.3, r);
    }
    PART.mimosaFlower(F, pts[3].clone().add(V(0, 0.08, 0)), 3, r, 0.01);
  }
  return { B, L, F, H: 0.45, crown: V(0, 0.15, 0), crownR: 0.9, leafKind: "mimosa" };
}

function growGunja(r) {
  // a dead support pole with the vine twining up it
  const B = new Geo(), L = new Geo(), F = new Geo();
  const H = 3.2;
  tube(B, [V(0, -0.2, 0), V(0.05, H * 0.5, 0), V(-0.05, H, 0.05)], [0.07, 0.06, 0.04], 6, () => 0);
  const vine = [], vr = [];
  for (let i = 0; i <= 60; i++) { const t = i / 60, a = t * 14; vine.push(V(Math.cos(a) * 0.09, t * H, Math.sin(a) * 0.09)); vr.push(0.008); }
  tube(B, vine, vr, 3, p => p.y * 0.004, () => [0.6, 0.75, 0.45]);
  for (let i = 3; i < 60; i += 2) {
    const p = vine[i], out = V(p.x, 0, p.z).normalize();
    card(L, p, out.clone().add(V(0, 0.4 + r() * 0.4, 0)).normalize(), 0.45, 0.45, p.y * 0.006, out.clone().add(V(0, 0.4, 0)).normalize(), 0.85 + r() * 0.3, r);
  }
  for (let k = 0; k < 16; k++) { const p = vine[20 + ((r() * 38) | 0)]; PART.gunja(F, p.clone().add(V(p.x * 2, 0, p.z * 2)), 3, r, 0.01); }
  return { B, L, F, H, crown: V(0, H * 0.6, 0), crownR: 0.8, leafKind: "gunja", barkKind: "mossy" };
}

function growMushrooms(r) {
  const B = new Geo(), L = new Geo(), F = new Geo();
  const cap = new THREE.SphereGeometry(1, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2);
  for (let k = 0; k < 9; k++) {
    const a = r() * Math.PI * 2, d = 0.15 + r() * 0.45, s = 0.06 + r() * 0.08;
    const p = V(Math.cos(a) * d, 0, Math.sin(a) * d);
    const red = k < 4;
    F.add(G_CYL, M(p, V(s * 0.25, s * 1.3, s * 0.25)), hex("#efe8d6"), 0);
    F.add(cap, M(p.clone().add(V(0, s * 1.25, 0)), V(s, s * 0.6, s)), hex(red ? "#c8201e" : ["#b0824a", "#e8d3a0"][k % 2]), 0);
    if (red) for (let i = 0; i < 7; i++) {
      const u = r() * Math.PI * 2, v = 0.3 + r() * 0.9;
      F.add(G.S0, M(p.clone().add(V(Math.cos(u) * Math.sin(v) * s, s * 1.25 + Math.cos(v) * s * 0.6, Math.sin(u) * Math.sin(v) * s)), s * 0.1), hex("#fbf6ea"), 0);
    }
  }
  return { B, L, F, H: 0.3, crown: V(0, 0.1, 0), crownR: 0.7 };
}

/* ------------------------------------------------------------------ public */
const SPECIAL = { coconut: growPalm, banana: growBanana, bamboo: growBamboo, mimosa: growMimosa, gunja: growGunja, mushroom: growMushrooms };

export function build(id, seed = 1, lite = false) {
  LOW = lite;
  const r = rng(seed * 7919 + id.length * 31 + id.charCodeAt(0));
  let res, leafKind = id, barkKind, tint = "#ffffff";
  if (SPECIAL[id]) { res = SPECIAL[id](r); leafKind = res.leafKind || id; barkKind = res.barkKind; }
  else if (BUSHES[id]) { res = growBush(BUSHES[id], r); barkKind = BUSHES[id].bark; tint = BUSHES[id].tint; }
  else {
    let R = TREES[id] || TREES.filler;
    if (lite) R = { ...R, depth: Math.min(R.depth, 2), kids: R.kids.map((k, i) => (i === 0 ? k : k + 1)), leaves: Math.round(R.leaves * 1.15), card: R.card * 1.55, roots: R.roots ? 10 : 0, thorns: 0 };
    res = growTree(R, r); barkKind = R.bark; tint = R.tint; if (!TREES[id]) leafKind = "filler";
  }

  const g = new THREE.Group();
  const bark = res.barkPlain
    ? mat("plain:" + res.barkPlain, () => windify(new THREE.MeshStandardMaterial({ color: res.barkPlain, roughness: 0.7, vertexColors: true, map: photo(BARK.smooth + "_color"), normalMap: photo(BARK.smooth + "_normal", false) }), false))
    : barkMat(barkKind || "rough", tint);
  if (res.B.count) { const m = new THREE.Mesh(res.B.build(), bark); m.name = "bark"; g.add(m); }
  if (res.L.count) {
    const lm = res.leafMap ? leafMat(res.leafKey, res.leafMap) : leafMat(leafKind);
    const m = new THREE.Mesh(res.L.build(), lm); m.name = "leaves"; g.add(m);
  }
  if (res.F.count) { const m = new THREE.Mesh(res.F.build(), fruitMat()); m.name = "fruit"; g.add(m); }
  g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  const box = new THREE.Box3().setFromObject(g);
  g.userData.info = { h: res.H, crownR: res.crownR, box, leafKind };
  LOW = false;
  return g;
}

/* Wrap a built plant so assets.scatter() can instance it (it wants a gltf-like object). */
export function asModel(group) {
  group.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(group);
  return { scene: group, animations: [], userData: { box, size: box.getSize(V()) } };
}

/* Close-up specimens for the plant stage: one big leaf spray and one fruit/flower. */
export function leafSpecimen(id, size = 0.9) {
  const kind = SPECIAL[id] ? (id === "coconut" ? "frond" : id === "banana" ? "banana" : id) : (TREES[id] || BUSHES[id] ? id : "filler");
  const map = kind === "frond" ? frondTexture() : kind === "banana" ? bananaLeafTexture() : leafOnly(kind);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size * (kind === "frond" || kind === "banana" ? 0.4 : 1), size).translate(0, size / 2, 0),
    new THREE.MeshStandardMaterial({ map, alphaTest: 0.42, side: THREE.DoubleSide, roughness: 0.7 }));
  m.castShadow = true;
  return m;
}
const SPECIMEN = {
  banyan: ["fig", 6], peepal: ["smallFig", 10], neem: ["neemFruit", 6], teak: ["teakFlower", 5], sal: ["salFlower", 6], palash: ["palash", 5],
  semal: ["semal", 5], mahua: ["mahuaFlower", 5], mango: ["mango", 3.5], jackfruit: ["jack", 1.6], jamun: ["jamun", 6], tamarind: ["pod", 5],
  amla: ["amla", 5], bael: ["bael", 3], gular: ["fig", 5], coconut: ["coconut", 0.8], banana: ["bananaBunch", 0.45], ber: ["ber", 7],
  karonda: ["karonda", 8], mulberry: ["mulberry", 7], phalsa: ["phalsa", 9], sitaphal: ["sitaphal", 4], lantana: ["lantana", 10],
  datura: ["datura", 3.5], gunja: ["gunja", 9], mimosa: ["mimosaFlower", 7], mushroom: null, fern: null, bamboo: null,
};
export function fruitSpecimen(id) {
  const spec = SPECIMEN[id];
  if (!spec) return null;
  const F = new Geo(), r = rng(11);
  PART[spec[0]](F, V(0, 0.3, 0), spec[1], r, 0, V(0, 0, 1));
  if (id === "datura") PART.daturaFruit(F, V(0.35, 0.25, 0), 3.5, r, 0);
  if (id === "semal") PART.cotton(F, V(0.35, 0.35, 0), 5, r, 0);
  const m = new THREE.Mesh(F.build(), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5 }));
  m.castShadow = true;
  const box = new THREE.Box3().setFromObject(m);
  m.position.y = -box.min.y;
  const wrap = new THREE.Group();
  wrap.add(m);
  return wrap;
}

/* The touch-me-not's leaves fold when tapped: squash its leaf mesh for a while. */
export function fold(group, t0) { group.userData.foldAt = t0; }
export function updateFold(group, t) {
  const leaves = group.getObjectByName("leaves");
  if (!leaves || group.userData.foldAt == null) return;
  const e = t - group.userData.foldAt;
  const k = e < 0.35 ? e / 0.35 : e < 3.5 ? 1 : e < 5 ? 1 - (e - 3.5) / 1.5 : 0;
  leaves.scale.set(1 - 0.75 * k, 1 - 0.35 * k, 1 - 0.75 * k);
  if (e >= 5) group.userData.foldAt = null;
}
