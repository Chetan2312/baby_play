/* Takatak Zoo — app shell: loading, walking, tapping, labels, the info panel. */
import * as THREE from "three";
import * as A from "./assets.js";
import { ANIMALS, FISH, UI, LANGS } from "./data.js";
import { PLANTS, CATS, PARTS } from "./plants.js";
import * as F from "./flora.js";
import { createJungle, route, camAtStop, natureUrls } from "./jungle.js";
import { createFamily } from "./family.js";
import { createFishWorld, fishUrls } from "./fishworld.js";
import { lerpAngle, smooth } from "./env.js";
import { createStyler } from "./anime.js";

const $ = s => document.querySelector(s);
const isMobile = matchMedia("(pointer: coarse)").matches || Math.min(innerWidth, innerHeight) < 600;
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ---------- tiny storage that never throws ---------- */
const mem = {};
const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v === null ? (k in mem ? mem[k] : d) : JSON.parse(v); } catch (e) { return k in mem ? mem[k] : d; } },
  set(k, v) { mem[k] = v; try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} },
};
const S = Object.assign({ lang: "en", sound: true, anime: false }, store.get("zoo.settings", {}));
const save = () => store.set("zoo.settings", S);
const T = key => UI[key][S.lang] || UI[key].en;
const L = obj => obj[S.lang] || obj.en;
const nm = sp => sp.name[S.lang] || sp.name.en;
const byId = id => ANIMALS.find(a => a.id === id) || FISH.find(f => f.id === id);
const plantById = id => PLANTS.find(p => p.id === id);
let lastT = 0;                  // scene clock, for the touch-me-not

/* ---------- renderer ---------- */
let renderer;
try {
  renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
} catch (e) {
  $("#status").textContent = "This browser cannot show 3D. Please try Chrome, Safari or Edge on a newer device.";
  throw e;
}
renderer.setPixelRatio(Math.min(devicePixelRatio || 1, isMobile ? 1.5 : 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.toneMapping = THREE.NeutralToneMapping;
renderer.toneMappingExposure = 1.05;
$("#stage").appendChild(renderer.domElement);
const canvas = renderer.domElement;

const jCam = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 1500);
jCam.rotation.order = "YXZ";
const styler = createStyler(renderer);
styler.set(!!S.anime);

/* ---------- audio: a few synthesised sounds + the device's voices ---------- */
let ac = null;
function audio() {
  if (!S.sound) return null;
  try { ac = ac || new (window.AudioContext || window.webkitAudioContext)(); if (ac.state === "suspended") ac.resume(); } catch (e) { return null; }
  return ac;
}
function tone(freq, dur = 0.18, type = "triangle", vol = 0.18, slide = 0) {
  const a = audio(); if (!a) return;
  const o = a.createOscillator(), g = a.createGain(), t = a.currentTime;
  o.type = type; o.frequency.setValueAtTime(freq, t);
  if (slide) o.frequency.exponentialRampToValueAtTime(freq * slide, t + dur);
  g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + 0.015); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(a.destination); o.start(t); o.stop(t + dur + 0.02);
}
const pop = () => tone(520, 0.16, "triangle", 0.16, 1.6);
const chirp = () => { const f = 1800 + Math.random() * 1400; tone(f, 0.09, "sine", 0.05, 1.3); setTimeout(() => tone(f * 1.1, 0.08, "sine", 0.04, 1.25), 110); };
const blub = () => tone(300 + Math.random() * 200, 0.12, "sine", 0.08, 2.2);

let voices = [];
const loadVoices = () => { try { voices = speechSynthesis.getVoices() || []; } catch (e) {} };
loadVoices();
if (window.speechSynthesis) speechSynthesis.onvoiceschanged = loadVoices;
function say(text, lang = S.lang) {
  if (!S.sound || !window.speechSynthesis) return;
  try {
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    const want = [LANGS[lang].voice, LANGS[lang].fallback, "en-IN", "en-US"].filter(Boolean);
    let v = null;
    for (const tag of want) { v = voices.find(x => x.lang && x.lang.toLowerCase().replace("_", "-").startsWith(tag.toLowerCase())); if (v) break; }
    if (v) u.voice = v;
    u.lang = (v && v.lang) || LANGS[lang].voice;
    u.rate = 0.9; u.pitch = 1.1;
    speechSynthesis.speak(u);
  } catch (e) {}
}

