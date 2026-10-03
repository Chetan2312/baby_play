/* "Meet the family": father, mother, babies (and eggs) on a round stage that
   the child can spin all the way round. Used for land animals and for fish. */
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import * as A from "./assets.js";
import * as F from "./flora.js";
import { skyDome, addLights, stageTexture, rng, radial, realSky, SUN_DIR } from "./env.js";
import { grassTuft } from "./terrain.js";

const EGG_KIND = { crocodile: "reptile", turtle: "reptile", cobra: "reptile", frog: "frog", parrot: "bird", owl: "bird", hornbill: "bird", duck: "bird" };
const FISH_LEN = { swordfish: 1.7, tuna: 1.45, trout: 1.3 };

function makeEnv(kind, isMobile, renderer) {
  const scene = new THREE.Scene();
  scene.userData = { kind: kind === "land" ? "land" : "water", small: true };
  const decor = new THREE.Group();
  scene.add(decor);
  let sun, stage;
  const mapSize = isMobile ? 1024 : 2048;
  if (kind === "land") {
    // the same real sky, light and ground as the jungle
    scene.userData.tone = { mapping: THREE.ACESFilmicToneMapping, exposure: 0.85 };
    scene.background = new THREE.Color(0xb7cdd2);
    scene.fog = new THREE.Fog(0xb4c8c6, 40, 170);
    const sky = realSky(scene, renderer);
    const dome = skyDome(0x5cb8ee, 0xe4f6f0, 0x8fb86a);
    dome.visible = false;
    scene.add(dome);
    scene.userData.onStyle = on => { sky.visible = !on; dome.visible = on; scene.environment = on ? null : scene.userData.env; };
    scene.userData.realSky = sky;
    sun = addLights(scene, { sky: 0xdfe6c8, ground: 0x4a5424, hemi: 1.05, sun: 0xffeccc, sunI: 3.2, mapSize, span: 8 });
    const tiled = (name, srgb, k) => { const t = F.photo(name, srgb).clone(); t.repeat.set(k, k); t.needsUpdate = true; return t; };
    const ground = new THREE.Mesh(new THREE.CircleGeometry(200, 48).rotateX(-Math.PI / 2),
      new THREE.MeshStandardMaterial({ map: tiled("grass004_color", true, 60), normalMap: tiled("grass004_normal", false, 60), roughness: 0.97, envMapIntensity: 0.6 }));
    ground.position.y = -0.02;
    ground.receiveShadow = true;
    scene.add(ground);
    const floorMap = tiled("ground037_color", true, 1), floorNor = tiled("ground037_normal", false, 1);
    stage = new THREE.Mesh(new THREE.CircleGeometry(1, 64).rotateX(-Math.PI / 2),
      new THREE.MeshStandardMaterial({ map: floorMap, normalMap: floorNor, alphaMap: radial("rgb(255,255,255)", "rgb(0,0,0)", 256), transparent: true, depthWrite: false, roughness: 0.98, polygonOffset: true, polygonOffsetFactor: -1, envMapIntensity: 0.6 }));
    stage.userData.tiles = [floorMap, floorNor];
  } else {
    scene.background = new THREE.Color(0x0d5e8f);
    scene.fog = new THREE.Fog(0x0d5e8f, 8, 55);
    scene.add(skyDome(0x3fb2e0, 0x0f6699, 0x06324f));
    sun = addLights(scene, { sky: 0xaee9ff, ground: 0x1d4a5c, hemi: 2.0, sun: 0xd9f7ff, sunI: 1.8, mapSize, span: 8 });
    const floor = new THREE.Mesh(new THREE.CircleGeometry(200, 48).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0xc9b27a }));
    floor.position.y = -0.02;
    floor.receiveShadow = true;
    scene.add(floor);
    stage = new THREE.Mesh(new THREE.CircleGeometry(1, 64).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ map: stageTexture("#e8d7a5", "#d4bf86", "#c9b27a"), transparent: true }));
  }
  stage.receiveShadow = true;
  scene.add(stage);
  return { scene, decor, sun, stage, kind };
}

/* seaweed that sways, built from stacked boxes */
function seaweed(r, h) {
  const g = new THREE.Group();
  const mat = new THREE.MeshLambertMaterial({ color: new THREE.Color().setHSL(0.3 + r() * 0.08, 0.55, 0.3 + r() * 0.1) });
  let parent = g;
  const n = 6, seg = h / n;
  for (let i = 0; i < n; i++) {
    const piece = new THREE.Group();
    const m = new THREE.Mesh(new THREE.BoxGeometry(0.16 * (1 - i / n * 0.6), seg * 1.05, 0.05), mat);
    m.position.y = seg / 2;
    m.userData.own = true;
    piece.add(m);
    piece.position.y = i ? seg : 0;
    parent.add(piece);
    parent = piece;
  }
  g.userData.sway = r() * 6;
  return g;
}

