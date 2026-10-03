/* Model loading, normalising and cloning.
   Every model is wrapped so that its feet sit on y = 0, it is centred on x/z,
   it faces +Z, and it is scaled to a height (or length) given in metres. */
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { MeshoptDecoder } from "three/addons/libs/meshopt_decoder.module.js";
import * as SkeletonUtils from "three/addons/utils/SkeletonUtils.js";

const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
const cache = new Map();                       // url -> Promise<gltf|null>

export const url = (group, key) => `models/${group}/${key}.glb`;

export function load(u) {
  if (!cache.has(u)) {
    cache.set(u, loader.loadAsync(u).then(prepare).catch(err => {
      console.warn("model failed", u, err);   // a missing model becomes a placeholder, not a crash
      return null;
    }));
  }
  return cache.get(u);
}

export async function loadAll(urls, onProgress) {
  let done = 0;
  await Promise.all(urls.map(u => load(u).finally(() => onProgress && onProgress(++done, urls.length))));
}

/* One-time fix-ups on the loaded source. Poly models sometimes ship metallic
   materials that go black without an environment map. */
function prepare(gltf) {
  const root = gltf.scene;
  let skinned = false;
  root.traverse(o => {
    if (o.isSkinnedMesh) skinned = true;
    if (o.isMesh) {
      o.castShadow = true;
      o.frustumCulled = !o.isSkinnedMesh;     // skinned bounds are bind-pose only
      for (const m of [].concat(o.material)) {
        if ("metalness" in m) { m.metalness = 0; m.roughness = Math.max(m.roughness ?? 1, 0.65); }
      }
    }
  });
  root.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(root, true);
  gltf.userData.box = box;
  gltf.userData.size = box.getSize(new THREE.Vector3());
  gltf.userData.skinned = skinned;
  return gltf;
}

const tintCache = new Map();
function tinted(mat, hex) {
  const k = mat.uuid + ":" + hex;
  if (!tintCache.has(k)) {
    const m = mat.clone();
    m.color.multiply(new THREE.Color(hex));
    tintCache.set(k, m);
  }
  return tintCache.get(k);
}

/* A ready-to-place animal.
   opts: { h | len, yaw, tint }
   returns Group with userData { dims:{h,w,l}, mixer, actions } */
export function instance(gltf, opts = {}) {
  const outer = new THREE.Group();
  if (!gltf) return placeholder(opts);
  const { box, size, skinned } = gltf.userData;
  const obj = skinned ? SkeletonUtils.clone(gltf.scene) : gltf.scene.clone(true);
  obj.traverse(o => { if (o.isMesh) o.userData.character = true; });
  if (opts.tint != null) {
    obj.traverse(o => {
      if (o.isMesh) o.material = Array.isArray(o.material) ? o.material.map(m => tinted(m, opts.tint)) : tinted(o.material, opts.tint);
    });
  }
  obj.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);
  const inner = new THREE.Group();
  inner.add(obj);
  inner.rotation.y = opts.yaw || 0;
  const turned = Math.abs(Math.sin(opts.yaw || 0)) > 0.5;
  const sx = turned ? size.z : size.x, sz = turned ? size.x : size.z;
  const s = opts.len ? opts.len / Math.max(sx, sz) : (opts.h || 1) / size.y;
  inner.scale.setScalar(s);
  outer.add(inner);

  let mixer = null;
  const actions = {};
  if (gltf.animations.length) {
    mixer = new THREE.AnimationMixer(obj);
    for (const clip of gltf.animations) actions[clip.name.split("|").pop()] = mixer.clipAction(clip);
  }
  outer.userData = { dims: { h: size.y * s, w: sx * s, l: sz * s }, mixer, actions, inner };
  return outer;
}

/* Play the first clip that exists from a preference list, at a random phase. */
export function play(obj, names, fade = 0.3) {
  const { actions } = obj.userData;
  if (!actions) return null;
  const name = names.find(n => actions[n]);
  if (!name) return null;
  const a = actions[name];
  if (obj.userData.current === a) return a;
  if (obj.userData.current) obj.userData.current.fadeOut(fade);
  a.reset().fadeIn(fade).play();
  if (!obj.userData.current) a.time = Math.random() * a.getClip().duration;
  obj.userData.current = a;
  return a;
}