/* ---------- floating labels ---------- */
const v3 = new THREE.Vector3();
class Labels {
  constructor(root) { this.root = root; this.els = new Map(); }
  sync(items, make) {
    const keep = new Set(items.map(i => i.key));
    for (const [k, el] of this.els) if (!keep.has(k)) { el.remove(); this.els.delete(k); }
    for (const it of items) {
      let el = this.els.get(it.key);
      if (!el) { el = make(it); this.root.appendChild(el); this.els.set(it.key, el); }
    }
  }
  place(items, cam, maxDist = Infinity) {
    const w = innerWidth, h = innerHeight;
    for (const it of items) {
      const el = this.els.get(it.key);
      if (!el) continue;
      const d = cam.position.distanceTo(it.pos);
      v3.copy(it.pos).project(cam);
      const show = v3.z < 1 && d < maxDist && Math.abs(v3.x) < 1.2 && Math.abs(v3.y) < 1.2;
      if (!show) { if (el.style.visibility !== "hidden") el.style.visibility = "hidden"; continue; }
      el.style.visibility = "visible";
      el.style.opacity = maxDist === Infinity ? 1 : String(smooth(maxDist, maxDist * 0.7, d));
      el.style.transform = `translate(${((v3.x + 1) / 2) * w}px, ${((1 - v3.y) / 2) * h}px) translate(-50%, -100%)`;
    }
  }
  clear() { for (const el of this.els.values()) el.remove(); this.els.clear(); }
}
const labelsJ = new Labels($("#lj")), labelsF = new Labels($("#lf")), labelsW = new Labels($("#lw"));

/* ---------- state ---------- */
let jungle, family, fishWorld;
let mode = "loading";          // loading | jungle | family | fish
let familyFrom = "jungle";
const nav = { stop: 0, u: 0, onBoard: false, route: null, dist: 0, speed: 7, target: 0, yaw: 0, pitch: 0, userYaw: 0, userPitch: 0, pendingOpen: null, tour: false, tourAt: 0 };

/* stop keys: an animal id, "pond" (also for "duck"), or "plant:<id>" */
const stopIndex = id => jungle.stops.findIndex(s =>
  id === "duck" ? s.id === "pond" : id.startsWith("plant:") ? s.kind === "plant" && s.ids.includes(id.slice(6)) : s.id === id);
const yawTo = d => Math.atan2(-d.x, -d.z);
const pitchTo = d => Math.atan2(d.y, Math.hypot(d.x, d.z));

function samplePath(rt, d) {
  const pts = rt.pts;
  let i = 1;
  while (i < pts.length - 1 && pts[i].d < d) i++;
  const a = pts[i - 1], b = pts[i];
  const t = b.d > a.d ? Math.min(1, Math.max(0, (d - a.d) / (b.d - a.d))) : 1;
  const p = a.p.clone().lerp(b.p, t);
  const u = a.u != null && b.u != null ? a.u + ((((b.u - a.u + 0.5) % 1) + 1) % 1 - 0.5) * t : (b.u ?? a.u);
  return { p, u, onBoard: a.u == null || b.u == null };
}

function goTo(i, open = null) {
  i = ((i % jungle.stops.length) + jungle.stops.length) % jungle.stops.length;
  nav.pendingOpen = open;
  if (!nav.route && nav.stop === i) { arrive(i); return; }
  nav.route = route(jungle.stops, jCam.position, nav.u, nav.onBoard, i);
  nav.dist = 0;
  nav.target = i;
  nav.speed = Math.max(7, nav.route.len / 4.5);
  nav.userYaw *= 0.3; nav.userPitch = 0;
  markChip(i);
}

function arrive(i) {
  nav.stop = i;
  const st = jungle.stops[i];
  markChip(i);
  const open = nav.pendingOpen;
  nav.pendingOpen = null;
  nav.tourAt = performance.now();
  if (open === "pond") return openFish();
  if (open && open.startsWith("plant:")) return openPlant(open.slice(6));
  if (open) return openFamily(open);
  if (st.kind === "pond") { say(T("pond")); toast(T("tapPond")); }
  else if (st.kind === "plant") say(st.ids.map(x => nm(plantById(x))).join(", "));
  else say(nm(byId(st.id)));
}

