/* "Anime look": soft cel shading, ink outlines on the animals only (painted
   backgrounds in anime have no lines), a painted sky with cartoon clouds,
   floating petals and brighter, warmer light. Everything here is reversible —
   the classic look keeps its own materials and settings. */
import * as THREE from "three";
import { OutlineEffect } from "three/addons/effects/OutlineEffect.js";
import { rng } from "./env.js";

const INK = [0.035, 0.018, 0.028];             // warm brown-black (linear), softer than pure black

function ramp(steps) {
  const t = new THREE.DataTexture(new Uint8Array(steps.map(v => Math.round(v * 255))), steps.length, 1, THREE.RedFormat);
  t.minFilter = t.magFilter = THREE.NearestFilter;
  t.needsUpdate = true;
  return t;
}
const RAMP_CHAR = ramp([0.55, 0.82, 1]);       // animals: three soft bands
const RAMP_WORLD = ramp([0.68, 0.9, 1]);       // scenery: gentler, more painterly

const PALETTE = {
  land: {
    sky: [0x2f8ae6, 0xc8eeff, 0xa6d884], bg: 0xc8eeff, fog: 0xd2f0fb,
    hemi: [0xfff8ea, 0x86b85a, 2.5], sun: [0xfff0d2, 2.1],
  },
  water: {
    sky: [0x86e4ff, 0x2aa2de, 0x0c5c90], bg: 0x2aa2de, fog: 0x2aa2de,
    hemi: [0xe6faff, 0x3c8496, 2.6], sun: [0xeafcff, 1.7],
  },
};

/* ---- materials ---- */
const toonCache = new Map();
function toon(m, character) {
  const convertible = m.isMeshStandardMaterial || m.isMeshLambertMaterial || m.isMeshPhongMaterial;
  if (!convertible || m.userData.noToon) {
    m.userData.outlineParameters = { visible: false };
    return m;
  }
  const key = m.uuid + (character ? ":c" : ":w");
  if (toonCache.has(key)) return toonCache.get(key);
  const t = new THREE.MeshToonMaterial({
    name: m.name, color: m.color.clone(), map: m.map || null, vertexColors: m.vertexColors,
    transparent: m.transparent, opacity: m.opacity, alphaTest: m.alphaTest, side: m.side,
    depthWrite: m.depthWrite, blending: m.blending,
    polygonOffset: m.polygonOffset, polygonOffsetFactor: m.polygonOffsetFactor, polygonOffsetUnits: m.polygonOffsetUnits,
    emissive: m.emissive ? m.emissive.clone() : new THREE.Color(0), emissiveIntensity: m.emissiveIntensity ?? 1,
    gradientMap: character ? RAMP_CHAR : RAMP_WORLD,
  });
  if (character) {
    // a hard-edged warm rim, the little glow round an anime character's outline
    t.onBeforeCompile = sh => {
      sh.fragmentShader = sh.fragmentShader.replace("#include <opaque_fragment>", `
        float rimF = 1.0 - saturate( dot( normal, normalize( vViewPosition ) ) );
        outgoingLight += vec3( 1.0, 0.93, 0.8 ) * smoothstep( 0.6, 0.75, rimF ) * 0.3;
        #include <opaque_fragment>`);
    };
    t.customProgramCacheKey = () => "toon-rim";
    t.userData.outlineParameters = { thickness: 0.0075, color: INK, alpha: 1, visible: true };
  } else {
    t.userData.outlineParameters = { visible: false };
  }
  toonCache.set(key, t);
  return t;
}

/* Low-poly models have one normal per face, which reads as "facets".
   Averaging the normals of vertices that share a position gives soft,
   rounded shading bands — and closes the gaps in the ink outline. */
const smoothCache = new WeakMap();
function smoothed(geo) {
  if (smoothCache.has(geo)) return smoothCache.get(geo);
  const pos = geo.attributes.position, nor = geo.attributes.normal;
  if (!pos || !nor) { smoothCache.set(geo, geo); return geo; }
  if (!geo.boundingBox) geo.computeBoundingBox();
  const q = geo.boundingBox.getSize(new THREE.Vector3()).length() * 2e-4 || 1e-6;
  const sums = new Map(), keys = new Array(pos.count);
  for (let i = 0; i < pos.count; i++) {
    const k = Math.round(pos.getX(i) / q) + "," + Math.round(pos.getY(i) / q) + "," + Math.round(pos.getZ(i) / q);
    keys[i] = k;
    let a = sums.get(k);
    if (!a) sums.set(k, (a = [0, 0, 0]));
    a[0] += nor.getX(i); a[1] += nor.getY(i); a[2] += nor.getZ(i);
  }
  const out = new Float32Array(pos.count * 3);
  for (let i = 0; i < pos.count; i++) {
    const a = sums.get(keys[i]), l = Math.hypot(a[0], a[1], a[2]) || 1;
    out[3 * i] = a[0] / l; out[3 * i + 1] = a[1] / l; out[3 * i + 2] = a[2] / l;
  }
  const g = new THREE.BufferGeometry();
  for (const [name, attr] of Object.entries(geo.attributes)) g.setAttribute(name, attr);
  g.setAttribute("normal", new THREE.BufferAttribute(out, 3));
  g.setIndex(geo.index);
  g.groups = geo.groups;
  g.boundingBox = geo.boundingBox; g.boundingSphere = geo.boundingSphere;
  smoothCache.set(geo, g);
  return g;
}

