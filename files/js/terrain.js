/* Realistic ground: four photo-scanned surfaces (CC0, ambientCG) blended per
   vertex — grass, forest floor, leaf litter, pond mud — plus a trodden dirt
   trail and tufts of grass that move in the wind. */
import * as THREE from "three";
import { photo, windMaterial, grassTexture } from "./flora.js";

/* splat weights ride on a vec4 attribute: x grass, y forest floor, z leaf litter, w mud */
export function groundMaterial() {
  const T = n => photo(n + "_color"), N = n => photo(n + "_normal", false);
  const mat = new THREE.MeshStandardMaterial({
    map: T("grass004"), normalMap: N("grass004"), normalScale: new THREE.Vector2(0.9, 0.9),
    roughness: 0.97, metalness: 0, vertexColors: true, envMapIntensity: 0.6,
  });
  const extra = { tForest: T("ground037"), tLitter: T("ground020"), tMud: T("ground024"), nForest: N("ground037"), nLitter: N("ground020"), nMud: N("ground024") };
  mat.onBeforeCompile = sh => {
    for (const [k, v] of Object.entries(extra)) sh.uniforms[k] = { value: v };
    sh.vertexShader = "attribute vec4 splat;\nvarying vec4 vSplat;\n" + sh.vertexShader.replace("#include <begin_vertex>", "#include <begin_vertex>\nvSplat = splat;");
    sh.fragmentShader = "uniform sampler2D tForest, tLitter, tMud, nForest, nLitter, nMud;\nvarying vec4 vSplat;\n" + sh.fragmentShader
      .replace("#include <map_fragment>", `
        vec2 uvA = vMapUv, uvB = vMapUv * 0.71 + vec2(0.37, 0.11), uvC = vMapUv * 1.27;
        vec3 cG = texture2D(map, uvA).rgb, cF = texture2D(tForest, uvB).rgb, cL = texture2D(tLitter, uvC).rgb, cM = texture2D(tMud, uvB).rgb;
        // height-aware blend: where two surfaces meet, the brighter (higher) texel wins,
        // so grass pokes through litter instead of fading into mush
        vec4 hw = vSplat * (vec4(dot(cG, vec3(0.333)), dot(cF, vec3(0.333)), dot(cL, vec3(0.333)), dot(cM, vec3(0.333))) + 0.35);
        hw = pow(max(hw, vec4(1e-4)), vec4(3.0));
        hw /= max(dot(hw, vec4(1.0)), 1e-4);
        diffuseColor.rgb *= cG * hw.x + cF * hw.y + cL * hw.z + cM * hw.w;`)
      .replace("#include <normal_fragment_maps>", `
        vec3 mapN = (texture2D(normalMap, uvA).xyz * hw.x + texture2D(nForest, uvB).xyz * hw.y + texture2D(nLitter, uvC).xyz * hw.z + texture2D(nMud, uvB).xyz * hw.w) * 2.0 - 1.0;
        mapN.xy *= normalScale;
        normal = normalize( tbn * mapN );`);
  };
  mat.customProgramCacheKey = () => "splat-ground";
  return mat;
}

export function trailMaterial() {
  return new THREE.MeshStandardMaterial({
    map: photo("ground020_color"), normalMap: photo("ground020_normal", false), normalScale: new THREE.Vector2(1.1, 1.1),
    roughness: 0.98, metalness: 0, vertexColors: true, transparent: true, depthWrite: false,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, envMapIntensity: 0.5,
  });
}

/* one tuft: three crossed cards of painted blades, tops sway */
export function grassTuft() {
  const g = new THREE.BufferGeometry();
  const p = [], n = [], uv = [], sw = [], c = [], idx = [];
  for (let k = 0; k < 3; k++) {
    const a = (k / 3) * Math.PI, dx = Math.cos(a) * 0.5, dz = Math.sin(a) * 0.5, b = p.length / 3;
    p.push(-dx, 0, -dz, dx, 0, dz, dx, 1, dz, -dx, 1, -dz);
    for (let i = 0; i < 4; i++) n.push(0, 1, 0);
    uv.push(0, 0, 1, 0, 1, 1, 0, 1);
    sw.push(0, 0, 0.06, 0.06);
    for (let i = 0; i < 4; i++) c.push(1, 1, 1);
    idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }
  g.setAttribute("position", new THREE.Float32BufferAttribute(p, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(n, 3));
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute("aSway", new THREE.Float32BufferAttribute(sw, 1));
  g.setAttribute("color", new THREE.Float32BufferAttribute(c, 3));
  g.setIndex(idx);
  const m = new THREE.Mesh(g, windMaterial("grass", grassTexture()));
  const grp = new THREE.Group();
  grp.add(m);
  return grp;
}