function updateNav(dt) {
  const st = jungle.stops[nav.route ? nav.target : nav.stop];
  let pos, desiredYaw, desiredPitch, bob = 0;
  const look = st.look;
  if (nav.route) {
    const rt = nav.route;
    const ramp = Math.min(1, 0.25 + Math.min(nav.dist, rt.len - nav.dist) / 4);
    nav.dist = Math.min(rt.len, nav.dist + nav.speed * ramp * dt);
    const s = samplePath(rt, nav.dist);
    pos = s.p;
    nav.u = s.u; nav.onBoard = s.onBoard;
    const ahead = samplePath(rt, Math.min(rt.len, nav.dist + 5)).p.sub(pos);
    const toLook = look.clone().sub(pos);
    const w = smooth(12, 1, rt.len - nav.dist);
    desiredYaw = ahead.lengthSq() > 0.01 ? lerpAngle(yawTo(ahead), yawTo(toLook), w) : yawTo(toLook);
    desiredPitch = THREE.MathUtils.lerp(-0.04, pitchTo(toLook), w);
    bob = reduceMotion ? 0 : Math.sin(nav.dist * 2.3) * 0.045 * (1 - w);
    if (nav.dist >= rt.len) { nav.route = null; nav.onBoard = st.kind === "pond"; arrive(nav.target); }
  } else {
    pos = camAtStop(st);
    const toLook = look.clone().sub(pos);
    desiredYaw = yawTo(toLook);
    desiredPitch = pitchTo(toLook);
    if (nav.tour && performance.now() - nav.tourAt > 5500) goTo(nav.stop + 1);
  }
  const k = 1 - Math.exp(-dt * 3.5);
  nav.yaw = lerpAngle(nav.yaw, desiredYaw + nav.userYaw, k);
  nav.pitch = THREE.MathUtils.lerp(nav.pitch, THREE.MathUtils.clamp(desiredPitch + nav.userPitch, -0.7, 0.8), k);
  jCam.position.copy(pos).y += bob;
  jCam.rotation.set(nav.pitch, nav.yaw, 0);
}

/* ---------- jungle labels + chips ---------- */
function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

function jungleItems() {
  return jungle.labels.map(l => ({ key: "j:" + l.id, id: l.id, pos: l.pos }));
}
function makeJungleLabel(it) {
  const b = document.createElement("button");
  const plant = it.id.startsWith("p:") && plantById(it.id.slice(2));
  b.className = "tag" + (it.id === "pond" ? " pond" : "") + (plant ? " plant" + (plant.cat === "danger" ? " danger" : "") : "");
  b.dataset.id = it.id;
  b.addEventListener("click", e => {
    e.stopPropagation(); pop();
    tapTarget(it.id === "pond" ? { type: "pond" } : plant ? { type: "plant", id: plant.id } : { type: "animal", id: it.id });
  });
  return b;
}
function labelText(id) {
  if (id === "pond") return "🐟 " + T("pond");
  if (id.startsWith("p:")) { const p = plantById(id.slice(2)); return (p.cat === "danger" ? "⚠️ " : p.emoji + " ") + nm(p); }
  return byId(id).emoji + " " + nm(byId(id));
}
function renderJungleLabels() {
  labelsJ.sync(jungleItems(), makeJungleLabel);
  for (const [k, e] of labelsJ.els) e.textContent = labelText(k.slice(2));
}

/* the strip under the jungle: one tab of animal chips, one of plant chips */
let chipTab = "animals";
function buildChips() {
  const bar = $("#chips");
  bar.textContent = "";
  jungle.stops.forEach((st, i) => {
    const ids = st.kind === "pond" ? ["pond", "duck"] : st.kind === "plant" ? st.ids.map(x => "p:" + x) : [st.id];
    for (const id of ids) {
      const b = document.createElement("button");
      const plant = id.startsWith("p:") && plantById(id.slice(2));
      b.className = "chip" + (plant ? " wide" + (plant.cat === "danger" ? " danger" : "") : "");
      b.dataset.stop = i;
      b.dataset.id = id;
      b.dataset.kind = plant ? "plants" : "animals";
      if (plant) { b.append(el("span", "e", plant.emoji)); b.append(el("span", "n", "")); }
      else b.textContent = id === "pond" ? "🐟" : byId(id).emoji;
      b.addEventListener("click", () => { pop(); stopTour(); goTo(i); });
      bar.appendChild(b);
    }
  });
  titleChips();
  setTab(chipTab);
}
function setTab(tab) {
  chipTab = tab;
  $("#chips").dataset.tab = tab;
  document.querySelectorAll("#tabs button").forEach(b => b.setAttribute("aria-pressed", b.dataset.tab === tab));
  if (jungle) markChip(nav.route ? nav.target : nav.stop);
}
function titleChips() {
  for (const b of document.querySelectorAll("#chips .chip")) {
    const id = b.dataset.id;
    const t = id === "pond" ? T("pond") : id.startsWith("p:") ? nm(plantById(id.slice(2))) : nm(byId(id));
    b.title = t; b.setAttribute("aria-label", t);
    const n = b.querySelector(".n");
    if (n) n.textContent = t.replace(/ \(.*\)$/, "");
  }
  document.querySelectorAll("#tabs button").forEach(b => { b.querySelector(".t").textContent = T(b.dataset.tab + "Tab"); });
}
function markChip(i) {
  let first = null;
  for (const b of document.querySelectorAll("#chips .chip")) {
    const on = +b.dataset.stop === i;
    b.classList.toggle("on", on);
    if (on && !first && b.dataset.kind === chipTab) first = b;
  }
  if (first) first.scrollIntoView({ inline: "center", block: "nearest", behavior: reduceMotion ? "auto" : "smooth" });
}