function placeholder(opts) {
  const h = opts.h || (opts.len ? opts.len * 0.4 : 1);
  const g = new THREE.Group();
  const m = new THREE.Mesh(new THREE.CapsuleGeometry(h * 0.3, h * 0.4, 4, 12), new THREE.MeshStandardMaterial({ color: 0xc8a26b }));
  m.position.y = h * 0.5;
  m.castShadow = true;
  g.add(m);
  g.userData = { dims: { h, w: h * 0.6, l: h * 0.6 }, mixer: null, actions: {} };
  return g;
}

/* Frog babies: no model exists, so a tadpole is built from two shapes. */
export function tadpole(len) {
  const g = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ color: 0x3b3a26, roughness: 0.5 });
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.5, 16, 12), mat);
  head.scale.set(0.8, 0.65, 1);
  head.position.set(0, 0.35, 0.3);
  const tail = new THREE.Mesh(new THREE.ConeGeometry(0.28, 1.4, 4, 1), new THREE.MeshStandardMaterial({ color: 0x5b5a3c, roughness: 0.6, transparent: true, opacity: 0.9 }));
  tail.rotation.x = -Math.PI / 2;
  tail.scale.set(0.25, 1, 1);
  tail.position.set(0, 0.35, -0.7);
  const eyeM = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.3 });
  for (const s of [-1, 1]) {
    const e = new THREE.Mesh(new THREE.SphereGeometry(0.1, 8, 6), eyeM);
    e.position.set(0.24 * s, 0.52, 0.58);
    g.add(e);
  }
  head.castShadow = tail.castShadow = true;
  g.add(head, tail);
  g.traverse(o => { if (o.isMesh) o.userData.own = o.userData.character = true; });
  g.scale.setScalar(len / 1.9);
  g.userData = { dims: { h: 0.7 * len / 1.9, w: 0.8 * len / 1.9, l: len }, mixer: null, actions: {}, tail };
  const wrap = new THREE.Group();
  wrap.add(g);
  wrap.userData = g.userData;
  return wrap;
}

/* A little pile of eggs, optionally in a twig nest.
   kind: "bird" | "reptile" | "frog" | "fish" */
export function eggs(kind, count, size) {
  const g = new THREE.Group();
  const look = {
    bird:    { color: 0xf4efe2, r: 0.5, stretch: 1.3, nest: true },
    reptile: { color: 0xf7f3ea, r: 0.5, stretch: 1.25, nest: false },
    frog:    { color: 0xd8f0e6, r: 0.5, stretch: 1, nest: false, jelly: true },
    fish:    { color: 0xffa640, r: 0.5, stretch: 1, nest: false, jelly: true },
  }[kind];
  const geo = new THREE.SphereGeometry(look.r, 14, 10);
  const mat = new THREE.MeshStandardMaterial({
    color: look.color, roughness: look.jelly ? 0.15 : 0.55,
    transparent: !!look.jelly, opacity: look.jelly ? 0.72 : 1,
    emissive: kind === "fish" ? 0x7a2a00 : 0x000000, emissiveIntensity: 0.25,
  });
  const inst = new THREE.InstancedMesh(geo, mat, count);
  inst.castShadow = !look.jelly;
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), sc = new THREE.Vector3();
  const spread = size * Math.sqrt(count) * 0.55;
  for (let i = 0; i < count; i++) {
    // golden-angle spiral, stacked into a low dome
    const a = i * 2.39996, r = spread * Math.sqrt((i + 0.5) / count);
    p.set(Math.cos(a) * r, size * 0.5 + (1 - r / (spread + 1e-6)) * size * 0.6, Math.sin(a) * r);
    q.setFromEuler(new THREE.Euler(Math.random() * 0.6, Math.random() * 6, Math.random() * 0.6));
    sc.set(size, size * look.stretch, size);
    inst.setMatrixAt(i, m.compose(p, q, sc));
  }
  g.add(inst);
  if (look.jelly) {                               // a dark dot inside every jelly egg
    const dot = new THREE.InstancedMesh(new THREE.SphereGeometry(0.16, 8, 6), new THREE.MeshBasicMaterial({ color: kind === "fish" ? 0x40200a : 0x111111 }), count);
    for (let i = 0; i < count; i++) { inst.getMatrixAt(i, m); dot.setMatrixAt(i, m); }
    g.add(dot);
  }
  if (look.nest) {
    const nest = new THREE.Mesh(new THREE.TorusGeometry(spread + size * 0.7, size * 0.55, 8, 24), new THREE.MeshStandardMaterial({ color: 0x7a5530, roughness: 1 }));
    nest.rotation.x = Math.PI / 2;
    nest.position.y = size * 0.35;
    nest.scale.z = 0.7;
    nest.castShadow = true;
    g.add(nest);
  }
  g.traverse(o => { if (o.isMesh && !o.isInstancedMesh) o.userData.own = o.userData.character = true; });
  inst.userData.own = true;
  const R = spread + size * 1.2;
  g.userData = { dims: { h: size * 2, w: R * 2, l: R * 2 } };
  return g;
}