function restyle(root, on) {
  root.traverse(o => {
    if (!o.isMesh && !o.isSprite) return;
    if (o.isSprite) { o.material.userData.outlineParameters = { visible: false }; return; }
    if (o.userData.orig === undefined) { o.userData.orig = o.material; o.userData.origGeo = o.geometry; }
    const orig = o.userData.orig;
    if (!on) { o.material = orig; o.geometry = o.userData.origGeo; return; }
    const ch = !!o.userData.character && !o.isInstancedMesh;   // the outline shader can't do instancing
    o.material = Array.isArray(orig) ? orig.map(m => toon(m, ch)) : toon(orig, ch);
    if ((o.userData.character || o.userData.plant) && !o.userData.own) o.geometry = smoothed(o.userData.origGeo);
  });
}

/* ---- sky, light, fog ---- */
function mood(scene, on) {
  const kind = scene.userData.kind || "land";
  const P = PALETTE[kind];
  const u = scene.userData;
  if (!u.classic) {
    const sky = scene.children.find(o => o.userData.sky);
    const hemi = scene.children.find(o => o.isHemisphereLight), sun = scene.children.find(o => o.isDirectionalLight);
    u.classic = {
      sky, hemi, sun,
      skyCols: sky && ["top", "horizon", "bottom"].map(k => sky.material.uniforms[k].value.clone()),
      bg: scene.background && scene.background.clone(), fog: scene.fog && scene.fog.color.clone(),
      hemiV: hemi && [hemi.color.clone(), hemi.groundColor.clone(), hemi.intensity],
      sunV: sun && [sun.color.clone(), sun.intensity],
    };
  }
  const c = u.classic;
  if (c.sky) ["top", "horizon", "bottom"].forEach((k, i) => c.sky.material.uniforms[k].value.set(on ? P.sky[i] : c.skyCols[i]));
  if (c.bg && scene.background) scene.background.set(on ? P.bg : c.bg);
  if (c.fog && scene.fog) scene.fog.color.set(on ? P.fog : c.fog);
  if (c.hemi) { c.hemi.color.set(on ? P.hemi[0] : c.hemiV[0]); c.hemi.groundColor.set(on ? P.hemi[1] : c.hemiV[1]); c.hemi.intensity = on ? P.hemi[2] : c.hemiV[2]; }
  if (c.sun) { c.sun.color.set(on ? P.sun[0] : c.sunV[0]); c.sun.intensity = on ? P.sun[1] : c.sunV[1]; }
}

/* ---- cartoon clouds: flat white tops, a crisp blue-grey underside ---- */
function cloudTexture(seed) {
  const r = rng(seed), W = 512, H = 256;
  const c = document.createElement("canvas");
  c.width = W; c.height = H;
  const g = c.getContext("2d");
  const puffs = [];
  const n = 6 + ((r() * 4) | 0);
  for (let i = 0; i < n; i++) {
    const x = W * (0.18 + 0.64 * (i / (n - 1))) + (r() - 0.5) * 30;
    const rad = H * (0.16 + r() * 0.2) * (1 - Math.abs(i / (n - 1) - 0.5) * 0.9);
    puffs.push([x, H * 0.66 - rad * 0.55, rad]);
  }
  puffs.push([W * 0.5, H * 0.72, H * 0.1], [W * 0.3, H * 0.72, H * 0.09], [W * 0.7, H * 0.72, H * 0.09]);
  const draw = (col, dx, dy, k) => {
    g.fillStyle = col;
    g.beginPath();
    for (const [x, y, rad] of puffs) { g.moveTo(x + rad * k, y); g.arc(x + dx, y + dy, rad * k, 0, Math.PI * 2); }
    g.fill();
  };
  draw("#b9cde8", 0, 0, 1);                  // underside shadow
  draw("#ffffff", -6, -10, 0.93);            // lit top
  g.globalCompositeOperation = "destination-in";
  g.fillStyle = "#000";
  g.fillRect(0, 0, W, H * 0.8);             // flat cloud base
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
let cloudTex = null;
function clouds(count, dist, seed) {
  cloudTex ||= [1, 2, 3].map(cloudTexture);
  const r = rng(seed), g = new THREE.Group();
  for (let i = 0; i < count; i++) {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: cloudTex[i % 3], fog: false, depthWrite: false, transparent: true }));
    const a = (i / count) * Math.PI * 2 + r() * 0.4, el = 0.1 + r() * 0.22;
    s.position.set(Math.cos(a) * dist * Math.cos(el), Math.sin(el) * dist, Math.sin(a) * dist * Math.cos(el));
    const w = dist * (0.35 + r() * 0.3);
    s.scale.set(w, w / 2, 1);
    s.renderOrder = -0.5;
    g.add(s);
  }
  return g;
}