/* ---------- tapping ---------- */
const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
function pick(x, y, cam, hits) {
  ndc.set((x / innerWidth) * 2 - 1, -(y / innerHeight) * 2 + 1);
  ray.setFromCamera(ndc, cam);
  const h = ray.intersectObjects(hits, false)[0];
  return h ? h.object.userData.hit : null;
}
function tapTarget(hit) {
  if (!hit) return;
  if (mode === "jungle") {
    stopTour();
    const key = hit.type === "pond" ? "pond" : hit.type === "plant" ? "plant:" + hit.id : hit.id;
    const i = stopIndex(key);
    const here = !nav.route && nav.stop === i;
    if (!here) return goTo(i, key);
    if (hit.type === "plant" && hit.id === "mimosa") {               // it folds first, then we look closer
      jungle.foldMimosa(lastT); say(T("mimosaSays")); setTimeout(() => openPlant("mimosa"), 1400);
      return;
    }
    if (key === "pond") openFish(); else if (hit.type === "plant") openPlant(hit.id); else openFamily(key);
  } else if (mode === "fish" && hit.type === "fish") {
    openFamily(hit.id, true);
  }
}

let down = null;
canvas.addEventListener("pointerdown", e => {
  down = { x: e.clientX, y: e.clientY, t: performance.now(), lx: e.clientX, ly: e.clientY, id: e.pointerId };
  if (mode === "jungle") canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener("pointermove", e => {
  if (!down || e.pointerId !== down.id || mode !== "jungle") return;
  const dx = e.clientX - down.lx, dy = e.clientY - down.ly;
  down.lx = e.clientX; down.ly = e.clientY;
  nav.userYaw += dx * 0.0045;
  nav.userPitch = THREE.MathUtils.clamp(nav.userPitch + dy * 0.0035, -0.6, 0.6);
});
canvas.addEventListener("pointerup", e => {
  if (!down || e.pointerId !== down.id) return;
  const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y), quick = performance.now() - down.t < 600;
  down = null;
  if (moved > 10 || !quick) return;
  if (mode === "jungle") { const h = pick(e.clientX, e.clientY, jCam, jungle.hits); if (h) { pop(); tapTarget(h); } }
  else if (mode === "fish") { const h = pick(e.clientX, e.clientY, fishWorld.camera, fishWorld.hits); if (h) { pop(); tapTarget(h); } else blub(); }
  else if (mode === "family" && current && current.plant && current.plant.id === "mimosa") { F.fold(family.subject, lastT); say(T("mimosaSays")); }
});
canvas.addEventListener("pointercancel", () => { down = null; });

addEventListener("keydown", e => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (mode === "jungle") {
    if (e.key === "ArrowRight") { stopTour(); goTo((nav.route ? nav.target : nav.stop) + 1); }
    else if (e.key === "ArrowLeft") { stopTour(); goTo((nav.route ? nav.target : nav.stop) - 1); }
    else if (e.key === "Enter" || e.key === " ") {
      const st = jungle.stops[nav.stop];
      if (!nav.route) st.kind === "pond" ? openFish() : st.kind === "plant" ? openPlant(st.ids[0]) : openFamily(st.id);
    } else return;
    e.preventDefault();
  } else if (e.key === "Escape" || e.key === "Backspace") {
    e.preventDefault();
    mode === "family" ? closeFamily() : closeFish();
  }
});

/* ---------- fades between worlds ---------- */
const fade = $("#fade");
const wait = ms => new Promise(r => setTimeout(r, ms));
/* classic: a white blink. anime: a wave-pattern curtain sweeps across */
async function fadeOut() {
  fade.classList.toggle("wave", !!S.anime && !reduceMotion);
  fade.classList.remove("out", "reset");
  void fade.offsetWidth;
  fade.classList.add("on");
  await wait(reduceMotion ? 0 : S.anime ? 420 : 260);
}
function fadeIn() {
  if (!fade.classList.contains("wave")) { fade.classList.remove("on"); return; }
  fade.classList.add("out");
  fade.classList.remove("on");
  setTimeout(() => { fade.classList.add("reset"); fade.classList.remove("out"); }, 480);
}

