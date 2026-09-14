/* "Meet the family": father, mother, babies (and eggs) on a round stage that
   the child can spin all the way round. Used for land animals and for fish. */
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import * as A from "./assets.js";
import { skyDome, addLights, stageTexture, rng } from "./env.js";

const EGG_KIND = { crocodile: "reptile", turtle: "reptile", cobra: "reptile", frog: "frog", parrot: "bird", owl: "bird", hornbill: "bird", duck: "bird" };
const FISH_LEN = { swordfish: 1.7, tuna: 1.45, trout: 1.3 };

function makeEnv(kind, isMobile) {
  const scene = new THREE.Scene();
  const decor = new THREE.Group();
  scene.add(decor);
  let sun;
  if (kind === "land") {
    scene.background = new THREE.Color(0xd8f1f6);
    scene.fog = new THREE.Fog(0xd8f1f6, 30, 120);
    scene.add(skyDome(0x5cb8ee, 0xe4f6f0, 0x8fb86a));
    sun = addLights(scene, { mapSize: isMobile ? 1024 : 2048, span: 8 });
    const ground = new THREE.Mesh(new THREE.CircleGeometry(200, 48).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0x78ad45 }));
    ground.position.y = -0.02;
    ground.receiveShadow = true;
    scene.add(ground);
  } else {
    scene.background = new THREE.Color(0x0d5e8f);
    scene.fog = new THREE.Fog(0x0d5e8f, 8, 55);
    scene.add(skyDome(0x3fb2e0, 0x0f6699, 0x06324f));
    sun = addLights(scene, { sky: 0xaee9ff, ground: 0x1d4a5c, hemi: 2.0, sun: 0xd9f7ff, sunI: 1.8, mapSize: isMobile ? 1024 : 2048, span: 8 });
    const floor = new THREE.Mesh(new THREE.CircleGeometry(200, 48).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ color: 0xc9b27a }));
    floor.position.y = -0.02;
    floor.receiveShadow = true;
    scene.add(floor);
  }
  const tex = kind === "land" ? stageTexture("#8cc152", "#6fa53b", "#78ad45") : stageTexture("#e8d7a5", "#d4bf86", "#c9b27a");
  const stage = new THREE.Mesh(new THREE.CircleGeometry(1, 64).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ map: tex, transparent: true }));
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
  let env = null, members = [], weeds = [], bubbles = null, R = 1;
  const labels = [];

  async function show(sp, isFish, view = { fw: 1, fh: 1, aspect: 1.6 }) {
    const kind = isFish ? "water" : "land";
    env = envs[kind] || (envs[kind] = makeEnv(kind, isMobile));
    // free what was built just for the last visit (shared model geometry stays)
    const free = o => o.traverse(x => {
      if (x.isInstancedMesh) x.dispose();
      if (x.userData.own) { x.geometry.dispose(); [].concat(x.material).forEach(m => m.dispose()); }
    });
    for (const m of members) { env.scene.remove(m); free(m); }
    members = [];
    free(env.decor);
    env.decor.clear();
    weeds = [];
    labels.length = 0;

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
      const r = rng(sp.id.length * 31);
      const byKey = {};
      const scale = Math.min(1.6, Math.max(0.5, R * 0.35));
      for (let i = 0; i < 30; i++) {
        const a = (i / 30) * Math.PI * 2 + r() * 0.15, front = Math.sin(a) > 0.2;   // +z faces the camera
        const d = R * (front ? 1.35 + r() * 0.3 : 1.45 + r() * 0.6);
        const key = front ? ["flowers-1", "flowers-2", "grass"][(r() * 3) | 0] : ["bush-flowers", "flowers-1", "tall-grass", "bush-1", "bush-berries", "flowers-2"][(r() * 6) | 0];
        const h = scale * (key.startsWith("bush") ? 1.2 : 0.55) * (front ? 0.6 : 1) * (0.7 + r() * 0.6);
        (byKey[key] ||= []).push(new THREE.Matrix4().compose(new THREE.Vector3(Math.cos(a) * d, 0, Math.sin(a) * d), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, r() * 6, 0)), new THREE.Vector3(h, h, h)));
      }
      for (const [k, mats] of Object.entries(byKey)) env.decor.add(A.scatter(await A.load(A.url("nature", k)), mats));
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

    env.stage.scale.setScalar(R * 1.15);
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
    env.sun.position.copy(c).add(new THREE.Vector3(rad * 3, rad * 6, rad * 2.5));

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

  function update(dt, t) {
    if (!env) return;
    if (!controls.autoRotate && performance.now() - lastTouch > 7000) controls.autoRotate = true;
    controls.update(dt);
    for (const m of members) {
      const u = m.userData;
      if (u.mixer) u.mixer.update(dt);
      if (u.role === "eggs") continue;
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
      let top = -1e9, x = 0, z = 0;
      for (const o of l.obj) { x += o.position.x + o.userData.cx; z += o.position.z + o.userData.cz; top = Math.max(top, o.position.y + o.userData.top); }
      l.pos.set(x / l.obj.length, top + 0.1 * R, z / l.obj.length);
    }
  }

  return { camera, controls, show, update, labels, get scene() { return env && env.scene; } };
}
