/* Shared scenery helpers: sky, lights, generated textures, seeded random. */
import * as THREE from "three";

export function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
export const lerpAngle = (a, b, t) => a + ((((b - a + Math.PI) % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI) - Math.PI) * t;

/* Gradient sky that follows the camera. */
export function skyDome(top, horizon, bottom = horizon) {
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { top: { value: new THREE.Color(top) }, horizon: { value: new THREE.Color(horizon) }, bottom: { value: new THREE.Color(bottom) } },
    vertexShader: `varying vec3 vDir;
      void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `uniform vec3 top; uniform vec3 horizon; uniform vec3 bottom; varying vec3 vDir;
      void main(){
        float h = vDir.y;
        vec3 c = h > 0.0 ? mix(horizon, top, pow(h, 0.55)) : mix(horizon, bottom, pow(-h, 0.4));
        gl_FragColor = vec4(c, 1.0);
        #include <colorspace_fragment>
      }`,
  });
  const m = new THREE.Mesh(new THREE.SphereGeometry(500, 32, 16), mat);
  m.renderOrder = -1;
  m.frustumCulled = false;
  m.onBeforeRender = (r, s, cam) => m.position.copy(cam.position);
  return m;
}

export function addLights(scene, { sky = 0xcfeaff, ground = 0x4a6b33, hemi = 1.7, sun = 0xfff1d6, sunI = 2.4, shadow = true, mapSize = 2048, span = 26 } = {}) {
  scene.add(new THREE.HemisphereLight(sky, ground, hemi));
  const dir = new THREE.DirectionalLight(sun, sunI);
  dir.position.set(30, 50, 20);
  if (shadow) {
    dir.castShadow = true;
    dir.shadow.mapSize.set(mapSize, mapSize);
    const c = dir.shadow.camera;
    c.left = c.bottom = -span; c.right = c.top = span; c.near = 1; c.far = 160;
    dir.shadow.bias = -0.0006;
    dir.shadow.normalBias = 0.04;
  }
  scene.add(dir, dir.target);
  return dir;
}

function canvas(w, h, draw) {
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  draw(c.getContext("2d"), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

/* Soft round spot: blob shadows, the family stage, light shafts. */
export function radial(inner = "rgba(0,0,0,1)", outer = "rgba(0,0,0,0)", size = 128) {
  return canvas(size, size, (g, w) => {
    const gr = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2);
    gr.addColorStop(0, inner); gr.addColorStop(1, outer);
    g.fillStyle = gr; g.fillRect(0, 0, w, w);
  });
}

/* Grassy disc with a speckle of darker blades, fading out at the rim. */
export function stageTexture(base, speck, edge) {
  return canvas(512, 512, (g, w) => {
    const r = rng(7);
    g.fillStyle = base; g.fillRect(0, 0, w, w);
    for (let i = 0; i < 3500; i++) {
      g.fillStyle = r() < 0.5 ? speck : edge;
      g.globalAlpha = 0.25 + r() * 0.35;
      g.fillRect(r() * w, r() * w, 2 + r() * 3, 2 + r() * 5);
    }
    g.globalAlpha = 1;
    const gr = g.createRadialGradient(w / 2, w / 2, w * 0.38, w / 2, w / 2, w / 2);
    gr.addColorStop(0, "rgba(0,0,0,0)"); gr.addColorStop(1, edge);
    g.fillStyle = gr; g.fillRect(0, 0, w, w);
  });
}

/* Tileable ripple normal map for water. */
export function waterNormals(size = 128) {
  const c = document.createElement("canvas");
  c.width = c.height = size;
  const g = c.getContext("2d");
  const img = g.createImageData(size, size);
  const f = (x, y) => {
    const k = 2 * Math.PI / size;
    return Math.sin(x * k * 3 + Math.sin(y * k * 2) * 1.5) * 0.5 + Math.sin(y * k * 4 + x * k) * 0.35 + Math.sin((x + y) * k * 5) * 0.2;
  };
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const dx = f(x + 1, y) - f(x - 1, y), dy = f(x, y + 1) - f(x, y - 1);
    const n = new THREE.Vector3(-dx * 2, -dy * 2, 1).normalize();
    const i = (y * size + x) * 4;
    img.data[i] = (n.x * 0.5 + 0.5) * 255; img.data[i + 1] = (n.y * 0.5 + 0.5) * 255; img.data[i + 2] = (n.z * 0.5 + 0.5) * 255; img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}