/* ---------- family view (animals, fish) and plant view share one stage ---------- */
let current = null;           // { sp, isFish } or { plant }
function stageView() {
  const narrow = matchMedia("(max-width:760px), (orientation:portrait)").matches;
  const aspect = innerWidth / innerHeight;
  return narrow ? { fw: 1, fh: 0.5, aspect } : { fw: (innerWidth - Math.min(400, innerWidth * 0.4)) / innerWidth, fh: 1, aspect };
}
function enterStage(key) {
  styler.dirty(family.scene);
  mode = "family";
  document.body.dataset.mode = "family";
  family.controls.enabled = true;
  fillPanel();
  $("#panel").hidden = false;
  $("#panel").scrollTop = 0;
  layoutOffset();
  labelsF.sync(family.labels.map((l, i) => ({ key: "f:" + i + ":" + key })), () => el("div", "tag role"));
  familyLabelText();
  fadeIn();
}
async function openFamily(id, isFish = false) {
  const sp = byId(id);
  if (!sp) return;
  stopTour();
  await fadeOut();
  if (mode !== "family") familyFrom = mode === "fish" ? "fish" : "jungle";
  if (familyFrom === "fish") fishWorld.controls.enabled = false;
  $("#spinner").hidden = false;
  await family.show(sp, isFish, stageView());
  $("#spinner").hidden = true;
  current = { sp, isFish };
  enterStage(sp.id);
  toast(T("spin"));
  say(nm(sp) + (S.lang === "en" ? " family" : " " + T("family")));
}
async function openPlant(id) {
  const pl = plantById(id);
  if (!pl) return;
  stopTour();
  await fadeOut();
  if (mode !== "family") familyFrom = mode === "fish" ? "fish" : "jungle";
  $("#spinner").hidden = false;
  await family.showPlant(pl, stageView());
  $("#spinner").hidden = true;
  current = { plant: pl };
  enterStage(pl.id);
  toast(pl.id === "mimosa" ? T("mimosaTap") : T("spinPlant"));
  say(nm(pl));
}
const currentKey = () => current && (current.plant ? current.plant.id : current.sp.id);
const PART_ICON = { leaf: "🍃 ", fruit: "🍎 ", flower: "🌸 ", pod: "🫛 ", seeds: "🌰 ", berries: "🫐 ", roots: "〰️ " };
function familyLabelText() {
  if (!current) return;
  const key = currentKey();
  if (current.plant) {
    family.labels.forEach((l, i) => {
      const e = labelsF.els.get("f:" + i + ":" + key);
      if (!e) return;
      e.textContent = l.role === "name" ? current.plant.emoji + " " + nm(current.plant) : PART_ICON[l.role] + L(PARTS[l.role]);
      e.dataset.role = l.role === "name" ? "name" : "part";
    });
    return;
  }
  const { sp } = current;
  const roles = sp.roles || { m: "Male", f: "Female" };
  family.labels.forEach((l, i) => {
    const e = labelsF.els.get("f:" + i + ":" + key);
    if (!e) return;
    let txt;
    if (l.role === "father") txt = "♂ " + T("father") + (S.lang === "en" && roles.m !== "Male" ? " · " + roles.m : "");
    else if (l.role === "mother") txt = "♀ " + T("mother") + (S.lang === "en" && roles.f !== "Female" ? " · " + roles.f : "");
    else if (l.role === "baby") txt = S.lang === "en" ? (l.count > 1 ? `${roles.bs} × ${l.count}` : roles.b) : (l.count > 1 ? `${T("babies")} × ${l.count}` : T("baby"));
    else txt = "🥚 " + T("eggs");
    e.textContent = txt;
    e.dataset.role = l.role;
  });
}
async function closeFamily() {
  await fadeOut();
  family.controls.enabled = false;
  $("#panel").hidden = true;
  labelsF.clear();
  current = null;
  family.camera.clearViewOffset();
  if (familyFrom === "fish") { mode = "fish"; document.body.dataset.mode = "fish"; fishWorld.controls.enabled = true; }
  else { mode = "jungle"; document.body.dataset.mode = "jungle"; }
  fadeIn();
}

