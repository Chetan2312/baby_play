/* Under the pond: fish we eat swim on the left, fish we don't eat on the right. */
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import * as A from "./assets.js";
import { FISH } from "./data.js";
import { skyDome, addLights, rng, radial } from "./env.js";

export const fishUrls = FISH.map(f => A.url("fish", f.model));

export function createFishWorld(renderer, isMobile) {
  const scene = new THREE.Scene();
  scene.userData.kind = "water";
  scene.background = new THREE.Color(0x0e6496);
  scene.fog = new THREE.FogExp2(0x0e6496, 0.028);
  scene.add(skyDome(0x47c1ec, 0x1273aa, 0x073556));
  const sun = addLights(scene, { sky: 0xb4ecff, ground: 0x1c4a5e, hemi: 2.1, sun: 0xdaf7ff, sunI: 1.6, mapSize: isMobile ? 1024 : 2048, span: 22 });
  sun.position.set(6, 40, 10);

  const camera = new THREE.PerspectiveCamera(50, 1, 0.1, 1500);
  camera.position.set(0, 5.5, 20);
  const controls = new OrbitControls(camera, renderer.domElement);
  Object.assign(controls, { enableDamping: true, dampingFactor: 0.08, enablePan: false, minDistance: 8, maxDistance: 26, maxPolarAngle: 1.62, minPolarAngle: 0.5, minAzimuthAngle: -0.9, maxAzimuthAngle: 0.9, rotateSpeed: 0.7 });
  controls.target.set(0, 3.2, 0);
  controls.enabled = false;

  const r = rng(99);
  // sandy floor with dunes
  const floorG = new THREE.PlaneGeometry(160, 160, 90, 90).rotateX(-Math.PI / 2);
  const p = floorG.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i);
    p.setY(i, Math.sin(x * 0.25) * 0.25 + Math.cos(z * 0.18 + x * 0.05) * 0.35 + Math.max(0, Math.hypot(x, z) - 26) * 0.25);
  }
  floorG.computeVertexNormals();
  const floor = new THREE.Mesh(floorG, new THREE.MeshLambertMaterial({ color: 0xd9c38f }));
  floor.receiveShadow = true;
  scene.add(floor);

  // light shafts from the surface
  const shaftMat = new THREE.MeshBasicMaterial({ map: radial("rgba(220,250,255,0.28)", "rgba(220,250,255,0)"), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false });
  const shafts = [];
  for (let i = 0; i < 9; i++) {
    const s = new THREE.Mesh(new THREE.PlaneGeometry(3 + r() * 3, 30), shaftMat);
    s.position.set((r() - 0.5) * 34, 13, (r() - 0.5) * 16 - 4);
    s.rotation.z = 0.25;
    s.userData.o = r() * 6;
    scene.add(s);
    shafts.push(s);
  }

  // seaweed and coral-ish rocks along the back and sides
  const weeds = [];
  const weedMats = [0x2f8f4e, 0x3aa35a, 0x5cae3c, 0x2b7a5f].map(c => new THREE.MeshLambertMaterial({ color: c }));
  for (let i = 0; i < 70; i++) {
    const g = new THREE.Group();
    const h = 2 + r() * 5, n = 7, seg = h / n;
    let parent = g;
    const mat = weedMats[i % 4];
    for (let k = 0; k < n; k++) {
      const piece = new THREE.Group();
      const m = new THREE.Mesh(new THREE.BoxGeometry(0.35 * (1 - k / n * 0.6), seg * 1.05, 0.08), mat);
      m.position.y = seg / 2;
      piece.add(m);
      piece.position.y = k ? seg : 0;
      parent.add(piece);
      parent = piece;
    }
    const side = i % 3;
    const x = side === 0 ? (r() - 0.5) * 44 : (side === 1 ? -1 : 1) * (15 + r() * 8);
    const z = side === 0 ? -10 - r() * 8 : (r() - 0.5) * 20;
    g.position.set(x, 0, z);
    g.rotation.y = r() * 6;
    g.userData.o = r() * 6;
    scene.add(g);
    weeds.push(g);
  }
  let rocksReady = A.load(A.url("nature", "rock-moss")).then(gl => {
    const mats = [];
    for (let i = 0; i < 26; i++) {
      const a = r() * Math.PI - Math.PI, d = 14 + r() * 10, h = 0.8 + r() * 2.2;
      mats.push(new THREE.Matrix4().compose(new THREE.Vector3(Math.cos(a) * d * 1.3, -0.1, Math.sin(a) * d * 0.7 - 3), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, r() * 6, 0)), new THREE.Vector3(h, h, h)));
    }
    scene.add(A.scatter(gl, mats));
  });

  // the dividing line: a low ridge of pebbles down the middle
  const pebble = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.3, 0), new THREE.MeshLambertMaterial({ color: 0xa99c86 }), 40);
  for (let i = 0; i < 40; i++) {
    const s = 0.4 + r() * 0.5;
    pebble.setMatrixAt(i, new THREE.Matrix4().compose(new THREE.Vector3((r() - 0.5) * 0.8, 0.05, -10 + i * 0.3), new THREE.Quaternion().setFromEuler(new THREE.Euler(r(), r(), r())), new THREE.Vector3(s, s * 0.6, s)));
  }
  scene.add(pebble);

  // bubbles
  const bn = 90;
  const bubbles = new THREE.InstancedMesh(new THREE.SphereGeometry(1, 10, 8), new THREE.MeshPhongMaterial({ color: 0xe4f8ff, transparent: true, opacity: 0.4, shininess: 120 }), bn);
  const bseed = Array.from({ length: bn }, () => [(r() - 0.5) * 40, (r() - 0.5) * 18 - 2, r() * 14, 0.04 + r() * 0.1]);
  scene.add(bubbles);

  const fish = [];
  const labels = [];
  const hits = [];
  const zoneLabels = [
    { zone: "edible", pos: new THREE.Vector3(-8, 10.6, -4) },
    { zone: "inedible", pos: new THREE.Vector3(8, 10.6, -4) },
  ];
  let built = null;

  function build() {
    if (built) return built;
    built = (async () => {
      await Promise.all(fishUrls.map(A.load));
      const groups = { true: FISH.filter(f => f.edible), false: FISH.filter(f => !f.edible) };
      for (const [edible, list] of Object.entries(groups)) {
        const sx = edible === "true" ? -1 : 1;
        for (let i = 0; i < list.length; i++) {
          const sp = list[i];
          const gltf = await A.load(A.url("fish", sp.model));
          const L = { swordfish: 2.5, tuna: 2.1, trout: 1.9 }[sp.id] || 1.7;
          const f = A.instance(gltf, { len: L });
          A.play(f, ["Swimming_Normal", "Swim"]);
          // each fish swims a small loop in its own spot of its half
          f.userData.loop = { i, sx, rx0: 1.3 + r() * 0.8, rz: 0.9 + r() * 0.6, s: (r() < 0.5 ? -1 : 1) * (0.35 + r() * 0.25), a: r() * 6 };
          f.userData.sp = sp;
          const hit = new THREE.Mesh(new THREE.SphereGeometry(L * 0.75, 8, 6), new THREE.MeshBasicMaterial());
          hit.visible = false;
          hit.position.y = f.userData.dims.h * 0.5;
          hit.userData.hit = { type: "fish", id: sp.id };
          f.add(hit);
          hits.push(hit);
          scene.add(f);
          fish.push(f);
          labels.push({ id: sp.id, obj: f, pos: new THREE.Vector3() });
        }
      }
      await rocksReady;
      layout(tall);
    })();
    return built;
  }

  /* Wide screens: eat on the left, don't eat on the right.
     Tall phone screens: eat on top, don't eat below. */
  let tall = false;
  function layout(isTall) {
    tall = isTall;
    for (const f of fish) {
      const L = f.userData.loop, row = Math.floor(L.i / 3), col = L.i % 3;
      if (!tall) Object.assign(L, { cx: L.sx * (3.2 + col * 3.9 + (row % 2) * 1.4), cy: 1.7 + row * 2.3, cz: -1.5 + (col % 2) * 2.2 - row * 0.8, rx: L.rx0 });
      else Object.assign(L, { cx: (col - 1) * 3.1 + (row % 2 ? 0.7 : -0.3), cy: (L.sx < 0 ? 9.4 : 1.6) + row * 2.0, cz: -1 + (col % 2) * 1.5, rx: 0.7 });
    }
    zoneLabels[0].pos.set(tall ? 0 : -8, tall ? 16.2 : 10.6, -4);
    zoneLabels[1].pos.set(tall ? 0 : 8, tall ? 8.2 : 10.6, -4);
    pebble.visible = !tall;
  }

  function update(dt, t) {
    controls.update(dt);
    for (const f of fish) {
      const L = f.userData.loop, a = L.a + t * L.s;
      f.position.set(L.cx + Math.cos(a) * L.rx, L.cy + Math.sin(t * 0.9 + L.a) * 0.25, L.cz + Math.sin(a) * L.rz);
      const vx = -Math.sin(a) * L.rx * Math.sign(L.s), vz = Math.cos(a) * L.rz * Math.sign(L.s);
      f.rotation.y = Math.atan2(vx, vz);
      f.userData.mixer && f.userData.mixer.update(dt);
    }
    for (const l of labels) l.pos.copy(l.obj.position).y += l.obj.userData.dims.h + 0.45;
    for (const w of weeds) {
      let p = w.children[0], k = 0;
      while (p) { p.rotation.z = Math.sin(t * 1.1 + w.userData.o + k) * 0.1; p = p.children[1]; k += 0.35; }
    }
    shafts.forEach(s => { s.material.opacity = 1; s.position.x += Math.sin(t * 0.2 + s.userData.o) * 0.004; });
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), v = new THREE.Vector3(), sc = new THREE.Vector3();
    bseed.forEach(([x, z, o, s], i) => {
      v.set(x + Math.sin(t + o) * 0.2, ((t * 0.9 + o) % 14), z);
      sc.setScalar(s);
      bubbles.setMatrixAt(i, m.compose(v, q, sc));
    });
    bubbles.instanceMatrix.needsUpdate = true;
  }

  return { scene, camera, controls, build, update, labels, zoneLabels, hits, layout };
}