/* ---- scenery: many copies of one model drawn with instancing ---- */
const partsCache = new WeakMap();
function parts(gltf) {
  if (partsCache.has(gltf)) return partsCache.get(gltf);
  const root = gltf.scene;
  root.updateMatrixWorld(true);
  const { box, size } = gltf.userData;
  const norm = new THREE.Matrix4().makeScale(1 / size.y, 1 / size.y, 1 / size.y)
    .multiply(new THREE.Matrix4().makeTranslation(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2));
  const groups = new Map();                         // geometry+material -> local matrices
  const add = (o, local) => {
    const k = o.geometry.uuid + ":" + [].concat(o.material).map(m => m.uuid).join(",");
    if (!groups.has(k)) groups.set(k, { geometry: o.geometry, material: o.material, mats: [] });
    groups.get(k).mats.push(local);
  };
  root.traverse(o => {
    if (!o.isMesh) return;
    const base = norm.clone().multiply(o.matrixWorld);
    if (o.isInstancedMesh) {
      const im = new THREE.Matrix4();
      for (let i = 0; i < o.count; i++) { o.getMatrixAt(i, im); add(o, base.clone().multiply(im)); }
    } else add(o, base);
  });
  const res = { groups: [...groups.values()], aspect: Math.max(size.x, size.z) / size.y };
  partsCache.set(gltf, res);
  return res;
}

/* placements: array of Matrix4 in world space for a model of height 1.
   With cull:true the group gets userData.cull(camPos, camDir, maxDist), which
   packs only the copies near and in front of the camera into the draw. */
export function scatter(gltf, placements, { shadow = false, cull = false } = {}) {
  const out = new THREE.Group();
  if (!gltf || !placements.length) return out;
  const insts = [];
  for (const part of parts(gltf).groups) {
    const L = part.mats.length, n = placements.length * L;
    const inst = new THREE.InstancedMesh(part.geometry, part.material, n);
    const all = inst.instanceMatrix.array;
    const m = new THREE.Matrix4();
    let i = 0;
    for (const P of placements) for (const M of part.mats) m.multiplyMatrices(P, M).toArray(all, 16 * i++);
    inst.castShadow = shadow;
    inst.receiveShadow = false;
    inst.userData.plant = true;
    if (cull) { inst.frustumCulled = false; inst.userData.all = all.slice(); inst.userData.L = L; }
    else inst.computeBoundingSphere();
    insts.push(inst);
    out.add(inst);
  }
  if (cull) {
    const xz = new Float32Array(placements.length * 2);
    placements.forEach((P, k) => { xz[2 * k] = P.elements[12]; xz[2 * k + 1] = P.elements[14]; });
    const keep = new Int32Array(placements.length);
    out.userData.cull = (cam, dir, maxD) => {
      const dl = Math.hypot(dir.x, dir.z) || 1, fx = dir.x / dl, fz = dir.z / dl, m2 = maxD * maxD;
      let c = 0;
      for (let k = 0; k < placements.length; k++) {
        const dx = xz[2 * k] - cam.x, dz = xz[2 * k + 1] - cam.z, d2 = dx * dx + dz * dz;
        if (d2 > m2) continue;
        if (d2 > 144 && (dx * fx + dz * fz) < -0.35 * Math.sqrt(d2)) continue;   // well behind us
        keep[c++] = k;
      }
      for (const inst of insts) {
        const { all, L } = inst.userData, dst = inst.instanceMatrix.array, blk = 16 * L;
        for (let j = 0; j < c; j++) dst.set(all.subarray(keep[j] * blk, keep[j] * blk + blk), j * blk);
        inst.count = c * L;
        inst.instanceMatrix.needsUpdate = true;
      }
    };
  }
  return out;
}