export function createFamily(renderer, isMobile) {
  const camera = new THREE.PerspectiveCamera(38, 1, 0.05, 1500);
  const controls = new OrbitControls(camera, renderer.domElement);
  Object.assign(controls, { enableDamping: true, dampingFactor: 0.08, enablePan: false, autoRotate: true, autoRotateSpeed: 1.4, maxPolarAngle: 1.5, minPolarAngle: 0.2, rotateSpeed: 0.8 });
  controls.enabled = false;
  let lastTouch = -1e9;
  controls.addEventListener("start", () => { controls.autoRotate = false; lastTouch = performance.now(); });
  controls.addEventListener("end", () => { lastTouch = performance.now(); });

  const envs = {};
  let env = null, members = [], weeds = [], bubbles = null, R = 1, subject = null;
  const labels = [];
  const real = {};
  const realModel = async k => (real[k] ||= await A.load(A.url("real", k)));
  let tuftModel = null;

  /* free what was built just for the last visit (shared model geometry and cached materials stay) */
  function reset(kind) {
    const free = o => o.traverse(x => {
      if (x.isInstancedMesh) x.dispose();
      if (x.userData.own) { x.geometry.dispose(); [].concat(x.material).forEach(m => m.dispose()); }
      else if (x.userData.ownGeo) x.geometry.dispose();
    });
    if (env) { for (const m of members) { env.scene.remove(m); free(m); } free(env.decor); env.decor.clear(); }
    env = envs[kind] || (envs[kind] = makeEnv(kind, isMobile, renderer));
    members = [];
    weeds = [];
    subject = null;
    labels.length = 0;
  }

  /* ferns, weeds, sorrel and grass in a ring round the stage, low in front of the camera */
  async function landRing(seed, scale = Math.min(1.6, Math.max(0.8, R * 0.35))) {
    const r = rng(seed);
    tuftModel ||= F.asModel(grassTuft());
    const kinds = { fern: [await realModel("fern"), 1.1], weed_plant: [await realModel("weed_plant"), 0.7], shrub_sorrel: [await realModel("shrub_sorrel"), 0.35], grass: [tuftModel, 0.6] };
    const byKey = {};
    for (let i = 0; i < 90; i++) {
      const a = r() * Math.PI * 2, front = Math.sin(a) > 0.25;
      const d = R * (front ? 1.25 + r() * 0.5 : 1.1 + r() * 0.9);
      const key = front ? (r() < 0.8 ? "grass" : "shrub_sorrel") : ["fern", "weed_plant", "grass", "grass", "fern", "shrub_sorrel"][(r() * 6) | 0];
      const h = kinds[key][1] * (0.7 + r() * 0.6) * scale;
      (byKey[key] ||= []).push(new THREE.Matrix4().compose(new THREE.Vector3(Math.cos(a) * d, 0, Math.sin(a) * d), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, r() * 6, 0)), new THREE.Vector3(h, h, h)));
    }
    for (const [k, mats] of Object.entries(byKey)) env.decor.add(A.scatter(kinds[k][0], mats));
  }

  async function show(sp, isFish, view = { fw: 1, fh: 1, aspect: 1.6 }) {
    reset(isFish ? "water" : "land");

    const add = (obj, role, x, z, yaw, y = 0) => {
      obj.position.set(x, y, z);
      obj.rotation.y = yaw;
      Object.assign(obj.userData, { role, x, z, y, yaw, phase: Math.random() * 6, base: obj.userData.inner ? obj.userData.inner.scale.y : 1 });
      env.scene.add(obj);
      members.push(obj);
      return obj;
    };

    if (!isFish) {
      const gm = await A.load(A.url("animals", sp.models.m));
      const gf = await A.load(A.url("animals", sp.models.f));
      const size = k => sp.len ? { len: sp.len * k } : { h: sp.h * k };
      const dad = A.instance(gm, { ...size(1), yaw: sp.yaw });
      const mum = A.instance(gf, { ...size(sp.fs || 0.9), yaw: sp.models.f === sp.models.m ? sp.yaw : 0, tint: sp.tint && sp.tint.f });
      const kids = [];
      for (let i = 0; i < sp.n; i++) {
        if (sp.models.b === "tadpole") kids.push(A.tadpole((sp.len || sp.h) * sp.bs));
        else {
          const gb = await A.load(A.url("animals", sp.models.b));
          const own = sp.models.b !== sp.models.m;           // a real baby model: size it on its own
          kids.push(A.instance(gb, { ...(own && !sp.len ? { h: sp.h * sp.bs } : size(sp.bs)), yaw: own ? 0 : sp.yaw, tint: sp.tint && (sp.tint.b ?? (sp.models.b === sp.models.f ? sp.tint.f : undefined)) }));
        }
      }
      const foot = o => { const d = o.userData.dims; return 0.5 * Math.hypot(d.w, d.l) * 0.78; };
      const rd = foot(dad), rm = foot(mum);
      const dx = -(rd + 0.12), mx = rm + 0.12;
      add(dad, "father", dx, 0, 0.55);
      add(mum, "mother", mx, 0, -0.55);
      const back = Math.max(dad.userData.dims.l, mum.userData.dims.l) * 0.45;
      if (kids.length) {
        const bw = Math.max(kids[0].userData.dims.w, kids[0].userData.dims.l * 0.5) + 0.12;
        const bz = back + kids[0].userData.dims.l * 0.5 + 0.25;
        kids.forEach((k, i) => {
          const off = (i - (kids.length - 1) / 2) * bw;
          add(k, "baby", off + (mx + dx) / 2, bz + Math.abs(off) * -0.15, (i - (kids.length - 1) / 2) * -0.25);
          k.userData.hop = !!sp.hop;
        });
      }
      if (sp.eggs) {
        const size = Math.max(0.035, (sp.len || sp.h) * (sp.id === "frog" ? 0.05 : 0.06));
        const nest = A.eggs(EGG_KIND[sp.id] || "bird", sp.eggs, size);
        const ex = mx + rm + nest.userData.dims.w * 0.5 + 0.1;
        add(nest, "eggs", ex, back * 0.6, 0);
      }
      // a ring of plants around the stage
      const span = new THREE.Box3();
      members.forEach(m => span.expandByPoint(m.position.clone().setY(0)));
      R = Math.max(span.getSize(new THREE.Vector3()).length() * 0.5 + Math.max(dad.userData.dims.w, dad.userData.dims.l) * 0.7, 1.2);
      await landRing(sp.id.length * 31);
    } else {
      const g = await A.load(A.url("fish", sp.model));
      const L = FISH_LEN[sp.id] || 1.15;
      const dad = A.instance(g, { len: L });
      const mum = A.instance(g, { len: L * (sp.fs || 1) });
      const lift = L * 0.75;
      add(dad, "father", -L * 0.62, 0, 0.9, lift);
      add(mum, "mother", L * 0.62 * (sp.fs || 1), 0, -0.9, lift + 0.1);
      A.play(dad, ["Swimming_Normal", "Swim"]);
      A.play(mum, ["Swimming_Normal", "Swim"]);
      const nest = A.eggs("fish", sp.eggs, L * 0.045);
      add(nest, "eggs", 0, L * 0.9, 0, 0.02);
      R = L * 1.9;
      const r = rng(sp.id.length * 17);
      for (let i = 0; i < 22; i++) {
        const a = (i / 22) * Math.PI * 2 + r() * 0.25, front = Math.sin(a) > 0.2;
        const d = R * (front ? 1.7 + r() * 0.4 : 1.2 + r() * 0.8);
        const w = seaweed(r, R * (front ? 0.25 + r() * 0.2 : 0.5 + r() * 0.7));
        w.position.set(Math.cos(a) * d, 0, Math.sin(a) * d);
        env.decor.add(w);
        weeds.push(w);
      }
      const rocks = [];
      for (let i = 0; i < 10; i++) {
        const a = r() * Math.PI * 2, d = R * (1.1 + r() * 0.9), h = R * (0.12 + r() * 0.2);
        rocks.push(new THREE.Matrix4().compose(new THREE.Vector3(Math.cos(a) * d, -0.05, Math.sin(a) * d), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, r() * 6, 0)), new THREE.Vector3(h, h, h)));
      }
      env.decor.add(A.scatter(await A.load(A.url("nature", "rock-moss")), rocks));
      // bubbles
      const bn = 40;
      bubbles = new THREE.InstancedMesh(new THREE.SphereGeometry(1, 10, 8), new THREE.MeshPhongMaterial({ color: 0xdff6ff, transparent: true, opacity: 0.45, shininess: 120 }), bn);
      bubbles.userData.own = true;
      bubbles.userData.seed = Array.from({ length: bn }, () => [(r() - 0.5) * R * 3, (r() - 0.5) * R * 3, r() * 10, 0.02 + r() * 0.05]);
      env.decor.add(bubbles);
    }

    return frame(view, isFish);
  }

  function frame(view, isFish) {
    env.stage.scale.setScalar(R * 1.15);
    if (env.stage.userData.tiles) env.stage.userData.tiles.forEach(t => t.repeat.set(R * 0.6, R * 0.6));
    for (const m of members) m.traverse(o => { if (o.isMesh) { o.castShadow = true; } });
    for (const m of members) if (m.userData.mixer && !isFish) A.play(m, ["Idle", "Idle_2", "Eating"]);

    // frame everyone (precise bounds: skinned models report bind-pose boxes otherwise)
    const box = new THREE.Box3();
    for (const m of members) {
      m.updateMatrixWorld(true);
      const b = new THREE.Box3().setFromObject(m, true);
      Object.assign(m.userData, { top: b.max.y - m.position.y, cx: (b.min.x + b.max.x) / 2 - m.position.x, cz: (b.min.z + b.max.z) / 2 - m.position.z });
      box.union(b);
    }
    const c = box.getCenter(new THREE.Vector3()), sz = box.getSize(new THREE.Vector3());
    const rad = Math.max(sz.length() * 0.5, 0.6);
    // fit the family into the part of the screen the panel leaves free
    const tv = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const dist = rad / Math.min(tv * view.fh, tv * view.aspect * view.fw) * 1.02;
    controls.target.set(c.x, c.y * 0.9, c.z);
    camera.position.set(c.x + dist * 0.25, c.y + rad * 0.45, c.z + dist);
    controls.minDistance = dist * 0.4;
    controls.maxDistance = dist * 2.2;
    controls.autoRotate = true;
    controls.update();
    const s = env.sun.shadow.camera;
    s.left = s.bottom = -rad * 1.6; s.right = s.top = rad * 1.6; s.updateProjectionMatrix();
    env.sun.target.position.copy(c);
    env.sun.position.copy(c).addScaledVector(SUN_DIR, rad * 7);

    if (subject) return env.scene;                                  // plant view: labels made by showPlant
    // one label per father / mother, one for the babies, one for the eggs
    for (const role of ["father", "mother"]) {
      const m = members.find(o => o.userData.role === role);
      labels.push({ role, obj: [m], pos: new THREE.Vector3() });
    }
    const kids = members.filter(o => o.userData.role === "baby");
    if (kids.length) labels.push({ role: "baby", count: kids.length, obj: kids, pos: new THREE.Vector3() });
    const nest = members.find(o => o.userData.role === "eggs");
    if (nest) labels.push({ role: "eggs", obj: [nest], pos: new THREE.Vector3() });
    return env.scene;
  }

  /* A wild plant on the stage, with a magnified leaf and its fruit / flower beside it. */
  async function showPlant(pl, view = { fw: 1, fh: 1, aspect: 1.6 }) {
    reset("land");
    const add = (obj, role, x, z, yaw = 0, y = 0) => {
      obj.position.set(x, y, z);
      obj.rotation.y = yaw;
      Object.assign(obj.userData, { role, x, z, y, yaw, phase: Math.random() * 6 });
      env.scene.add(obj);
      members.push(obj);
      return obj;
    };
    let g;
    if (pl.id === "fern") { g = A.instance(await realModel("fern"), { h: 1.3 }); g.traverse(o => { if (o.isMesh) o.userData.character = false; }); }
    else {
      g = F.build(pl.id, 1);
      g.traverse(o => { if (o.isMesh) o.userData.ownGeo = true; });
      if (pl.id === "mushroom") {
        const stump = A.instance(await realModel("tree_stump"), { h: 0.7 });
        stump.traverse(o => { if (o.isMesh) { o.userData.character = false; o.castShadow = o.receiveShadow = true; } });
        stump.position.set(-0.6, -0.05, -0.3);
        g.add(stump);
      }
    }
    g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    add(g, "plant", 0, 0);
    subject = g;
    const box = new THREE.Box3().setFromObject(g), size = box.getSize(new THREE.Vector3());
    const H = size.y, crownR = Math.max(size.x, size.z) / 2;
    const mag = H > 4 ? H / 3.6 : Math.min(1.2, Math.max(0.45, H * 0.45));   // big trees get magnified close-ups; small plants near life-size
    const front = H > 4 ? Math.max(1.4, Math.min(crownR * 0.8, 8)) : Math.max(0.5, crownR + 0.35 * mag);
    const specimens = [];
    for (const part of pl.shows) {
      if (part === "roots") continue;
      const m = part === "leaf" ? F.leafSpecimen(pl.id, 0.9) : F.fruitSpecimen(pl.id);
      if (!m) continue;
      m.traverse(o => { if (o.isMesh) o.userData.own = true; });
      m.scale.setScalar(part === "leaf" ? mag : mag * 1.4);
      specimens.push({ part, m });
    }
    specimens.forEach(({ part, m }, i) => {
      const x = (i - (specimens.length - 1) / 2) * 1.1 * mag;
      add(m, "specimen", x, front, 0, 0.25 * mag).userData.part = part;
    });
    R = Math.max(crownR, H > 4 ? 2.2 : 0.9) * 1.05;
    await landRing(pl.id.length * 17, Math.min(1.6, Math.max(0.25, H * 0.5)));
    frame(view, false);
    labels.push({ role: "name", obj: [g], pos: new THREE.Vector3() });
    for (const { part, m } of specimens) labels.push({ role: part, obj: [m], pos: new THREE.Vector3() });
    if (pl.shows.includes("roots")) labels.push({ role: "roots", fixed: new THREE.Vector3(crownR * 0.45, H * 0.28, crownR * 0.35), obj: [], pos: new THREE.Vector3() });
    return env.scene;
  }

  function update(dt, t) {
    if (!env) return;
    if (!controls.autoRotate && performance.now() - lastTouch > 7000) controls.autoRotate = true;
    controls.update(dt);
    F.wind.value = t;
    if (subject) F.updateFold(subject, t);
    for (const m of members) {
      const u = m.userData;
      if (u.mixer) u.mixer.update(dt);
      if (u.role === "eggs" || u.role === "plant") continue;
      if (u.role === "specimen") {                                  // keep the close-ups turned to the viewer
        m.rotation.y = Math.atan2(camera.position.x - m.position.x, camera.position.z - m.position.z) + Math.sin(t * 0.7 + u.phase) * 0.25;
        m.position.y = u.y + Math.sin(t * 1.3 + u.phase) * 0.04 * m.scale.x;
        continue;
      }
      if (env.kind === "water") {
        m.position.y = u.y + Math.sin(t * 1.3 + u.phase) * 0.06;
        m.rotation.y = u.yaw + Math.sin(t * 0.5 + u.phase) * 0.25;
        continue;
      }
      if (!u.mixer && u.inner) u.inner.scale.y = u.base * (1 + 0.018 * Math.sin(t * 2.1 + u.phase));
      if (u.role === "baby") {
        const bounce = u.hop ? Math.pow(Math.max(0, Math.sin(t * 3 + u.phase)), 4) * 0.35 : Math.max(0, Math.sin(t * 2.2 + u.phase)) * 0.06;
        m.position.y = u.y + bounce * u.dims.h;
        m.rotation.y = u.yaw + Math.sin(t * 0.9 + u.phase) * 0.45;
        if (u.tail) u.tail.rotation.y = Math.sin(t * 9 + u.phase) * 0.5;
      } else if (!u.mixer) {
        m.rotation.y = u.yaw + Math.sin(t * 0.3 + u.phase) * 0.12;
      }
    }
    for (const w of weeds) {
      let p = w.children[0], k = 0;
      while (p) { p.rotation.z = Math.sin(t * 1.2 + w.userData.sway + k) * 0.12; p.rotation.x = Math.cos(t * 0.9 + w.userData.sway + k) * 0.06; p = p.children[1]; k += 0.4; }
    }
    if (bubbles && env.kind === "water") {
      const m = new THREE.Matrix4(), q = new THREE.Quaternion();
      bubbles.userData.seed.forEach(([x, z, o, s], i) => {
        const y = ((t * 0.6 + o) % 10) / 10 * R * 2.5;
        m.compose(new THREE.Vector3(x + Math.sin(t + o) * 0.1, y, z), q, new THREE.Vector3(s * R, s * R, s * R));
        bubbles.setMatrixAt(i, m);
      });
      bubbles.instanceMatrix.needsUpdate = true;
    }
    for (const l of labels) {
      if (l.fixed) { l.pos.copy(l.fixed); continue; }
      let top = -1e9, x = 0, z = 0;
      for (const o of l.obj) { x += o.position.x + o.userData.cx; z += o.position.z + o.userData.cz; top = Math.max(top, o.position.y + o.userData.top); }
      l.pos.set(x / l.obj.length, top + 0.1 * R, z / l.obj.length);
    }
  }

  return { camera, controls, show, showPlant, update, labels, get scene() { return env && env.scene; }, get subject() { return subject; } };
}