/* ---- drifting petals and leaves ---- */
function petals(count, box) {
  const geo = new THREE.PlaneGeometry(0.14, 0.09);
  const mat = new THREE.MeshBasicMaterial({ side: THREE.DoubleSide, transparent: true, opacity: 0.92, depthWrite: false });
  const inst = new THREE.InstancedMesh(geo, mat, count);
  inst.frustumCulled = false;
  const cols = [0xffc4dc, 0xffe3ef, 0xfff6fb, 0xbfeab0, 0xffd9a8].map(c => new THREE.Color(c));
  const r = rng(5);
  const st = [];
  for (let i = 0; i < count; i++) {
    inst.setColorAt(i, cols[i % cols.length]);
    st.push({ x: (r() - 0.5) * box, y: r() * box * 0.45, z: (r() - 0.5) * box, s: 0.25 + r() * 0.35, p: r() * 6, w: 0.6 + r() * 1.2 });
  }
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), one = new THREE.Vector3(1, 1, 1);
  inst.userData.update = (dt, t, cx, cy, cz) => {
    const half = box / 2, top = box * 0.45;
    st.forEach((p, i) => {
      p.y -= p.s * dt;
      p.x += Math.sin(t * 0.7 + p.p) * 0.25 * dt + 0.12 * dt;
      if (p.y < 0) { p.y = top; }
      // keep the drift centred on the viewer
      let x = ((p.x - cx) % box + box * 1.5) % box - half + cx, z = ((p.z - cz) % box + box * 1.5) % box - half + cz;
      v.set(x, cy - 1 + p.y, z);
      e.set(t * p.w + p.p, t * p.w * 0.7, Math.sin(t + p.p));
      inst.setMatrixAt(i, m.compose(v, q.setFromEuler(e), one));
    });
    inst.instanceMatrix.needsUpdate = true;
  };
  return inst;
}

export function createStyler(renderer) {
  const outline = new OutlineEffect(renderer, { defaultThickness: 0.0075, defaultColor: INK, defaultAlpha: 1, defaultKeepAlive: true });
  let on = false;
  const tmp = new THREE.Vector3();

  function dress(scene) {
    const u = scene.userData;
    if (u.dress) return u.dress;
    const d = { group: new THREE.Group() };
    if ((u.kind || "land") === "land") {
      d.clouds = clouds(u.small ? 10 : 16, u.small ? 260 : 380, u.small ? 9 : 4);
      d.petals = petals(u.small ? 70 : 140, u.small ? 14 : 30);
      d.group.add(d.clouds, d.petals);
    }
    d.group.visible = false;
    scene.add(d.group);
    u.dress = d;
    return d;
  }

  return {
    get on() { return on; },
    set(v) { on = v; },
    /* Mark a scene for re-styling (after new animals were added to it). */
    dirty(scene) { if (scene) scene.userData.styled = undefined; },
    render(scene, camera, dt, t) {
      const u = scene.userData;
      // realistic scenes want film-like tone mapping; anime and underwater stay neutral
      const tone = !on && u.tone;
      renderer.toneMapping = tone ? tone.mapping : THREE.NeutralToneMapping;
      renderer.toneMappingExposure = tone ? tone.exposure : 1.05;
      if (u.styled !== on) {
        const d = dress(scene);
        restyle(scene, on);
        mood(scene, on);
        d.group.visible = on;
        if (u.onStyle) u.onStyle(on);
        u.styled = on;
      }
      if (on) {
        const d = u.dress;
        if (d.clouds) d.clouds.position.copy(camera.position);
        if (d.petals) {
          if (u.small) d.petals.userData.update(dt, t, 0, 1, 0);          // drift over the family stage
          else {
            camera.getWorldDirection(tmp);
            d.petals.userData.update(dt, t, camera.position.x + tmp.x * 8, camera.position.y, camera.position.z + tmp.z * 8);
          }
        }
        outline.render(scene, camera);
      } else renderer.render(scene, camera);
    },
  };
}