function panelHead(P, item, sayText) {
  const head = el("header", "ph");
  head.append(el("span", "big-emoji", item.emoji));
  const names = el("div", "names");
  names.append(el("h2", null, nm(item)));
  names.append(el("p", "alt", ["en", "mr", "hi"].filter(l => l !== S.lang).map(l => item.name[l]).join(" · ")));
  head.append(names);
  const sayBtn = el("button", "say", "🔊");
  sayBtn.setAttribute("aria-label", "Say it");
  sayBtn.addEventListener("click", () => say(S.lang === "en" ? sayText : nm(item)));
  head.append(sayBtn);
  P.append(head);
}
function panelPhoto(P, item) {
  if (!item.photo) return;
  const img = new Image();
  img.src = item.photo; img.alt = item.name.en; img.className = "photo"; img.decoding = "async";
  img.onerror = () => img.remove();
  P.append(img);
}
function fillPlantPanel() {
  const pl = current.plant;
  const P = $("#panelBody");
  P.textContent = "";
  panelHead(P, pl, `${pl.name.en}. ${pl.info.fact}`);
  const tags = el("div", "ptags");
  tags.append(el("span", "cat c-" + pl.cat, CATS[pl.cat].emoji + " " + L(CATS[pl.cat])));
  if (pl.eat === "yes") tags.append(el("span", "edible yes", "✅ " + T("eatYes")));
  if (pl.eat === "no") tags.append(el("span", "edible no", "⚠️ " + T("eatNo")));
  P.append(tags);
  panelPhoto(P, pl);
  const dl = el("dl");
  const row = (k, v) => { dl.append(el("dt", null, k)); dl.append(el("dd", null, v)); };
  const I = pl.info;
  row("How to spot it", I.spot);
  row("When", I.season);
  row("Who eats it", I.eaters);
  row("Uses", I.uses);
  row("Wow!", I.fact);
  P.append(dl);
  P.append(el("p", "note", "Facts are in English; names in all three languages. Never taste a wild plant unless a grown-up who knows it says it is safe."));
}
function fillPanel() {
  if (current.plant) return fillPlantPanel();
  const { sp, isFish } = current;
  const P = $("#panelBody");
  P.textContent = "";
  panelHead(P, sp, `${sp.name.en}. ${sp.info.fact}`);
  if (isFish) P.append(el("p", "edible " + (sp.edible ? "yes" : "no"), sp.edible ? "🍽️ " + T("edible") : "🚫 " + L(sp.why)));
  panelPhoto(P, sp);
  const fam = el("div", "fam");
  const roles = sp.roles || { m: "Male", f: "Female" };
  const card = (sym, a, b) => { const c = el("div", "fc"); c.append(el("b", null, sym + " " + a)); if (b) c.append(el("small", null, b)); return c; };
  fam.append(card("♂", T("father"), roles.m), card("♀", T("mother"), roles.f));
  if (!isFish) fam.append(card("🐾", sp.n > 1 ? T("babies") : T("baby"), `${roles.bs || roles.b} × ${sp.n}`));
  if (isFish || sp.eggs) fam.append(card("🥚", T("eggs")));
  P.append(fam);
  const dl = el("dl");
  const row = (k, v) => { dl.append(el("dt", null, k)); const d = el("dd"); if (Array.isArray(v)) { d.className = "kinds"; v.forEach(x => d.append(el("span", null, x))); } else d.textContent = v; dl.append(d); };
  const I = sp.info;
  row("Kinds", I.kinds);
  if (isFish) row("Eggs", I.eggs); else row("Babies", I.babies);
  row("Home", I.home);
  row("Food", I.food);
  row("Lives for", I.life);
  row("Wow!", I.fact);
  P.append(dl);
  P.append(el("p", "note", "Facts are in English. Names in all three languages."));
}

/* When the panel covers part of the screen, slide the 3D view out from under it. */
function layoutOffset() {
  const cam = family.camera;
  const panel = $("#panel");
  cam.aspect = innerWidth / innerHeight;
  if (mode !== "family" || panel.hidden) { cam.clearViewOffset(); cam.updateProjectionMatrix(); return; }
  const r = panel.getBoundingClientRect();
  if (r.width < innerWidth * 0.9) cam.setViewOffset(innerWidth, innerHeight, (innerWidth - r.left) / 2, 0, innerWidth, innerHeight);
  else cam.setViewOffset(innerWidth, innerHeight, 0, (innerHeight - r.top) / 2 - 20, innerWidth, innerHeight);
  cam.updateProjectionMatrix();
}

/* ---------- fish world ---------- */
async function openFish() {
  stopTour();
  await fadeOut();
  $("#spinner").hidden = false;
  await fishWorld.build();
  styler.dirty(fishWorld.scene);
  $("#spinner").hidden = true;
  mode = "fish";
  document.body.dataset.mode = "fish";
  fishWorld.controls.enabled = true;
  fishFrame();
  labelsW.sync([...fishWorld.zoneLabels.map(z => ({ key: "z:" + z.zone, zone: z.zone })), ...fishWorld.labels.map(l => ({ key: "w:" + l.id, id: l.id }))], it => {
    const b = el(it.zone ? "div" : "button", it.zone ? "zone " + it.zone : "tag fish");
    if (it.id) b.addEventListener("click", e => { e.stopPropagation(); pop(); openFamily(it.id, true); });
    return b;
  });
  fishLabelText();
  fadeIn();
  say(T("pond"));
}
function fishLabelText() {
  for (const [k, e] of labelsW.els) {
    if (k.startsWith("z:")) e.textContent = k === "z:edible" ? "🍽️ " + T("edible") : "🚫 " + T("inedible");
    else e.textContent = nm(byId(k.slice(2)));
  }
}
function fishItems() {
  return [...fishWorld.zoneLabels.map(z => ({ key: "z:" + z.zone, pos: z.pos })), ...fishWorld.labels.map(l => ({ key: "w:" + l.id, pos: l.pos }))];
}
function fishFrame() {
  const c = fishWorld.camera;
  c.aspect = innerWidth / innerHeight;
  c.updateProjectionMatrix();
  const tall = c.aspect < 0.95;
  fishWorld.layout(tall);
  const d = tall ? 24 : c.aspect < 1.3 ? 26 : 20;
  fishWorld.controls.maxDistance = d * 1.3;
  fishWorld.controls.target.set(0, tall ? 7 : 3.2, 0);
  c.position.set(0, tall ? 7.5 : 5.5, d);
  fishWorld.controls.update();
}
async function closeFish() {
  await fadeOut();
  fishWorld.controls.enabled = false;
  labelsW.clear();
  mode = "jungle";
  document.body.dataset.mode = "jungle";
  fadeIn();
}

/* ---------- chrome ---------- */
let toastTimer = 0;
function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("on"), 4200);
}
function stopTour() { nav.tour = false; $("#tour").classList.remove("on"); $("#tour").textContent = "🚶"; }

function applyLang() {
  document.documentElement.lang = S.lang === "en" ? "en" : S.lang;
  document.querySelectorAll("[data-t]").forEach(e => { e.textContent = T(e.dataset.t); });
  document.querySelectorAll("[data-lang]").forEach(b => b.setAttribute("aria-pressed", b.dataset.lang === S.lang));
  if (jungle) { renderJungleLabels(); titleChips(); }
  if (current) { fillPanel(); familyLabelText(); }
  if (fishWorld) fishLabelText();
}
document.querySelectorAll("[data-lang]").forEach(b => b.addEventListener("click", () => {
  S.lang = b.dataset.lang; save(); applyLang(); pop();
  if (mode === "jungle" && jungle) { const st = jungle.stops[nav.stop]; say(st.kind === "pond" ? T("pond") : st.kind === "plant" ? nm(plantById(st.ids[0])) : nm(byId(st.id))); }
  else if (current) say(nm(current.plant || current.sp));
}));
function styleUI() {
  $("#styleBtn").setAttribute("aria-pressed", !!S.anime);
  document.body.classList.toggle("anime", !!S.anime);
}
$("#styleBtn").addEventListener("click", async () => {
  pop();
  await fadeOut();
  S.anime = !S.anime; save();
  styler.set(S.anime);
  styleUI();
  fadeIn();
  toast(S.anime ? "✨ " + T("anime") : T("classic"));
});
function soundUI() { $("#sound").textContent = S.sound ? "🔊" : "🔇"; $("#sound").setAttribute("aria-pressed", S.sound); }
$("#sound").addEventListener("click", () => { S.sound = !S.sound; save(); soundUI(); if (!S.sound) try { speechSynthesis.cancel(); } catch (e) {} else pop(); });
$("#fs").addEventListener("click", async () => {
  try { document.fullscreenElement ? await document.exitFullscreen() : await document.documentElement.requestFullscreen({ navigationUI: "hide" }); } catch (e) {}
});
document.querySelectorAll("#tabs button").forEach(b => b.addEventListener("click", () => { pop(); setTab(b.dataset.tab); }));
$("#prev").addEventListener("click", () => { pop(); stopTour(); goTo((nav.route ? nav.target : nav.stop) - 1); });
$("#next").addEventListener("click", () => { pop(); stopTour(); goTo((nav.route ? nav.target : nav.stop) + 1); });
$("#tour").addEventListener("click", () => {
  pop();
  nav.tour = !nav.tour;
  $("#tour").classList.toggle("on", nav.tour);
  $("#tour").textContent = nav.tour ? "⏸" : "🚶";
  if (nav.tour && !nav.route) goTo(nav.stop + 1);
});
$("#closePanel").addEventListener("click", () => { pop(); closeFamily(); });
$("#backFish").addEventListener("click", () => { pop(); closeFish(); });
$("#creditsBtn").addEventListener("click", () => $("#credits").showModal());
$("#creditsClose").addEventListener("click", () => $("#credits").close());
addEventListener("contextmenu", e => e.preventDefault());
document.addEventListener("gesturestart", e => e.preventDefault());

addEventListener("resize", () => {
  renderer.setSize(innerWidth, innerHeight);
  jCam.aspect = innerWidth / innerHeight;
  jCam.updateProjectionMatrix();
  if (family) layoutOffset();
  if (fishWorld && mode === "fish") fishFrame();
});

/* ---------- credits ---------- */
fetch("models/credits.json").then(r => r.json()).then(list => {
  const ul = $("#creditList");
  for (const c of list) {
    const li = el("li");
    const a = el("a", null, c.title);
    a.href = c.source; a.target = "_blank"; a.rel = "noopener";
    li.append(a, document.createTextNode(` by ${c.creator} — ${c.licence}`));
    ul.append(li);
  }
}).catch(() => {});

/* ---------- loop ---------- */
const timer = new THREE.Timer();
let nextChirp = 4;
function frame(now) {
  timer.update(now);
  const dt = Math.min(timer.getDelta(), 0.05), t = timer.getElapsed();
  lastT = t;
  if (mode === "jungle" || mode === "loading") {
    updateNav(dt);
    jungle.update(dt, t, jCam);
    styler.render(jungle.scene, jCam, dt, t);
    labelsJ.place(jungleItems(), jCam, 48);
    if (mode === "jungle" && t > nextChirp) { chirp(); nextChirp = t + 3 + Math.random() * 6; }
  } else if (mode === "family") {
    family.update(dt, t);
    styler.render(family.scene, family.camera, dt, t);
    const key = currentKey();
    labelsF.place(family.labels.map((l, i) => ({ key: "f:" + i + ":" + key, pos: l.pos })), family.camera);
  } else if (mode === "fish") {
    fishWorld.update(dt, t);
    styler.render(fishWorld.scene, fishWorld.camera, dt, t);
    labelsW.place(fishItems(), fishWorld.camera);
  }
}

/* ---------- boot ---------- */
async function boot() {
  applyLang();
  styleUI();
  soundUI();
  $("#status").textContent = T("loading");
  const bar = $("#bar");
  const animalUrls = [...new Set(ANIMALS.flatMap(a => Object.values(a.models)).filter(k => k !== "tadpole"))].map(k => A.url("animals", k));
  const urls = [...animalUrls, ...natureUrls, A.url("fish", "koi"), A.url("fish", "goldfish")];
  await A.loadAll(urls, (d, n) => { bar.style.width = (d / n) * 80 + "%"; });
  jungle = await createJungle(isMobile, renderer);
  bar.style.width = "92%";
  await F.photosReady();
  family = createFamily(renderer, isMobile);
  fishWorld = createFishWorld(renderer, isMobile);
  const st0 = jungle.stops[0];
  nav.u = st0.u;
  jCam.position.copy(camAtStop(st0));
  const d = st0.look.clone().sub(jCam.position);
  nav.yaw = yawTo(d); nav.pitch = pitchTo(d);
  buildChips();
  renderJungleLabels();
  markChip(0);
  bar.style.width = "100%";
  try { renderer.compile(jungle.scene, jCam); } catch (e) {}
  renderer.setAnimationLoop(frame);
  document.body.classList.add("ready");
  $("#enter").disabled = false;
  $("#status").textContent = "";
  // fish load in the background once the jungle is up
  setTimeout(() => A.loadAll(fishUrls), 1500);
}

$("#enter").addEventListener("click", () => {
  audio();
  $("#curtain").remove();
  mode = "jungle";
  document.body.dataset.mode = "jungle";
  toast(T("hint"));
  arrive(nav.stop);
  if (isMobile) try { document.documentElement.requestFullscreen({ navigationUI: "hide" }).catch(() => {}); } catch (e) {}
});

boot().catch(err => {
  console.error(err);
  $("#status").textContent = "Something went wrong while loading. Please refresh the page.";
});

if ("serviceWorker" in navigator && location.protocol.startsWith("http") && location.hostname !== "localhost" && location.hostname !== "127.0.0.1") {
  addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));
}

// handy for testing from the console / screenshots
window.zoo = {
  goTo: i => goTo(i),
  info: () => ({ ...renderer.info.render, geometries: renderer.info.memory.geometries }),
  jump(i) { const st = jungle.stops[i]; nav.route = null; nav.stop = i; nav.u = st.u; nav.onBoard = st.kind === "pond"; const d = st.look.clone().sub(camAtStop(st)); nav.yaw = yawTo(d); nav.pitch = pitchTo(d); markChip(i); },
  openFamily, openFish, openPlant, closeFamily, closeFish,
  get stops() { return jungle && jungle.stops; }, get mode() { return mode; },
  budget() {
    const rows = {};
    jungle.scene.traverse(o => {
      if (!o.isMesh || !o.visible) return;
      const g = o.geometry, tri = (g.index ? g.index.count : g.attributes.position.count) / 3;
      const n = o.isInstancedMesh ? o.count : 1;
      const k = (o.isInstancedMesh ? "inst:" : "mesh:") + (o.parent && o.parent.name || o.name || "") + ":" + Math.round(tri) + (o.isInstancedMesh ? "×" + o.count : "");
      rows[k] = (rows[k] || 0) + tri * n;
    });
    return Object.entries(rows).sort((a, b) => b[1] - a[1]).slice(0, 25).map(([k, v]) => k + " = " + Math.round(v / 1000) + "k");
  },
};
