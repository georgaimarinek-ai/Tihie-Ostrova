// Туманные острова — играбельный набросок (three.js). Поморский Север: белая ночь, туман, карбас, деревянные маяки.
// v0.2: высадка на берег, ходьба, факел, путевые фонари, музыка слоями.
import * as THREE from 'three';

// ------------------------------------------------------------------ helpers
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const dist2 = (ax, az, bx, bz) => Math.hypot(ax - bx, az - bz);
function mulberry32(a) { return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function makePerlin(seed) {
  const rnd = mulberry32(seed), p = new Uint8Array(512), perm = [...Array(256).keys()];
  for (let i = 255; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [perm[i], perm[j]] = [perm[j], perm[i]]; }
  for (let i = 0; i < 512; i++) p[i] = perm[i & 255];
  const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
  const grad = (h, x, y) => { switch (h & 7) { case 0: return x + y; case 1: return -x + y; case 2: return x - y; case 3: return -x - y; case 4: return x; case 5: return -x; case 6: return y; default: return -y; } };
  return (x, y) => {
    const X = Math.floor(x) & 255, Y = Math.floor(y) & 255; x -= Math.floor(x); y -= Math.floor(y);
    const u = fade(x), v = fade(y), a = p[X] + Y, b = p[X + 1] + Y;
    return lerp(lerp(grad(p[a], x, y), grad(p[b], x - 1, y), u), lerp(grad(p[a + 1], x, y - 1), grad(p[b + 1], x - 1, y - 1), u), v);
  };
}
function fbm(noise, x, y, oct = 4) { let s = 0, a = 0.5, f = 1; for (let i = 0; i < oct; i++) { s += a * noise(x * f, y * f); f *= 2.03; a *= 0.5; } return s; }
// waves: the same function drives the water shader and the boat (the Godot pack keeps this rule: src/core/waves.gd)
const WAVE_GLSL = `float wave(vec2 p, float t){ return 0.34*sin(0.12*p.x+0.9*t)+0.24*sin(0.17*p.y+1.3*t+1.7)+0.12*sin(0.31*(p.x+p.y)+1.9*t)+0.06*sin(0.53*(p.x-p.y)+2.7*t); }`;
const wave = (x, z, t) => 0.34 * Math.sin(0.12 * x + 0.9 * t) + 0.24 * Math.sin(0.17 * z + 1.3 * t + 1.7) + 0.12 * Math.sin(0.31 * (x + z) + 1.9 * t) + 0.06 * Math.sin(0.53 * (x - z) + 2.7 * t);

const LANG = (navigator.language || 'ru').toLowerCase().startsWith('ru') ? 'ru' : 'en';
const TXT = {
  ru: {
    title: 'Туманные острова', sub: 'Играбельный набросок · Поморский Север', start: 'Отчалить',
    lede: 'Белая ночь над Белым морем. Карбас у причала, в избе горит печь, а дальше — туман до самого горизонта. Доплыви до острова, сойди на берег, добудь огонь и зажги маяк: туман отступит.',
    phones: 'Лучше в наушниках', modes: ['<b>Тихий</b> — без врагов, только море и стройка', '<b>Сказание</b> — звери, шторма, смерть без потерь', '<b>Сага</b> — туманные твари и стражи маяков'], modesT: 'Опасность выбирает игрок',
    ctrlDesk: 'W/S — вперёд и назад · A/D — поворот · мышь с зажатой кнопкой — осмотреться · Shift — бег · E — действие',
    ctrlTouch: 'Джойстик слева — движение · пальцем справа — обзор · кнопка действия появляется сама',
    gSailA: 'Плыви на огонёк маяка — он мерцает в тумане.',
    gLandA: 'Берег рядом. Сойди на него.',
    gGather: (b, r) => `На острове туман гуще, без огня тропы не видно. Собери хворост (${b}/3) и живицу (${r}/1) — они мерцают.`,
    gCraft: 'Всё есть. Сделай факел.',
    gClimbA: 'Факел горит и раздвигает туман. Донеси огонь по тропе на вершину и зажги маяк.',
    gBackToA: 'Маяк на этом острове. Вернись к лодке и плыви на огонёк.',
    gReturnA: 'Туман отступил! Вернись к карбасу: вдали виден второй маяк.',
    gSailB: 'Плыви ко второму маяку.',
    gLandB: 'Сойди на берег.',
    gLanterns: (n) => `Тропу к маяку отмечают путевые фонари. Зажги их факелом (${n}/3).`,
    gClimbB: 'Тропа освещена. Поднимись и зажги маяк.',
    gNoFire: 'Без огня здесь ничего не зажечь. Сначала зажги маяк на ближнем острове.',
    gFree: 'Небо ответило сиянием. Это конец наброска — гуляй и плавай где хочешь.',
    aLand: 'Сойти на берег', aBoard: 'Сесть в лодку', aBranch: 'Взять хворост', aResin: 'Взять живицу', aTorch: 'Сделать факел', aLantern: 'Зажечь фонарь', aBeacon: 'Зажечь маяк',
    tBeacon: 'До маяка', tBranch: 'До хвороста', tResin: 'До живицы', tBoat: 'До лодки', tLantern: 'До фонаря', m: 'м',
    sound: 'Звук', quality: 'Графика', hi: 'высокая', lo: 'лёгкая', on: 'вкл', off: 'выкл',
    endT: 'Так будет ощущаться игра', endP: 'Туман, свет и дом. Каждый зажжённый маяк раздвигает мир и добавляет новый голос в музыку моря. Дальше — пакет для разработки на Godot.', cont: 'Гулять дальше',
  },
  en: {
    title: 'Fog Isles', sub: 'Playable sketch · the Russian North', start: 'Cast off',
    lede: 'A white night over the White Sea. A karbas at the pier, a stove burning in the izba, and fog all the way to the horizon. Sail to the island, go ashore, make fire and light the beacon: the fog will recede.',
    phones: 'Best with headphones', modes: ['<b>Quiet</b> — no enemies, just the sea and building', '<b>Tale</b> — animals, storms, death without loss', '<b>Saga</b> — fog creatures and beacon guardians'], modesT: 'The player picks the danger',
    ctrlDesk: 'W/S — forward and back · A/D — turn · drag the mouse — look · Shift — run · E — action',
    ctrlTouch: 'Left joystick — move · drag on the right — look · the action button appears by itself',
    gSailA: 'Sail towards the beacon light flickering in the fog.',
    gLandA: 'The shore is close. Go ashore.',
    gGather: (b, r) => `The fog is thicker on the island; without fire you cannot see the path. Gather sticks (${b}/3) and resin (${r}/1) — they glimmer.`,
    gCraft: 'You have everything. Make a torch.',
    gClimbA: 'The torch pushes the fog back. Carry the fire up the path and light the beacon.',
    gBackToA: 'The beacon is on another island. Go back to the boat and sail towards the light.',
    gReturnA: 'The fog has receded! Go back to the karbas: a second beacon glimmers far away.',
    gSailB: 'Sail to the second beacon.',
    gLandB: 'Go ashore.',
    gLanterns: (n) => `Path lanterns mark the way to the beacon. Light them with your torch (${n}/3).`,
    gClimbB: 'The path is lit. Climb up and light the beacon.',
    gNoFire: 'Without fire nothing can be lit here. Light the beacon on the near island first.',
    gFree: 'The sky answered with the aurora. End of the sketch — walk and sail anywhere you like.',
    aLand: 'Go ashore', aBoard: 'Board the boat', aBranch: 'Take sticks', aResin: 'Take resin', aTorch: 'Make a torch', aLantern: 'Light the lantern', aBeacon: 'Light the beacon',
    tBeacon: 'Beacon', tBranch: 'Sticks', tResin: 'Resin', tBoat: 'Boat', tLantern: 'Lantern', m: 'm',
    sound: 'Sound', quality: 'Graphics', hi: 'high', lo: 'light', on: 'on', off: 'off',
    endT: 'This is how the game will feel', endP: 'Fog, light and home. Every beacon you light pushes the world open and adds a new voice to the music of the sea. Next: the Godot development pack.', cont: 'Keep exploring',
  },
}[LANG];

// ------------------------------------------------------------------ renderer / scene
const isTouch = matchMedia('(pointer: coarse)').matches;
let quality = isTouch ? 'lo' : 'hi';
try { const q = localStorage.getItem('fog.quality'); if (q) quality = q; } catch (e) { /* no storage */ }
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, quality === 'hi' ? 2 : 1));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
document.getElementById('app').appendChild(renderer.domElement);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(58, window.innerWidth / window.innerHeight, 0.3, 2000);
scene.fog = new THREE.FogExp2(0xaeb8bb, 0.018);

// Lights that push back the fog: x, z, radius, strength (0..1).
// [0] player light (boat lantern or torch), [1] home hearth, [2] beacon A, [3] beacon B, [4..6] path lanterns, [7] moored boat lantern
const NSLOT = 8;
const BEACONS = Array.from({ length: NSLOT }, () => new THREE.Vector4(0, 0, 0, 0));
BEACONS[0].set(0, 0, 16, 0.55);
const fogU = { uBeacons: { value: BEACONS } };
const FOG_CLEAR_GLSL = `float clearF = 1.0;
  for (int i = 0; i < ${NSLOT}; i++) { float d = distance(P.xz, uBeacons[i].xy); clearF = min(clearF, mix(1.0, smoothstep(uBeacons[i].z * 0.3, uBeacons[i].z, d), uBeacons[i].w)); }`;
function patchFog(mat) {
  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uBeacons = fogU.uBeacons;
    sh.vertexShader = sh.vertexShader
      .replace('#include <fog_pars_vertex>', '#include <fog_pars_vertex>\nvarying vec3 vFogWorld;')
      .replace('#include <fog_vertex>', '#include <fog_vertex>\n{ vec4 fw = vec4(transformed, 1.0);\n#ifdef USE_INSTANCING\n fw = instanceMatrix * fw;\n#endif\n fw = modelMatrix * fw; vFogWorld = fw.xyz; }');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <fog_pars_fragment>', `#include <fog_pars_fragment>\nvarying vec3 vFogWorld;\nuniform vec4 uBeacons[${NSLOT}];`)
      .replace('#include <fog_fragment>', `#ifdef USE_FOG
  vec3 P = vFogWorld;
  ${FOG_CLEAR_GLSL}
  float dens = fogDensity * mix(0.22, 1.0, clearF);
  float fogFactor = 1.0 - exp(-dens * dens * vFogDepth * vFogDepth);
  gl_FragColor.rgb = mix(gl_FragColor.rgb, fogColor, fogFactor);
#endif`);
  };
  return mat;
}
const std = (color, extra = {}) => patchFog(new THREE.MeshStandardMaterial({ color, roughness: 0.95, metalness: 0, flatShading: true, ...extra }));

// soft sprite textures (fire, smoke, glimmers)
function radialTex(inner, outer) {
  const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d');
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32); gr.addColorStop(0, inner); gr.addColorStop(1, outer); g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
const texSoft = radialTex('rgba(255,255,255,1)', 'rgba(255,255,255,0)');
const texFlame = (() => { const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d'); const gr = g.createRadialGradient(32, 40, 0, 32, 36, 30); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.45, 'rgba(255,255,255,0.85)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.beginPath(); g.moveTo(32, 2); g.quadraticCurveTo(58, 34, 50, 50); g.quadraticCurveTo(32, 66, 14, 50); g.quadraticCurveTo(6, 34, 32, 2); g.fill(); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t; })();
const hemi = new THREE.HemisphereLight(0xc9d4d8, 0x3a3a30, 1.15); scene.add(hemi);
const sun = new THREE.DirectionalLight(0xffd6b0, 1.1); scene.add(sun); scene.add(sun.target);

// ------------------------------------------------------------------ palettes (weather "chapters")
const PAL = [
  { fog: 0xaeb8bb, zen: 0x7c8e9b, dens: 0.018, sun: 0xffd6b0, sunI: 1.1, hs: 0xc9d4d8, hg: 0x3a3a30, hI: 1.15, deep: 0x253c44, shal: 0x5b7a80, sunEl: 0.1, night: 0, aur: 0 },
  { fog: 0xe0c3ad, zen: 0x6f8fae, dens: 0.0105, sun: 0xffc48a, sunI: 1.55, hs: 0xdfe2e6, hg: 0x40382c, hI: 1.2, deep: 0x28465a, shal: 0x86a3ab, sunEl: 0.14, night: 0, aur: 0 },
  { fog: 0x1c2a42, zen: 0x060a16, dens: 0.0052, sun: 0x8aa2d8, sunI: 0.45, hs: 0x2a3a5c, hg: 0x08080e, hI: 0.55, deep: 0x0a1624, shal: 0x21395a, sunEl: 0.35, night: 1, aur: 1 },
];
const cur = { fog: new THREE.Color(), zen: new THREE.Color(), sun: new THREE.Color(), hs: new THREE.Color(), hg: new THREE.Color(), deep: new THREE.Color(), shal: new THREE.Color(), dens: 0, sunI: 0, hI: 0, sunEl: 0, night: 0, aur: 0 };
let palFrom = 0, palTo = 0, palT = 1, fogBoost = 1;
const sunDir = new THREE.Vector3(-0.55, 0.1, -0.83).normalize();
function applyPalette(dt) {
  palT = Math.min(1, palT + dt / 7);
  const a = PAL[palFrom], b = PAL[palTo], k = smooth(0, 1, palT);
  const mix = (key) => cur[key].set(a[key]).lerp(new THREE.Color(b[key]), k);
  ['fog', 'zen', 'sun', 'hs', 'hg', 'deep', 'shal'].forEach(mix);
  for (const key of ['dens', 'sunI', 'hI', 'sunEl', 'night', 'aur']) cur[key] = lerp(a[key], b[key], k);
  scene.fog.color.copy(cur.fog); scene.fog.density = cur.dens * fogBoost;
  hemi.color.copy(cur.hs); hemi.groundColor.copy(cur.hg); hemi.intensity = cur.hI;
  sun.color.copy(cur.sun); sun.intensity = cur.sunI;
  sunDir.set(-0.55, cur.sunEl, -0.83).normalize();
  sun.position.copy(boat.pos3).addScaledVector(sunDir, 200); sun.target.position.copy(boat.pos3);
}
function setChapter(i) { palFrom = palTo; palTo = i; palT = 0; }

// ------------------------------------------------------------------ sky dome + stars + aurora
const skyU = { uHorizon: { value: new THREE.Color() }, uZenith: { value: new THREE.Color() }, uSunDir: { value: sunDir }, uSun: { value: new THREE.Color() }, uNight: { value: 0 }, uTime: { value: 0 } };
const sky = new THREE.Mesh(new THREE.SphereGeometry(1500, 32, 16), new THREE.ShaderMaterial({
  uniforms: skyU, side: THREE.BackSide, depthWrite: false, fog: false,
  vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); vec4 p = modelViewMatrix * vec4(position,1.0); gl_Position = projectionMatrix * p; }',
  fragmentShader: `uniform vec3 uHorizon, uZenith, uSun, uSunDir; uniform float uNight, uTime; varying vec3 vDir;
  float hash(vec3 p){ return fract(sin(dot(p, vec3(12.9898,78.233,37.719))) * 43758.5453); }
  void main(){ vec3 d = normalize(vDir); float t = smoothstep(-0.02, 0.55, d.y);
    vec3 col = mix(uHorizon, uZenith, t);
    float s = max(dot(d, normalize(uSunDir)), 0.0);
    col += uSun * (pow(s, 600.0) * 3.0 + pow(s, 12.0) * 0.35) * (1.0 - uNight * 0.6);
    if (uNight > 0.01 && d.y > 0.02) { vec3 c = floor(d * 260.0); float h = hash(c); float st = step(0.9975, h) * (0.6 + 0.4 * sin(uTime * 2.0 + h * 50.0)); col += vec3(st) * uNight * smoothstep(0.02, 0.3, d.y); }
    gl_FragColor = vec4(col, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`,
}));
scene.add(sky);
const aurU = { uTime: { value: 0 }, uAmt: { value: 0 } };
const aurora = new THREE.Group();
[[-1.25, 0], [-0.62, 1], [0, 2], [0.62, 0], [1.25, 1]].forEach(([az, i]) => {
  const g = new THREE.PlaneGeometry(760, 130, 110, 1);
  const pos = g.attributes.position;
  for (let v = 0; v < pos.count; v++) { const x = pos.getX(v); const bend = Math.sin(x / 760 * Math.PI * (1.2 + i * 0.3) + i + az) * 80; pos.setZ(v, bend); }
  const m = new THREE.Mesh(g, new THREE.ShaderMaterial({
    uniforms: aurU, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `uniform float uTime, uAmt; varying vec2 vUv;
      void main(){ float w = 0.5 + 0.5 * sin(vUv.x * 40.0 + uTime * 0.7 + sin(vUv.x * 13.0 - uTime * 0.4) * 2.0);
        float fall = smoothstep(0.0, 0.25, vUv.y) * (1.0 - smoothstep(0.35, 1.0, vUv.y));
        float edge = smoothstep(0.0, 0.08, vUv.x) * (1.0 - smoothstep(0.92, 1.0, vUv.x));
        vec3 col = mix(vec3(0.15, 1.0, 0.55), vec3(0.6, 0.35, 1.0), smoothstep(0.3, 1.0, vUv.y));
        gl_FragColor = vec4(col * (0.35 + 0.65 * w) * fall * edge * uAmt * 0.55, 1.0); }`,
  }));
  m.position.set(Math.sin(az) * 620, 150 + i * 28, -Math.cos(az) * 620); m.rotation.set(0.22, -az, 0, 'YXZ'); aurora.add(m);
});
scene.add(aurora);

// ------------------------------------------------------------------ sea
const seaU = { uTime: { value: 0 }, uDeep: { value: new THREE.Color() }, uShallow: { value: new THREE.Color() }, uSunDir: { value: sunDir }, uSun: { value: new THREE.Color() },
  uFogColor: { value: new THREE.Color() }, uFogDensity: { value: 0.018 }, uBeacons: fogU.uBeacons, uCam: { value: new THREE.Vector3() }, uGlow: { value: new THREE.Vector4(0, 0, 0, 0) }, uGlow2: { value: new THREE.Vector4(0, 0, 0, 0) } };
const SEA_SIZE = quality === 'hi' ? 520 : 420, SEA_SEG = quality === 'hi' ? 180 : 110;
const seaGeo = new THREE.PlaneGeometry(SEA_SIZE, SEA_SIZE, SEA_SEG, SEA_SEG); seaGeo.rotateX(-Math.PI / 2);
const sea = new THREE.Mesh(seaGeo, new THREE.ShaderMaterial({
  uniforms: seaU,
  vertexShader: `uniform float uTime; varying vec3 vWorld; varying float vDepth; ${WAVE_GLSL}
    void main(){ vec4 w = modelMatrix * vec4(position, 1.0); w.y += wave(w.xz, uTime); vWorld = w.xyz; vec4 mv = viewMatrix * w; vDepth = -mv.z; gl_Position = projectionMatrix * mv; }`,
  fragmentShader: `uniform vec3 uDeep, uShallow, uSunDir, uSun, uFogColor, uCam; uniform float uFogDensity; uniform vec4 uBeacons[${NSLOT}]; uniform vec4 uGlow, uGlow2; varying vec3 vWorld; varying float vDepth;
    void main(){
      vec3 n = normalize(cross(dFdx(vWorld), dFdy(vWorld))); if (n.y < 0.0) n = -n;
      vec3 v = normalize(uCam - vWorld);
      float fres = pow(1.0 - max(dot(n, v), 0.0), 3.0);
      vec3 col = mix(uDeep, uShallow, clamp(fres * 0.9 + (1.0 - n.y) * 2.5, 0.0, 1.0));
      vec3 h = normalize(normalize(uSunDir) + v); col += uSun * pow(max(dot(n, h), 0.0), 90.0) * 1.2;
      float g1 = uGlow.w * exp(-distance(vWorld.xz, uGlow.xy) / 18.0); float g2 = uGlow2.w * exp(-distance(vWorld.xz, uGlow2.xy) / 18.0);
      col += vec3(1.0, 0.55, 0.2) * (g1 + g2) * (0.35 + fres);
      vec3 P = vWorld;
      ${FOG_CLEAR_GLSL}
      float dens = uFogDensity * mix(0.22, 1.0, clearF);
      col = mix(col, uFogColor, 1.0 - exp(-dens * dens * vDepth * vDepth));
      gl_FragColor = vec4(col, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
}));
scene.add(sea);

// ------------------------------------------------------------------ islands (terrain first, trees later so paths can stay clear)
const ISLANDS = [];
function makeIsland({ x, z, r, peak, seed, trees = 1, plateau = null, avoid = null }) {
  const n1 = makePerlin(seed), n2 = makePerlin(seed + 101);
  const heightAt = (wx, wz) => {
    const dx = (wx - x) / r, dz = (wz - z) / r, d = Math.sqrt(dx * dx + dz * dz);
    if (d > 1.35) return -5;
    const edge = d + fbm(n1, wx * 0.035, wz * 0.035) * 0.35;
    const mask = 1 - smooth(0.55, 1.0, edge);
    const hills = 0.45 + 0.55 * (0.5 + 0.5 * fbm(n2, wx * 0.07, wz * 0.07, 3));
    let h = mask * peak * hills * (1 - 0.3 * d) - (1 - mask) * 4 + mask * 0.5 - 0.9;
    if (plateau) { const pd = Math.hypot(wx - plateau.x, wz - plateau.z); const k = 1 - smooth(plateau.r * 0.6, plateau.r, pd); h = lerp(h, plateau.h, k); }
    return h;
  };
  const size = r * 2.7, seg = quality === 'hi' ? 80 : 56;
  let g = new THREE.PlaneGeometry(size, size, seg, seg); g.rotateX(-Math.PI / 2);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) { const wx = p.getX(i) + x, wz = p.getZ(i) + z; p.setY(i, Math.max(-4.5, heightAt(wx, wz))); }
  g = g.toNonIndexed(); g.computeVertexNormals();
  const pos = g.attributes.position, cols = new Float32Array(pos.count * 3), c = new THREE.Color(), rnd = mulberry32(seed + 7);
  const sand = new THREE.Color(0x8b8676), rock = new THREE.Color(0x6f7479), grass = new THREE.Color(0x6d8752), moss = new THREE.Color(0x56704a), heath = new THREE.Color(0x8a6f5a);
  for (let f = 0; f < pos.count; f += 3) {
    const ya = (pos.getY(f) + pos.getY(f + 1) + pos.getY(f + 2)) / 3;
    const nY = g.attributes.normal.getY(f);
    if (ya < 0.5) c.copy(sand); else if (nY < 0.72) c.copy(rock); else c.copy(rnd() < 0.18 ? heath : rnd() < 0.5 ? grass : moss);
    c.offsetHSL(0, 0, (rnd() - 0.5) * 0.04);
    for (let k = 0; k < 3; k++) { cols[(f + k) * 3] = c.r; cols[(f + k) * 3 + 1] = c.g; cols[(f + k) * 3 + 2] = c.b; }
  }
  g.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  const mesh = new THREE.Mesh(g, std(0xffffff, { vertexColors: true })); mesh.position.set(x, 0, z); scene.add(mesh);
  const ring = new THREE.Mesh(new THREE.RingGeometry(r * 0.78, r * 1.02, 48, 1), patchFog(new THREE.MeshBasicMaterial({ color: 0xe8eef0, transparent: true, opacity: 0.13, depthWrite: false })));
  ring.rotation.x = -Math.PI / 2; ring.position.set(x, 0.12, z); scene.add(ring);
  const isl = { x, z, r, peak, seed, trees, heightAt, mesh, ring, avoid: avoid ? [...avoid] : [], solids: [] };
  ISLANDS.push(isl);
  return isl;
}
function slopeAt(isl, x, z) { const e = 0.8; return Math.hypot(isl.heightAt(x + e, z) - isl.heightAt(x - e, z), isl.heightAt(x, z + e) - isl.heightAt(x, z - e)) / (2 * e); }
function groundAt(x, z) { let h = -5; for (const isl of ISLANDS) { if (Math.abs(x - isl.x) > isl.r * 1.4 || Math.abs(z - isl.z) > isl.r * 1.4) continue; h = Math.max(h, isl.heightAt(x, z)); } return h; }
function islandAt(x, z) { for (const isl of ISLANDS) { if (dist2(x, z, isl.x, isl.z) < isl.r * 1.35 && isl.heightAt(x, z) > -0.9) return isl; } return null; }
const trunkGeo = new THREE.CylinderGeometry(0.12, 0.17, 3.2, 5); trunkGeo.translate(0, 1.6, 0);
const birchCrown = new THREE.IcosahedronGeometry(1.25, 0); birchCrown.scale(1, 1.35, 1); birchCrown.translate(0, 3.6, 0);
const pineTrunk = new THREE.CylinderGeometry(0.16, 0.22, 2.2, 5); pineTrunk.translate(0, 1.1, 0);
function mergeGeos(list) {
  const arrs = list.map((g) => g.index ? g.toNonIndexed() : g); let n = 0; arrs.forEach((g) => { n += g.attributes.position.count; });
  const pos = new Float32Array(n * 3); let o = 0; arrs.forEach((g) => { pos.set(g.attributes.position.array, o); o += g.attributes.position.array.length; });
  const out = new THREE.BufferGeometry(); out.setAttribute('position', new THREE.BufferAttribute(pos, 3)); out.computeVertexNormals(); return out;
}
const pineCone = mergeGeos([[1.7, 2.6, 1.9], [1.35, 2.3, 3.2], [0.95, 2.0, 4.4]].map(([rr, h, y]) => { const c = new THREE.ConeGeometry(rr, h, 6); c.translate(0, y, 0); return c; }));
const boulderGeo = new THREE.DodecahedronGeometry(1, 0);
function scatterTrees(isl) {
  const rnd = mulberry32(isl.seed * 7 + 3), birches = [], pines = [], rocks = [];
  const count = Math.round(isl.r * isl.r * 0.05 * isl.trees);
  const blocked = (x, z, pad = 0) => isl.avoid.some((q) => Math.hypot(x - q.x, z - q.z) < q.r + pad);
  for (let i = 0; i < count * 4 && birches.length + pines.length < count; i++) {
    const a = rnd() * Math.PI * 2, rr = Math.sqrt(rnd()) * isl.r * 0.95, x = isl.x + Math.cos(a) * rr, z = isl.z + Math.sin(a) * rr;
    const h = isl.heightAt(x, z); if (h < 1.1 || slopeAt(isl, x, z) > 0.9 || blocked(x, z)) continue;
    const t = { x, y: h - 0.2, z, s: 0.75 + rnd() * 0.6, r: rnd() * 6.28 };
    (h > 4.5 || rnd() < 0.35 ? pines : birches).push(t);
    isl.solids.push({ x, z, r: 0.45 * t.s });
  }
  for (let i = 0; i < count * 0.35; i++) {
    const a = rnd() * 6.28, rr = isl.r * (0.5 + rnd() * 0.5), x = isl.x + Math.cos(a) * rr, z = isl.z + Math.sin(a) * rr; const h = isl.heightAt(x, z);
    if (h > -0.5 && !blocked(x, z, 1)) { const t = { x, y: h - 0.2, z, s: 0.5 + rnd() * 1.6, r: rnd() * 6.28 }; rocks.push(t); if (h > -0.2) isl.solids.push({ x, z, r: 0.8 * t.s }); }
  }
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
  const inst = (geo, mat, list, colorFn) => {
    if (!list.length) return;
    const im = new THREE.InstancedMesh(geo, mat, list.length);
    list.forEach((t, i) => { e.set(0, t.r, 0); q.setFromEuler(e); v.set(t.x, t.y, t.z); sc.setScalar(t.s); m4.compose(v, q, sc); im.setMatrixAt(i, m4); if (colorFn) im.setColorAt(i, colorFn(i)); });
    scene.add(im);
  };
  const cc = new THREE.Color();
  inst(trunkGeo, std(0xe6e2d6), birches);
  inst(birchCrown, std(0xffffff), birches, () => cc.set(rnd() < 0.25 ? 0xc9a24a : rnd() < 0.5 ? 0x9fb35a : 0x88a24c).offsetHSL(0, 0, (rnd() - 0.5) * 0.06));
  inst(pineTrunk, std(0x5b4331), pines);
  inst(pineCone, std(0xffffff), pines, () => cc.set(0x2f4a3a).offsetHSL(0, 0, (rnd() - 0.5) * 0.05));
  inst(boulderGeo, std(0x7a7f84), rocks);
}

// ------------------------------------------------------------------ props: izba, beacon, pomor cross, pier, path lanterns, pickups
const wood = std(0x6b4a33), darkWood = std(0x3f2e22), plank = std(0x8a6a4c), stone = std(0x7c7f82);
function box(w, h, d, mat, x, y, z, parent) { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); m.position.set(x, y, z); (parent || scene).add(m); return m; }
function makeIzba(x, y, z, rot) {
  const g = new THREE.Group(); g.position.set(x, y, z); g.rotation.y = rot; scene.add(g);
  for (let i = 0; i < 7; i++) { box(6.2, 0.42, 0.42, i % 2 ? wood : plank, 0, 0.2 + i * 0.4, 2.3, g); box(6.2, 0.42, 0.42, i % 2 ? plank : wood, 0, 0.2 + i * 0.4, -2.3, g); box(0.42, 0.42, 5.0, i % 2 ? wood : plank, 3.0, 0.2 + i * 0.4, 0, g); box(0.42, 0.42, 5.0, i % 2 ? plank : wood, -3.0, 0.2 + i * 0.4, 0, g); }
  const roofGeo = new THREE.BufferGeometry();
  const v = new Float32Array([-3.6, 2.9, 3, 3.6, 2.9, 3, 0, 5.2, 3, -3.6, 2.9, -3, 3.6, 2.9, -3, 0, 5.2, -3]);
  roofGeo.setAttribute('position', new THREE.BufferAttribute(v, 3));
  roofGeo.setIndex([0, 1, 2, 5, 4, 3, 0, 2, 5, 0, 5, 3, 1, 4, 5, 1, 5, 2]); roofGeo.computeVertexNormals();
  g.add(new THREE.Mesh(roofGeo, patchFog(new THREE.MeshStandardMaterial({ color: 0x4a3526, roughness: 1, flatShading: true, side: THREE.DoubleSide }))));
  box(0.7, 1.6, 0.7, stone, 1.6, 4.6, -0.6, g);
  const winMat = new THREE.MeshBasicMaterial({ color: 0xffb24a }); box(0.9, 0.7, 0.05, winMat, -1.4, 1.6, 2.53, g); box(0.9, 0.7, 0.05, winMat, 1.4, 1.6, 2.53, g);
  const pl = new THREE.PointLight(0xffa040, 30, 26, 1.6); pl.position.set(0, 1.8, 3.4); g.add(pl);
  return { g, chimney: new THREE.Vector3(x, y + 5.6, z).add(new THREE.Vector3(1.6, 0, -0.6).applyAxisAngle(new THREE.Vector3(0, 1, 0), rot)), light: pl };
}
function makePier(x, z, rot, len = 12) {
  const g = new THREE.Group(); g.position.set(x, 0, z); g.rotation.y = rot; scene.add(g);
  for (let i = 0; i < len; i++) box(2.4, 0.18, 0.9, i % 2 ? plank : wood, 0, 0.9, i * 1.0, g);
  for (let i = 0; i < len; i += 3) { box(0.25, 2.6, 0.25, darkWood, -1.1, -0.2, i, g); box(0.25, 2.6, 0.25, darkWood, 1.1, -0.2, i, g); }
  return g;
}
function makeCross(x, y, z, rot) { // поморский крест — навигационный знак
  const g = new THREE.Group(); g.position.set(x, y, z); g.rotation.y = rot; scene.add(g);
  box(0.35, 7.5, 0.35, darkWood, 0, 3.75, 0, g); box(2.8, 0.3, 0.3, darkWood, 0, 5.6, 0, g); box(1.4, 0.25, 0.25, darkWood, 0, 6.6, 0, g);
  const low = box(1.9, 0.25, 0.25, darkWood, 0, 2.3, 0, g); low.rotation.z = -0.35;
  return g;
}
function makeBeacon(x, y, z) {
  const g = new THREE.Group(); g.position.set(x, y, z); scene.add(g);
  for (const [dx, dz] of [[-1.3, -1.3], [1.3, -1.3], [-1.3, 1.3], [1.3, 1.3]]) { const leg = box(0.35, 10, 0.35, darkWood, dx * 0.8, 5, dz * 0.8, g); leg.rotation.z = dx * -0.06; leg.rotation.x = dz * 0.06; }
  for (let i = 1; i < 4; i++) { box(2.6 - i * 0.2, 0.2, 0.2, wood, 0, i * 2.4, 1.05 - i * 0.05, g); box(2.6 - i * 0.2, 0.2, 0.2, wood, 0, i * 2.4, -1.05 + i * 0.05, g); }
  box(3.4, 0.3, 3.4, plank, 0, 10.1, 0, g);
  const bowl = new THREE.Mesh(new THREE.CylinderGeometry(1.0, 0.6, 0.8, 6), stone); bowl.position.set(0, 10.7, 0); g.add(bowl);
  // a stack of firewood waiting at the foot of the tower
  for (let i = 0; i < 5; i++) { const l = box(0.22, 0.22, 1.6, plank, 1.9, 0.2 + (i % 2) * 0.22, -0.3 + i * 0.26, g); l.rotation.y = 0.2; }
  const light = new THREE.PointLight(0xff8a30, 0, 90, 1.5); light.position.set(0, 12.2, 0); g.add(light);
  return { g, light, fire: new THREE.Vector3(x, y + 11.4, z), base: new THREE.Vector3(x, y, z), lit: 0 };
}
function makePathLantern(x, y, z, rot) {
  const g = new THREE.Group(); g.position.set(x, y, z); g.rotation.y = rot; scene.add(g);
  box(0.2, 2.2, 0.2, darkWood, 0, 1.1, 0, g); box(0.9, 0.14, 0.14, darkWood, 0.3, 2.1, 0, g);
  const glass = new THREE.MeshStandardMaterial({ color: 0x3a3226, emissive: 0x000000, roughness: 0.6 });
  const lamp = box(0.32, 0.42, 0.32, patchFog(glass), 0.62, 1.8, 0, g);
  const light = new THREE.PointLight(0xffa84a, 0, 18, 1.5); light.position.set(0.62, 1.8, 0); g.add(light);
  return { g, glass, lamp, light, x, z, y, lit: 0, tip: new THREE.Vector3(x, y + 1.8, z) };
}
function makePickup(kind, x, y, z) {
  const g = new THREE.Group(); g.position.set(x, y, z); scene.add(g);
  if (kind === 'branch') {
    for (let i = 0; i < 4; i++) { const s = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.07, 1.5, 4), wood); s.rotation.z = Math.PI / 2; s.rotation.y = -0.4 + i * 0.25; s.position.set(0, 0.12 + (i % 2) * 0.08, (i - 1.5) * 0.08); g.add(s); }
    const band = new THREE.Mesh(new THREE.TorusGeometry(0.16, 0.035, 4, 8), std(0xc9a27a)); band.rotation.y = Math.PI / 2; band.position.y = 0.14; g.add(band);
  } else {
    const stump = new THREE.Mesh(new THREE.CylinderGeometry(0.38, 0.45, 0.6, 7), std(0x5b4331)); stump.position.y = 0.3; g.add(stump);
    const drop = new THREE.Mesh(new THREE.IcosahedronGeometry(0.2, 0), new THREE.MeshStandardMaterial({ color: 0xffa726, emissive: 0x7a3a00, roughness: 0.3 })); drop.position.set(0.3, 0.5, 0.1); g.add(drop);
  }
  const spark = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSoft, color: 0xffe2a8, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false }));
  spark.scale.setScalar(1.3); spark.position.set(x, y + 1.3, z); scene.add(spark);
  return { kind, g, spark, x, z, y, taken: false };
}

// ------------------------------------------------------------------ world layout
const home = makeIsland({ x: 0, z: 62, r: 40, peak: 7, seed: 11, trees: 0.8, avoid: [{ x: -4, z: 47, r: 10 }, { x: 4, z: 30, r: 6 }, { x: 9, z: 40, r: 3 }] });
const islA = makeIsland({ x: -48, z: -150, r: 44, peak: 11, seed: 23, trees: 1.1, plateau: { x: -48, z: -152, r: 11, h: 9 }, avoid: [{ x: -48, z: -152, r: 7 }, { x: -40, z: -145, r: 3 }] });
const islB = makeIsland({ x: 135, z: -330, r: 52, peak: 14, seed: 37, trees: 1.2, plateau: { x: 135, z: -332, r: 12, h: 12 }, avoid: [{ x: 135, z: -332, r: 7 }, { x: 144, z: -324, r: 3 }] });
const islets = [[70, -60, 12, 4, 5], [-105, -45, 16, 5, 6], [40, -215, 14, 6, 7], [-110, -265, 20, 7, 8], [210, -190, 18, 6, 9], [-20, -380, 24, 8, 10], [260, -370, 22, 9, 12]].map(([x, z, r, pk, s]) => makeIsland({ x, z, r, peak: pk, seed: 50 + s, trees: 0.9 }));
function landingPoint(isl, bx, bz, fromX, fromZ) { // walk from the beacon toward `from` until the water
  const dx = fromX - bx, dz = fromZ - bz, d = Math.hypot(dx, dz), ux = dx / d, uz = dz / d;
  let shore = null;
  for (let s = 0; s < 200; s += 1) { const x = bx + ux * s, z = bz + uz * s; const h = isl.heightAt(x, z); if (h > 0.4) shore = { x, z }; if (h < -1.2) return { sea: new THREE.Vector3(x + ux * 3, 0, z + uz * 3), shore, ux, uz }; }
  return { sea: new THREE.Vector3(bx + ux * isl.r * 1.2, 0, bz + uz * isl.r * 1.2), shore, ux, uz };
}
const LA = landingPoint(islA, -48, -152, 0, 62), LB = landingPoint(islB, 135, -332, -48, -152);
// keep the paths from the shore to the beacons free of trees
for (const [isl, L, bx, bz] of [[islA, LA, -48, -152], [islB, LB, 135, -332]]) {
  const len = dist2(L.shore.x, L.shore.z, bx, bz);
  for (let s = 0; s <= len; s += 4) { const t = s / len; isl.avoid.push({ x: lerp(L.shore.x, bx, t), z: lerp(L.shore.z, bz, t), r: 5.5 }); }
}
ISLANDS.forEach(scatterTrees);
const izbaY = home.heightAt(-4, 48);
const izba = makeIzba(-4, Math.max(0.6, izbaY) - 0.1, 48, Math.PI);
home.solids.push({ x: -4, z: 48, r: 3.6 });
let shoreZ = 48; while (shoreZ > 0 && home.heightAt(4, shoreZ) > -0.4) shoreZ -= 0.5; // first water south of the izba
makePier(4, shoreZ + 3, Math.PI, 13);
makeCross(9, home.heightAt(9, 40) - 0.2, 40, 0.4); home.solids.push({ x: 9, z: 40, r: 0.4 });
const beaconA = makeBeacon(-48, islA.heightAt(-48, -152) - 0.3, -152);
const beaconB = makeBeacon(135, islB.heightAt(135, -332) - 0.3, -332);
islA.solids.push({ x: -48, z: -152, r: 1.7 }); islB.solids.push({ x: 135, z: -332, r: 1.7 });
makeCross(-40, islA.heightAt(-40, -145) - 0.2, -145, 0.9); islA.solids.push({ x: -40, z: -145, r: 0.4 });
makeCross(144, islB.heightAt(144, -324) - 0.2, -324, -0.4); islB.solids.push({ x: 144, z: -324, r: 0.4 });
const GOALS = [
  { beacon: beaconA, slot: 2, landing: LA.sea, isl: islA, name: 'A' },
  { beacon: beaconB, slot: 3, landing: LB.sea, isl: islB, name: 'B' },
];
BEACONS[1].set(-4, 48, 34, 0.8);
// on the path: pickups on island A, lanterns on island B
function pathPoint(isl, L, bx, bz, t, side) {
  const x0 = lerp(L.shore.x, bx, t), z0 = lerp(L.shore.z, bz, t), px = -L.uz, pz = L.ux; // perpendicular
  for (let k = 0; k < 8; k++) { const x = x0 + px * side * (1 - k / 8), z = z0 + pz * side * (1 - k / 8); if (isl.heightAt(x, z) > 0.5) return { x, z, y: isl.heightAt(x, z) }; }
  return { x: x0, z: z0, y: isl.heightAt(x0, z0) };
}
const PICKUPS = [[0.22, 3, 'branch'], [0.38, -3.2, 'resin'], [0.52, 3, 'branch'], [0.7, -3, 'branch']].map(([t, side, kind]) => { const p = pathPoint(islA, LA, -48, -152, t, side); return makePickup(kind, p.x, p.y - 0.05, p.z); });
const LANTERNS = [[0.3, 2.6], [0.56, -2.6], [0.8, 2.6]].map(([t, side], i) => { const p = pathPoint(islB, LB, 135, -332, t, side); islB.solids.push({ x: p.x, z: p.z, r: 0.35 }); const l = makePathLantern(p.x, p.y - 0.1, p.z, Math.atan2(LB.ux, LB.uz) + (i % 2 ? Math.PI : 0)); l._i = i; return l; });

// ------------------------------------------------------------------ boat (карбас) + sailor + walking character
const boat = { x: 7.3, z: shoreZ - 6, yaw: 0, speed: 0, turn: 0, pos3: new THREE.Vector3(), group: new THREE.Group(), crew: [] };
{
  const hull = new THREE.BoxGeometry(1.9, 0.8, 5.2, 4, 2, 10), p = hull.attributes.position;
  for (let i = 0; i < p.count; i++) { let x = p.getX(i), y = p.getY(i), z = p.getZ(i); const t = Math.abs(z) / 2.6; x *= 1 - 0.85 * t * t; if (y < 0) x *= 0.55; y += Math.pow(t, 3) * 0.55; if (y < 0) y *= 1 - 0.3 * t; p.setXYZ(i, x, y, z); }
  hull.computeVertexNormals();
  const h = new THREE.Mesh(hull, std(0x5a3f2c)); h.position.y = 0.25; boat.group.add(h);
  box(1.7, 0.12, 4.3, plank, 0, 0.62, 0, boat.group);
  const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.09, 5, 5), darkWood); mast.position.set(0, 3.1, -0.6); boat.group.add(mast);
  const sailG = new THREE.PlaneGeometry(2.6, 3.4, 8, 8), sp = sailG.attributes.position;
  for (let i = 0; i < sp.count; i++) { const x = sp.getX(i), y = sp.getY(i); sp.setZ(i, 0.35 * (1 - (x / 1.3) ** 2) * (1 - ((y) / 1.7) ** 2 * 0.3)); }
  sailG.computeVertexNormals();
  boat.sail = new THREE.Mesh(sailG, patchFog(new THREE.MeshStandardMaterial({ color: 0xd9cbb0, roughness: 1, side: THREE.DoubleSide, flatShading: true })));
  boat.sail.position.set(0, 3.4, -0.45); boat.group.add(boat.sail);
  const stripe = new THREE.Mesh(new THREE.PlaneGeometry(2.62, 0.35), patchFog(new THREE.MeshStandardMaterial({ color: 0xa3372c, side: THREE.DoubleSide, roughness: 1 }))); stripe.position.set(0, 2.2, -0.12); boat.group.add(stripe);
  const body = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.33, 1.0, 6), std(0xa3372c)); body.position.set(0, 1.25, 1.6); boat.group.add(body);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.24, 8, 6), std(0xe0b89a)); head.position.set(0, 1.98, 1.6); boat.group.add(head);
  const hat = new THREE.Mesh(new THREE.ConeGeometry(0.28, 0.3, 6), std(0x2c2f36)); hat.position.set(0, 2.25, 1.6); boat.group.add(hat);
  boat.crew.push(body, head, hat);
  const lantern = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.35, 0.25), new THREE.MeshBasicMaterial({ color: 0xffc070 })); lantern.position.set(0.6, 1.3, 2.3); boat.group.add(lantern);
  boat.light = new THREE.PointLight(0xffb060, 8, 18, 1.5); boat.light.position.set(0.6, 1.5, 2.3); boat.group.add(boat.light);
  scene.add(boat.group);
}
function collide(x, z) { for (const isl of ISLANDS) { if (Math.hypot(x - isl.x, z - isl.z) > isl.r * 1.4) continue; if (isl.heightAt(x, z) > -0.9) return true; } return false; }

const foot = { x: 0, z: 0, y: 0, yaw: 0, camYaw: 0, speed: 0, step: 0, group: new THREE.Group(), legs: [], torchLight: null, torchTip: new THREE.Vector3(), torchMesh: null };
{
  const g = foot.group;
  const body = new THREE.Mesh(new THREE.CylinderGeometry(0.27, 0.32, 0.95, 6), std(0xa3372c)); body.position.y = 1.08; g.add(body);
  const belt = new THREE.Mesh(new THREE.CylinderGeometry(0.33, 0.33, 0.1, 6), std(0x2c2f36)); belt.position.y = 0.82; g.add(belt);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.23, 8, 6), std(0xe0b89a)); head.position.y = 1.8; g.add(head);
  const hat = new THREE.Mesh(new THREE.ConeGeometry(0.27, 0.3, 6), std(0x2c2f36)); hat.position.y = 2.06; g.add(hat);
  const beard = new THREE.Mesh(new THREE.ConeGeometry(0.14, 0.28, 5), std(0xc9b38f)); beard.rotation.x = Math.PI; beard.position.set(0, 1.62, -0.17); g.add(beard);
  for (const s of [-1, 1]) {
    const hip = new THREE.Group(); hip.position.set(0.13 * s, 0.62, 0); g.add(hip);
    const leg = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.62, 0.2), std(0x3b3a3f)); leg.position.y = -0.31; hip.add(leg);
    foot.legs.push(hip);
  }
  const arm = new THREE.Group(); arm.position.set(0.34, 1.42, 0); g.add(arm);
  const sleeve = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.55, 0.13), std(0xa3372c)); sleeve.position.set(0, -0.22, -0.08); sleeve.rotation.x = 0.5; arm.add(sleeve);
  const stick = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.045, 0.8, 5), wood); stick.position.set(0, -0.2, -0.5); stick.rotation.x = -0.35; arm.add(stick);
  foot.torchMesh = stick; stick.visible = false; foot.arm = arm;
  foot.torchLight = new THREE.PointLight(0xffa04a, 0, 16, 1.4); foot.torchLight.position.set(0, 0.25, -0.62); arm.add(foot.torchLight);
  g.visible = false; scene.add(g);
}

// ------------------------------------------------------------------ particles (fire, smoke, fog wisps, will-o'-wisp hint)
const fireParts = [], smokeParts = [], wisps = [];
function spawnFire(pos, n = 1, scale = 1, spread = 1.4) {
  for (let i = 0; i < n; i++) {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: texFlame, color: 0xffa040, depthWrite: false, transparent: true, fog: false }));
    s.position.copy(pos).add(new THREE.Vector3((Math.random() - 0.5) * spread, -0.3 * scale, (Math.random() - 0.5) * spread)); s.scale.setScalar(2.4 * scale);
    scene.add(s); fireParts.push({ s, life: 0, max: 0.6 + Math.random() * 0.5, vy: (2.5 + Math.random() * 2) * scale, size: (2.6 + Math.random() * 1.4) * scale });
  }
}
function spawnSmoke(pos) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSoft, color: 0x9a9a98, depthWrite: false, transparent: true, opacity: 0.35 }));
  s.position.copy(pos); s.scale.setScalar(1.2); scene.add(s); smokeParts.push({ s, life: 0, max: 5 + Math.random() * 2 });
}
const WISP_N = quality === 'hi' ? 70 : 40;
for (let i = 0; i < WISP_N; i++) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSoft, color: 0xdfe6e8, depthWrite: false, transparent: true, opacity: 0.1 }));
  s.scale.set(40 + Math.random() * 40, 10 + Math.random() * 8, 1); s.position.set((Math.random() - 0.5) * 300, 3 + Math.random() * 6, (Math.random() - 0.5) * 300);
  scene.add(s); wisps.push(s);
}
const hint = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSoft, color: 0xbfe6ff, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false }));
hint.scale.setScalar(9); scene.add(hint);
const glowA = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSoft, color: 0xff9a40, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false, opacity: 0 }));
const glowB = glowA.clone(); glowB.material = glowA.material.clone();
glowA.position.copy(beaconA.fire); glowB.position.copy(beaconB.fire); glowA.scale.setScalar(24); glowB.scale.setScalar(24); scene.add(glowA, glowB);

// ------------------------------------------------------------------ audio: wind, waves, gulls, fire, steps; music in layers that grow with every beacon
const AU = {
  ctx: null, on: true, level: 0,
  init() {
    if (this.ctx) { this.ctx.resume && this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
    const c = this.ctx = new AC();
    this.master = c.createGain(); this.master.gain.value = this.on ? 0.85 : 0;
    const comp = c.createDynamicsCompressor(); comp.threshold.value = -20; comp.ratio.value = 3;
    this.master.connect(comp); comp.connect(c.destination);
    const len = c.sampleRate * 3.2, ir = c.createBuffer(2, len, c.sampleRate);
    for (let ch = 0; ch < 2; ch++) { const d = ir.getChannelData(ch); for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.6); }
    this.rev = c.createConvolver(); this.rev.buffer = ir; this.revGain = c.createGain(); this.revGain.gain.value = 0.55; this.rev.connect(this.revGain); this.revGain.connect(this.master);
    const nlen = c.sampleRate * 4, nb = c.createBuffer(1, nlen, c.sampleRate), nd = nb.getChannelData(0); let b0 = 0;
    for (let i = 0; i < nlen; i++) { const w = Math.random() * 2 - 1; b0 = 0.985 * b0 + 0.15 * w; nd[i] = b0 * 0.6; }
    this.noise = nb;
    const wn = c.createBuffer(1, c.sampleRate, c.sampleRate), wd = wn.getChannelData(0); for (let i = 0; i < wd.length; i++) wd[i] = Math.random() * 2 - 1; this.white = wn;
    const loopNoise = (freq, type, q, gain) => { const s = c.createBufferSource(); s.buffer = nb; s.loop = true; const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q; const g = c.createGain(); g.gain.value = gain; s.connect(f); f.connect(g); g.connect(this.master); s.start(); return { f, g }; };
    this.wind = loopNoise(600, 'bandpass', 0.6, 0.22);
    this.waves = loopNoise(420, 'lowpass', 0.5, 0.35);
    this.fire = loopNoise(2500, 'bandpass', 0.8, 0);
    this.drone = c.createGain(); this.drone.gain.value = 0.0; const dl = c.createBiquadFilter(); dl.type = 'lowpass'; dl.frequency.value = 420;
    for (const [f, det] of [[73.42, -6], [73.42, 6], [110, 0]]) { const o = c.createOscillator(); o.type = 'sawtooth'; o.frequency.value = f; o.detune.value = det; o.connect(dl); o.start(); }
    dl.connect(this.drone); this.drone.connect(this.master); this.drone.connect(this.rev);
    this.drone.gain.setTargetAtTime(0.05, c.currentTime, 3);
    this.ks = new Map(); const t = c.currentTime;
    this.nextPhrase = t + 2; this.nextGull = t + 6; this.nextChord = t + 4; this.chordI = 0; this.nextBell = t + 3; this.nextChoir = t + 5; this.nextStep = 0;
    this.timer = setInterval(() => this.tick(), 100);
  },
  setOn(v) { this.on = v; if (this.master) this.master.gain.setTargetAtTime(v ? 0.85 : 0, this.ctx.currentTime, 0.1); },
  hz: (m) => 440 * Math.pow(2, (m - 69) / 12),
  pluckBuf(f) { const c = this.ctx, key = Math.round(f); if (this.ks.has(key)) return this.ks.get(key); const n = Math.floor(c.sampleRate * 2.4), P = Math.max(2, Math.round(c.sampleRate / f - 0.5)); const b = c.createBuffer(1, n, c.sampleRate), d = b.getChannelData(0), ring = new Float32Array(P); for (let i = 0; i < P; i++) ring[i] = Math.random() * 2 - 1; for (let i = 0; i < n; i++) { const j = i % P, v = ring[j]; d[i] = v; ring[j] = 0.4985 * (v + ring[(j + 1) % P]); } this.ks.set(key, b); return b; },
  pluck(midi, t, vol = 0.25) { if (!this.ctx) return; const c = this.ctx, s = c.createBufferSource(); s.buffer = this.pluckBuf(this.hz(midi)); const g = c.createGain(); g.gain.value = vol; const f = c.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 3200; s.connect(f); f.connect(g); g.connect(this.master); g.connect(this.rev); s.start(t); },
  pad(midis, t, dur, vol = 0.05) { const c = this.ctx; for (const m of midis) { const o = c.createOscillator(), o2 = c.createOscillator(), g = c.createGain(), f = c.createBiquadFilter(); o.type = 'sawtooth'; o2.type = 'sawtooth'; o.frequency.value = o2.frequency.value = this.hz(m); o2.detune.value = 9; f.type = 'lowpass'; f.frequency.value = 900; g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(vol, t + dur * 0.35); g.gain.linearRampToValueAtTime(0.0001, t + dur); o.connect(f); o2.connect(f); f.connect(g); g.connect(this.rev); g.connect(this.master); o.start(t); o2.start(t); o.stop(t + dur + 0.1); o2.stop(t + dur + 0.1); } },
  bell(midi, t, vol = 0.08) { if (!this.ctx) return; const c = this.ctx, f0 = this.hz(midi); for (const [mul, a, d] of [[1, 1, 3.2], [2.76, 0.45, 1.6], [5.4, 0.25, 0.8]]) { const o = c.createOscillator(), g = c.createGain(); o.type = 'sine'; o.frequency.value = f0 * mul; g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(vol * a, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, t + d); o.connect(g); g.connect(this.master); g.connect(this.rev); o.start(t); o.stop(t + d + 0.05); } },
  choir(midis, t, dur, vol = 0.035) { const c = this.ctx; for (const m of midis) { const o = c.createOscillator(), g = c.createGain(); o.type = 'sawtooth'; o.frequency.value = this.hz(m); const vib = c.createOscillator(), vg = c.createGain(); vib.frequency.value = 5; vg.gain.value = 3; vib.connect(vg); vg.connect(o.detune); const out = c.createGain(); out.gain.setValueAtTime(0.0001, t); out.gain.linearRampToValueAtTime(vol, t + dur * 0.4); out.gain.linearRampToValueAtTime(0.0001, t + dur); for (const [ff, q] of [[700, 6], [1150, 8]]) { const f = c.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = ff; f.Q.value = q; o.connect(f); f.connect(out); } out.connect(this.rev); out.connect(this.master); o.start(t); vib.start(t); o.stop(t + dur + 0.1); vib.stop(t + dur + 0.1); } },
  noiseHit(t, freq, q, vol, dur) { const c = this.ctx, s = c.createBufferSource(); s.buffer = this.white; const f = c.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = q; const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur); s.connect(f); f.connect(g); g.connect(this.master); s.start(t); s.stop(t + dur + 0.05); },
  gull(t) { const c = this.ctx, o = c.createOscillator(), g = c.createGain(); o.type = 'triangle'; o.frequency.setValueAtTime(1500, t); o.frequency.exponentialRampToValueAtTime(900, t + 0.35); o.frequency.exponentialRampToValueAtTime(1300, t + 0.5); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.035, t + 0.05); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.55); o.connect(g); g.connect(this.master); g.connect(this.rev); o.start(t); o.stop(t + 0.6); },
  // one-shots for actions
  sfx(kind, arg = 0) {
    if (!this.ctx) return; const t = this.ctx.currentTime + 0.02;
    if (kind === 'pickup') { this.pluck(74 + arg * 3, t, 0.2); this.pluck(81 + arg * 3, t + 0.09, 0.12); }
    else if (kind === 'torch') { this.noiseHit(t, 1800, 0.7, 0.25, 0.5); this.noiseHit(t + 0.05, 600, 0.6, 0.18, 0.9); this.pluck(50, t + 0.1, 0.2); this.pluck(62, t + 0.25, 0.14); }
    else if (kind === 'lantern') { this.bell([69, 72, 74][arg] || 76, t, 0.1); this.pluck([57, 60, 62][arg] || 64, t, 0.14); }
    else if (kind === 'land') { this.noiseHit(t, 300, 0.8, 0.2, 0.35); this.pluck(55, t + 0.05, 0.12); }
    else if (kind === 'board') { this.noiseHit(t, 250, 0.8, 0.2, 0.4); }
    else if (kind === 'step') { this.noiseHit(t, 420 + Math.random() * 200, 1.2, 0.05 + Math.random() * 0.02, 0.09); }
  },
  swell(chapter) { if (!this.ctx) return; const t = this.ctx.currentTime + 0.1; const chords = chapter === 1 ? [[50, 57, 62, 65], [53, 60, 65, 69]] : [[50, 57, 62, 66, 69], [55, 62, 67, 71]]; chords.forEach((ch, i) => this.pad(ch, t + i * 3.2, 7, 0.045)); [62, 65, 69, 72, 74, 77].forEach((m, i) => this.pluck(m + (chapter === 2 ? 2 : 0), t + i * 0.28, 0.2)); this.drone.gain.setTargetAtTime(chapter === 2 ? 0.035 : 0.06, t, 4); },
  tick() {
    const c = this.ctx; if (!c || c.state !== 'running') return;
    const t = c.currentTime, st = STATE, lv = this.level;
    const sp = STATE.mode === 'boat' ? Math.abs(boat.speed) / 9 : 0;
    this.wind.f.frequency.setTargetAtTime(420 + 380 * (0.5 + 0.5 * Math.sin(t * 0.13)) + sp * 300, t, 0.8);
    this.wind.g.gain.setTargetAtTime((0.12 + 0.12 * (0.5 + 0.5 * Math.sin(t * 0.07))) * (st.chapter === 2 ? 0.5 : 1) * (STATE.mode === 'foot' ? 0.7 : 1), t, 1);
    const shoreDist = STATE.mode === 'foot' ? 1 : 0;
    this.waves.g.gain.setTargetAtTime((0.22 + 0.18 * (0.5 + 0.5 * Math.sin(t * 0.6)) + sp * 0.15) * (shoreDist ? 0.55 : 1), t, 0.4);
    const ear = STATE.mode === 'foot' ? new THREE.Vector3(foot.x, foot.y, foot.z) : boat.pos3;
    let fireNear = STATE.torch && STATE.mode === 'foot' ? 0.35 : 0;
    for (const b of [beaconA, beaconB]) if (b.lit > 0) fireNear = Math.max(fireNear, b.lit * clamp(1 - ear.distanceTo(b.fire) / 70, 0, 1));
    this.fire.g.gain.setTargetAtTime(fireNear * (0.05 + 0.06 * Math.random()), t, 0.05);
    // layer 0: sparse gusli phrases, a drone and gulls
    if (t > this.nextPhrase) {
      const scale = [62, 64, 65, 67, 69, 72, 74, 76], r = Math.random, n = 3 + Math.floor(r() * 4); let i = Math.floor(r() * 4);
      for (let k = 0; k < n; k++) { i = clamp(i + Math.floor(r() * 3) - 1, 0, scale.length - 1); this.pluck(scale[i] - (lv === 0 ? 12 : 0), t + k * (0.35 + r() * 0.2), 0.16); }
      this.nextPhrase = t + [7, 5, 4][lv] + r() * [8, 5, 4][lv];
    }
    // layer 1 (after the first beacon): a slow warm chord walk, Dm – F – C – G
    if (lv >= 1 && t > this.nextChord) { const chords = [[50, 57, 62, 65], [53, 57, 60, 65], [48, 55, 60, 64], [55, 59, 62, 67]]; this.pad(chords[this.chordI % 4], t, 9, 0.028); this.chordI++; this.nextChord = t + 8; }
    // layer 2 (after the second beacon): bells like frost and a far choir under the aurora
    if (lv >= 2 && t > this.nextBell) { const arp = [74, 77, 81, 84, 86]; for (let k = 0; k < 4; k++) this.bell(arp[Math.floor(Math.random() * arp.length)], t + k * 0.42, 0.035); this.nextBell = t + 6 + Math.random() * 4; }
    if (lv >= 2 && t > this.nextChoir) { this.choir([50, 57, 62], t, 11, 0.03); this.nextChoir = t + 13; }
    if (t > this.nextGull && st.chapter < 2) { this.gull(t); if (Math.random() < 0.5) this.gull(t + 0.7); this.nextGull = t + 9 + Math.random() * 14; }
  },
};
document.addEventListener('visibilitychange', () => { if (!AU.ctx) return; if (document.hidden) AU.ctx.suspend(); else AU.ctx.resume(); });

// ------------------------------------------------------------------ input
const keys = new Set();
window.addEventListener('keydown', (e) => { keys.add(e.code); if (e.code === 'KeyE' || e.code === 'Enter') { e.preventDefault(); tryAction(); } });
window.addEventListener('keyup', (e) => keys.delete(e.code));
const joy = { active: false, id: -1, ox: 0, oy: 0, x: 0, y: 0 };
const look = { yaw: 0, pitch: 0.32, dragging: false, id: -1, lx: 0, ly: 0, idle: 0 };
const cv = renderer.domElement;
cv.addEventListener('pointerdown', (e) => {
  if (!STATE.started) return;
  if (e.pointerType !== 'mouse' && e.clientX < window.innerWidth * 0.45 && !joy.active) { joy.active = true; joy.id = e.pointerId; joy.ox = e.clientX; joy.oy = e.clientY; joy.x = joy.y = 0; showJoy(true); return; }
  look.dragging = true; look.id = e.pointerId; look.lx = e.clientX; look.ly = e.clientY;
});
window.addEventListener('pointermove', (e) => {
  if (joy.active && e.pointerId === joy.id) { joy.x = clamp((e.clientX - joy.ox) / 60, -1, 1); joy.y = clamp((e.clientY - joy.oy) / 60, -1, 1); showJoy(true); return; }
  if (look.dragging && e.pointerId === look.id) {
    const dx = (e.clientX - look.lx) * 0.006;
    if (STATE.mode === 'foot') foot.camYaw -= dx; else look.yaw -= dx;
    look.pitch = clamp(look.pitch + (e.clientY - look.ly) * 0.004, 0.05, 0.9); look.lx = e.clientX; look.ly = e.clientY; look.idle = 0;
  }
});
const endPtr = (e) => { if (joy.active && e.pointerId === joy.id) { joy.active = false; joy.x = joy.y = 0; showJoy(false); } if (look.dragging && e.pointerId === look.id) look.dragging = false; };
window.addEventListener('pointerup', endPtr); window.addEventListener('pointercancel', endPtr);
cv.addEventListener('contextmenu', (e) => e.preventDefault());

// ------------------------------------------------------------------ HUD
const $ = (s) => document.querySelector(s);
const STATE = { started: false, mode: 'boat', chapter: 0, goal: 0, cine: null, ended: false, time: 0, torch: false, branch: 0, resin: 0, lanterns: 0, endAt: 0 };
function showJoy(on) { const j = $('#joy'); j.style.display = on ? 'block' : 'none'; if (on) { j.style.left = (joy.ox - 50) + 'px'; j.style.top = (joy.oy - 50) + 'px'; $('#knob').style.transform = `translate(${joy.x * 34}px, ${joy.y * 34}px)`; } }
document.documentElement.lang = LANG; $('#title').textContent = TXT.title; $('#sub').textContent = TXT.sub; $('#startBtn').textContent = TXT.start; $('#lede').textContent = TXT.lede; $('#phones').textContent = TXT.phones;
$('#modesT').textContent = TXT.modesT; $('#modes').innerHTML = TXT.modes.map((m) => '<li>' + m + '</li>').join('');
$('#ctrl').textContent = isTouch ? TXT.ctrlTouch : TXT.ctrlDesk;
$('#endT').textContent = TXT.endT; $('#endP').textContent = TXT.endP; $('#contBtn').textContent = TXT.cont;
const sndBtn = $('#snd'), qBtn = $('#qual');
const refreshBtns = () => { sndBtn.textContent = TXT.sound + ': ' + (AU.on ? TXT.on : TXT.off); sndBtn.setAttribute('aria-pressed', String(AU.on)); qBtn.textContent = TXT.quality + ': ' + (quality === 'hi' ? TXT.hi : TXT.lo); };
refreshBtns();
sndBtn.onclick = () => { AU.setOn(!AU.on); refreshBtns(); };
qBtn.onclick = () => { quality = quality === 'hi' ? 'lo' : 'hi'; try { localStorage.setItem('fog.quality', quality); } catch (e) { /* ignore */ } renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, quality === 'hi' ? 2 : 1)); refreshBtns(); };
$('#startBtn').onclick = () => { $('#intro').classList.add('gone'); STATE.started = true; AU.init(); $('#hud').classList.add('on'); };
$('#actBtn').onclick = () => tryAction();
$('#contBtn').onclick = () => { $('#end').classList.remove('on'); };

// ------------------------------------------------------------------ actions: go ashore, board, take, make a torch, light lanterns and beacons
function findLanding() { // nearest walkable land within reach of the boat
  let best = null;
  for (let a = 0; a < 16; a++) for (let d = 2; d <= 14; d += 1.5) {
    const ang = a / 16 * Math.PI * 2, x = boat.x + Math.cos(ang) * d, z = boat.z + Math.sin(ang) * d, h = groundAt(x, z);
    if (h <= 0.25) continue;
    const isl = islandAt(x, z), steep = isl ? slopeAt(isl, x, z) : 0;
    if (steep < 1.3 && !blockedFoot(x, z, 0.5)) { const score = d + steep * 5; if (!best || score < best.score) best = { x, z, d, score }; break; }
  }
  return best;
}
function blockedFoot(x, z, pad = 0.35) { for (const isl of ISLANDS) { if (dist2(x, z, isl.x, isl.z) > isl.r * 1.4) continue; for (const s of isl.solids) if (dist2(x, z, s.x, s.z) < s.r + pad) return true; } return false; }
function disembark(p) {
  STATE.mode = 'foot'; STATE.boardDist = Math.max(6, p.d + 3); STATE.walked = 0; foot.x = p.x; foot.z = p.z; foot.y = groundAt(p.x, p.z); foot.yaw = Math.atan2(-(p.x - boat.x), -(p.z - boat.z)); foot.camYaw = foot.yaw;
  foot.group.visible = true; boat.crew.forEach((m) => { m.visible = false; }); boat.speed = 0; AU.sfx('land');
}
function board() { STATE.mode = 'boat'; foot.group.visible = false; boat.crew.forEach((m) => { m.visible = true; }); look.yaw = 0; AU.sfx('board'); }
function takePickup(pk) {
  pk.taken = true; scene.remove(pk.g); scene.remove(pk.spark);
  if (pk.kind === 'branch') STATE.branch++; else STATE.resin++;
  AU.sfx('pickup', STATE.branch + STATE.resin);
}
function makeTorch() { STATE.branch -= 1; STATE.resin -= 1; STATE.torch = true; foot.torchMesh.visible = true; AU.sfx('torch'); }
function lightLantern(ln, i) { ln.lit = 0.001; STATE.lanterns++; AU.sfx('lantern', i); }
function currentAction() {
  if (!STATE.started || STATE.cine) return null;
  if (STATE.mode === 'boat') { const p = findLanding(); return p ? { label: TXT.aLand, run: () => disembark(p) } : null; }
  for (const pk of PICKUPS) if (!pk.taken && dist2(foot.x, foot.z, pk.x, pk.z) < 2.6) return { label: pk.kind === 'branch' ? TXT.aBranch : TXT.aResin, run: () => takePickup(pk) };
  if (STATE.torch && STATE.goal >= 1) for (const ln of LANTERNS) if (!ln.lit && dist2(foot.x, foot.z, ln.x, ln.z) < 3) return { label: TXT.aLantern, run: () => lightLantern(ln, ln._i) };
  const g = GOALS[STATE.goal];
  if (g && !g.beacon.lit && STATE.torch && dist2(foot.x, foot.z, g.beacon.base.x, g.beacon.base.z) < 5.5) {
    const ready = STATE.goal === 0 ? STATE.branch >= 2 : STATE.lanterns >= LANTERNS.length;
    if (ready) return { label: TXT.aBeacon, run: () => lightBeacon(STATE.goal) };
  }
  if (!STATE.torch && STATE.branch >= 3 && STATE.resin >= 1) return { label: TXT.aTorch, run: makeTorch };
  if (STATE.walked > 5 && dist2(foot.x, foot.z, boat.x, boat.z) < (STATE.boardDist || 6)) return { label: TXT.aBoard, run: board };
  return null;
}
function tryAction() { const a = currentAction(); if (a) a.run(); }
function lightBeacon(i) {
  const g = GOALS[i]; if (!g || g.beacon.lit > 0) return;
  const sx = sunDir.x, sz = sunDir.z, sl = Math.hypot(sx, sz) || 1; let px = -sz / sl, pz = sx / sl; // horizontal perpendicular to the sun
  const who = STATE.mode === 'foot' ? { x: foot.x, z: foot.z } : { x: boat.x, z: boat.z };
  if (px * (who.x - g.beacon.fire.x) + pz * (who.z - g.beacon.fire.z) < 0) { px = -px; pz = -pz; }
  const offset = new THREE.Vector3(px * 22 - sx / sl * 7, -2.5, pz * 22 - sz / sl * 7);
  STATE.cine = { t: 0, dur: 5.5, i, from: camera.position.clone(), target: g.beacon.fire.clone(), offset };
  g.beacon.lit = 0.001; if (i === 0) STATE.branch -= 2;
  AU.swell(i + 1);
}
function finishLighting(i) {
  STATE.goal = i + 1; STATE.chapter = i + 1; setChapter(i + 1); AU.level = i + 1;
  if (i === 1) STATE.endAt = STATE.time + 9; // let the night fall and the aurora rise first
}
function goalInfo() { // what to tell the player and where the compass points
  const onA = STATE.mode === 'foot' && islandAt(foot.x, foot.z) === islA, onB = STATE.mode === 'foot' && islandAt(foot.x, foot.z) === islB;
  const beaconT = (g) => ({ x: g.beacon.fire.x, z: g.beacon.fire.z, label: TXT.tBeacon });
  const boatT = { x: boat.x, z: boat.z, label: TXT.tBoat };
  if (STATE.goal >= 2) return { text: TXT.gFree, target: null };
  if (STATE.goal === 0) {
    if (STATE.mode === 'boat') return { text: dist2(boat.x, boat.z, LA.sea.x, LA.sea.z) < 30 && findLanding() ? TXT.gLandA : TXT.gSailA, target: beaconT(GOALS[0]) };
    if (!onA) return { text: TXT.gBackToA, target: boatT };
    if (!STATE.torch) {
      if (STATE.branch >= 3 && STATE.resin >= 1) return { text: TXT.gCraft, target: null };
      const left = PICKUPS.filter((p) => !p.taken).sort((a, b) => dist2(foot.x, foot.z, a.x, a.z) - dist2(foot.x, foot.z, b.x, b.z))[0];
      return { text: TXT.gGather(STATE.branch, STATE.resin), target: left ? { x: left.x, z: left.z, label: left.kind === 'branch' ? TXT.tBranch : TXT.tResin } : null };
    }
    return { text: TXT.gClimbA, target: beaconT(GOALS[0]) };
  }
  // goal 1
  if (STATE.mode === 'boat') return { text: dist2(boat.x, boat.z, LB.sea.x, LB.sea.z) < 30 && findLanding() ? TXT.gLandB : TXT.gSailB, target: beaconT(GOALS[1]) };
  if (!onB) return { text: onA ? TXT.gReturnA : TXT.gSailB, target: boatT };
  if (!STATE.torch) return { text: TXT.gNoFire, target: boatT };
  if (STATE.lanterns < LANTERNS.length) { const ln = LANTERNS.filter((l) => !l.lit).sort((a, b) => dist2(foot.x, foot.z, a.x, a.z) - dist2(foot.x, foot.z, b.x, b.z))[0]; return { text: TXT.gLanterns(STATE.lanterns), target: { x: ln.x, z: ln.z, label: TXT.tLantern } }; }
  return { text: TXT.gClimbB, target: beaconT(GOALS[1]) };
}

// ------------------------------------------------------------------ walking
function updateFoot(dt, fwd, trn, sprint) {
  foot.camYaw += trn * 1.9 * dt;
  const want = fwd * (sprint ? 7 : 4.2);
  foot.speed = lerp(foot.speed, want, 1 - Math.exp(-dt * 8));
  if (Math.abs(foot.speed) > 0.05) {
    const dirX = -Math.sin(foot.camYaw) * Math.sign(foot.speed), dirZ = -Math.cos(foot.camYaw) * Math.sign(foot.speed);
    const stepLen = Math.abs(foot.speed) * dt;
    const tryMove = (nx, nz) => { const h = groundAt(nx, nz); if (h < -0.35) return false; if (h - foot.y > stepLen * 1.6 + 0.08) return false; if (blockedFoot(nx, nz)) return false; foot.x = nx; foot.z = nz; return true; };
    const ox = foot.x, oz = foot.z;
    if (!tryMove(foot.x + dirX * stepLen, foot.z + dirZ * stepLen)) { tryMove(foot.x + dirX * stepLen, foot.z) || tryMove(foot.x, foot.z + dirZ * stepLen); }
    STATE.walked += dist2(ox, oz, foot.x, foot.z);
    const targetYaw = Math.atan2(-dirX, -dirZ); let dy = targetYaw - foot.yaw; while (dy > Math.PI) dy -= 2 * Math.PI; while (dy < -Math.PI) dy += 2 * Math.PI; foot.yaw += dy * (1 - Math.exp(-dt * 10));
    foot.step += Math.abs(foot.speed) * dt * 2.2;
    if (Math.floor(foot.step / Math.PI) !== Math.floor((foot.step - Math.abs(foot.speed) * dt * 2.2) / Math.PI)) AU.sfx('step');
  } else foot.step = lerp(foot.step, Math.round(foot.step / Math.PI) * Math.PI, 1 - Math.exp(-dt * 6));
  foot.y = lerp(foot.y, Math.max(groundAt(foot.x, foot.z), -0.3), 1 - Math.exp(-dt * 14));
  const sw = Math.sin(foot.step) * 0.55 * clamp(Math.abs(foot.speed) / 4, 0, 1);
  foot.legs[0].rotation.x = sw; foot.legs[1].rotation.x = -sw;
  foot.group.position.set(foot.x, foot.y + Math.abs(Math.sin(foot.step)) * 0.05, foot.z); foot.group.rotation.y = foot.yaw;
  foot.arm.rotation.x = STATE.torch ? -0.9 + Math.sin(STATE.time * 2) * 0.03 : -sw * 0.6;
  if (STATE.torch) { foot.torchTip.set(0, 0.25, -0.62); foot.arm.localToWorld(foot.torchTip); foot.torchLight.intensity = 10 + 3 * Math.sin(STATE.time * 13) + 2 * Math.random(); if (Math.random() < 0.8) spawnFire(foot.torchTip, 1, 0.3, 0.15); }
  else foot.torchLight.intensity = 0;
}

// ------------------------------------------------------------------ main loop
const clock = new THREE.Clock();
const camTarget = new THREE.Vector3(), tmp = new THREE.Vector3();
boat.pos3.set(boat.x, 0, boat.z);
applyPalette(0); palT = 1;
function frame() {
  const dt = window.__DT || Math.min(0.05, clock.getDelta()); /* __DT: fixed step for headless tests */ STATE.time += dt; const t = STATE.time;
  // fog clings to islands whose beacon is still dark
  const ownIsl = STATE.mode === 'foot' ? islandAt(foot.x, foot.z) : null;
  const unlitIsland = ownIsl && ((ownIsl === islA && !beaconA.lit) || (ownIsl === islB && !beaconB.lit));
  fogBoost = lerp(fogBoost, unlitIsland ? 2.3 : ownIsl === home ? 1.2 : 1, 1 - Math.exp(-dt * 0.8));
  applyPalette(dt);
  // input
  let fwd = 0, trn = 0;
  const sprint = keys.has('ShiftLeft') || keys.has('ShiftRight') || (joy.active && Math.hypot(joy.x, joy.y) > 0.95);
  if (STATE.started && !STATE.cine) {
    if (keys.has('KeyW') || keys.has('ArrowUp')) fwd += 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) fwd -= 0.5;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) trn += 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) trn -= 1;
    if (joy.active) { fwd += clamp(-joy.y, -0.5, 1); trn -= joy.x; }
    if (window.__AUTO) { fwd = window.__AUTO.fwd; trn = window.__AUTO.trn; }
  }
  fwd = clamp(fwd, -0.5, 1); trn = clamp(trn, -1, 1);
  if (STATE.mode === 'foot') { updateFoot(dt, fwd, trn, sprint); fwd = 0; trn = 0; }
  // boat (anchored while you walk)
  boat.speed = lerp(boat.speed, fwd * 9, 1 - Math.exp(-dt * (fwd ? 0.7 : 0.45)));
  boat.turn = lerp(boat.turn, trn, 1 - Math.exp(-dt * 3));
  boat.yaw += boat.turn * dt * (0.35 + 0.5 * Math.min(1, Math.abs(boat.speed) / 5));
  const nx = boat.x - Math.sin(boat.yaw) * boat.speed * dt, nz = boat.z - Math.cos(boat.yaw) * boat.speed * dt;
  if (!collide(nx, nz) && Math.hypot(nx, nz + 150) < 520) { boat.x = nx; boat.z = nz; } else boat.speed *= -0.25;
  const h = wave(boat.x, boat.z, t);
  const hx = wave(boat.x + 1, boat.z, t) - wave(boat.x - 1, boat.z, t), hz = wave(boat.x, boat.z + 1, t) - wave(boat.x, boat.z - 1, t);
  boat.pos3.set(boat.x, h, boat.z);
  boat.group.position.copy(boat.pos3);
  boat.group.rotation.set(0, boat.yaw, 0);
  boat.group.rotateX(clamp(hz * Math.cos(boat.yaw) + hx * Math.sin(boat.yaw), -0.25, 0.25) * 0.6);
  boat.group.rotateZ(clamp(-hx * Math.cos(boat.yaw) + hz * Math.sin(boat.yaw), -0.25, 0.25) * 0.6 - boat.turn * 0.06);
  boat.sail.scale.z = 0.7 + 0.3 * Math.sin(t * 1.3) + Math.min(1, Math.abs(boat.speed) / 9) * 0.4;
  // the player's light
  if (STATE.mode === 'boat') { BEACONS[0].set(boat.x, boat.z, 16, 0.55); BEACONS[7].set(0, 0, 0, 0); }
  else { BEACONS[0].set(foot.x, foot.z, STATE.torch ? 13 : 4, STATE.torch ? 0.92 : 0.25); BEACONS[7].set(boat.x, boat.z, 10, 0.4); }
  // sea follows the viewer on a grid (waves are computed in world space)
  const gstep = SEA_SIZE / SEA_SEG; sea.position.set(Math.round(camera.position.x / gstep) * gstep, 0, Math.round(camera.position.z / gstep) * gstep);
  seaU.uTime.value = t; seaU.uCam.value.copy(camera.position); seaU.uDeep.value.copy(cur.deep); seaU.uShallow.value.copy(cur.shal); seaU.uSun.value.copy(cur.sun).multiplyScalar(cur.night ? 0.4 : 1);
  seaU.uFogColor.value.copy(cur.fog); seaU.uFogDensity.value = cur.dens * fogBoost;
  skyU.uHorizon.value.copy(cur.fog); skyU.uZenith.value.copy(cur.zen); skyU.uSun.value.copy(cur.sun); skyU.uNight.value = cur.night; skyU.uTime.value = t;
  aurU.uTime.value = t; aurU.uAmt.value = cur.aur; aurora.visible = cur.aur > 0.01;
  sky.position.copy(camera.position); aurora.position.set(camera.position.x, 0, camera.position.z);
  // beacons: fire, light, fog clearing
  GOALS.forEach((g, k) => {
    const b = g.beacon;
    if (b.lit > 0) {
      b.lit = Math.min(1, b.lit + dt / 3.5);
      b.light.intensity = (110 + 35 * Math.sin(t * 17 + k) + 25 * Math.random()) * b.lit * (1 - 0.45 * cur.night);
      if (Math.random() < 0.9) spawnFire(b.fire, 2);
      BEACONS[g.slot].set(b.fire.x, b.fire.z, 110 * smooth(0, 1, b.lit), 0.95 * b.lit);
      (k === 0 ? glowA : glowB).material.opacity = b.lit * (0.25 + 0.45 * cur.night) * (0.9 + 0.1 * Math.sin(t * 9));
      (k === 0 ? seaU.uGlow : seaU.uGlow2).value.set(b.fire.x, b.fire.z, 0, b.lit * (0.1 + 0.45 * cur.night));
    }
  });
  // path lanterns
  LANTERNS.forEach((ln, i) => {
    if (ln.lit > 0) {
      ln.lit = Math.min(1, ln.lit + dt / 1.2);
      ln.light.intensity = (7 + 1.5 * Math.sin(t * 11 + i)) * ln.lit;
      ln.glass.emissive.setRGB(1.0 * ln.lit, 0.55 * ln.lit, 0.18 * ln.lit);
      BEACONS[4 + i].set(ln.x, ln.z, 24 * smooth(0, 1, ln.lit), 0.9 * ln.lit);
      if (Math.random() < 0.25) spawnFire(ln.tip, 1, 0.12, 0.08);
    }
  });
  // pickups glimmer; the will-o'-wisp hangs over the next beacon
  PICKUPS.forEach((pk, i) => { if (!pk.taken) { pk.spark.position.y = pk.y + 1.3 + Math.sin(t * 2 + i) * 0.15; pk.spark.material.opacity = (0.55 + 0.35 * Math.sin(t * 3 + i * 1.7)) * smooth(60, 20, dist2(camera.position.x, camera.position.z, pk.x, pk.z)); } });
  const cg = GOALS[STATE.goal];
  if (cg && cg.beacon.lit === 0) { hint.visible = true; hint.position.copy(cg.beacon.fire).add(new THREE.Vector3(0, 1 + Math.sin(t * 1.5) * 0.6, 0)); hint.material.opacity = 0.35 + 0.25 * Math.sin(t * 2.2); } else hint.visible = false;
  // chimney smoke and the izba light
  if (Math.random() < dt * 3) spawnSmoke(izba.chimney);
  izba.light.intensity = 26 + 6 * Math.sin(t * 7) + 3 * Math.random();
  for (let i = fireParts.length - 1; i >= 0; i--) { const p = fireParts[i]; p.life += dt; const k = p.life / p.max; p.s.position.y += p.vy * dt; p.s.material.opacity = Math.min(1, (1 - k) * 1.4); p.s.scale.setScalar((1 - k * 0.55) * p.size); p.s.material.color.setHSL(0.11 - k * 0.09, 1, 0.62 - k * 0.22); if (k >= 1) { scene.remove(p.s); p.s.material.dispose(); fireParts.splice(i, 1); } }
  for (let i = smokeParts.length - 1; i >= 0; i--) { const p = smokeParts[i]; p.life += dt; const k = p.life / p.max; p.s.position.y += 1.1 * dt; p.s.position.x += 0.6 * dt; p.s.scale.setScalar(1.2 + k * 5); p.s.material.opacity = 0.3 * (1 - k); if (k >= 1) { scene.remove(p.s); p.s.material.dispose(); smokeParts.splice(i, 1); } }
  // fog wisps drift and are recycled around the viewer; they thin out near lit fires
  const vx = camera.position.x, vz = camera.position.z;
  for (const w of wisps) {
    w.position.x += 1.2 * dt; if (w.position.x - vx > 160) w.position.x -= 320; if (w.position.x - vx < -160) w.position.x += 320; if (w.position.z - vz > 160) w.position.z -= 320; if (w.position.z - vz < -160) w.position.z += 320;
    let clearF = 1; for (let i = 1; i < NSLOT; i++) { const b = BEACONS[i]; if (b.w > 0) clearF = Math.min(clearF, lerp(1, smooth(b.z * 0.3, b.z, Math.hypot(w.position.x - b.x, w.position.z - b.y)), b.w)); }
    w.material.opacity = 0.11 * clearF * (cur.night ? 0.35 : 1) * smooth(8, 30, Math.hypot(w.position.x - vx, w.position.z - vz)) * (STATE.mode === 'foot' ? 1.3 : 1);
    w.material.color.copy(cur.fog).lerp(new THREE.Color(0xffffff), 0.25);
  }
  // camera
  if (STATE.cine) {
    const c = STATE.cine; c.t += dt; const k = smooth(0, 1, Math.min(1, c.t / 2.2)), back = smooth(c.dur - 1.6, c.dur, c.t);
    const shot = tmp.copy(c.target).add(c.offset);
    camTarget.copy(c.target).lerp(viewTarget(), back);
    camera.position.lerpVectors(c.from, shot, k * (1 - back)).lerp(desiredCam(), back);
    camera.lookAt(camTarget);
    if (c.t > 1.0 && c.t - dt <= 1.0) GOALS[c.i].beacon.lit = Math.max(GOALS[c.i].beacon.lit, 0.01);
    if (c.t >= c.dur) { STATE.cine = null; finishLighting(c.i); }
  } else {
    if (!STATE.started) { look.yaw = 2.55 + Math.sin(t * 0.06) * 0.4; look.pitch = 0.26; }
    else if (STATE.mode === 'boat' && !look.dragging) { look.idle += dt; if (look.idle > 2.5) look.yaw = lerp(look.yaw, 0, 1 - Math.exp(-dt * 0.8)); }
    camera.position.lerp(desiredCam(), 1 - Math.exp(-dt * (STATE.mode === 'foot' ? 6 : 4)));
    camTarget.lerp(viewTarget(), 1 - Math.exp(-dt * 6));
    camera.lookAt(camTarget);
  }
  if (STATE.endAt && STATE.time >= STATE.endAt) { STATE.endAt = 0; STATE.ended = true; $('#end').classList.add('on'); }
  updateHud();
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}
function viewTarget() { return STATE.mode === 'foot' ? new THREE.Vector3(foot.x, foot.y + 1.6, foot.z) : new THREE.Vector3(boat.pos3.x, boat.pos3.y + 2.2, boat.pos3.z); }
function terrainAt(x, z) { return groundAt(x, z); }
function desiredCam() {
  if (STATE.mode === 'foot') {
    const yaw = foot.camYaw, sx = Math.sin(yaw), sz = Math.cos(yaw), base = foot.y + 1.7 + look.pitch * 7;
    let dist = 7, hgt = base;
    for (let d = 1.5; d <= 7; d += 0.75) { const hh = terrainAt(foot.x + sx * d, foot.z + sz * d); if (hh + 1.2 > hgt) { if (hh + 1.2 <= base + 3) hgt = hh + 1.2; else { dist = Math.max(2, d - 0.8); break; } } }
    // pull in before a tree crown or the boat that stands between the player and the camera
    const occ = [];
    const isl = islandAt(foot.x, foot.z); if (isl) for (const s of isl.solids) if (dist2(s.x, s.z, foot.x, foot.z) < 9) occ.push({ x: s.x, z: s.z, r: Math.max(0.8, s.r * 3.2) });
    for (const o of occ) {
      const along = (o.x - foot.x) * sx + (o.z - foot.z) * sz; if (along <= 0.5 || along > dist + o.r) continue;
      const side = Math.abs((o.x - foot.x) * sz - (o.z - foot.z) * sx);
      if (side < o.r) dist = Math.max(1.8, Math.min(dist, along - Math.sqrt(o.r * o.r - side * side) - 0.3));
    }
    if (dist < 4) hgt = Math.max(hgt, foot.y + 2.4 + (4 - dist) * 0.35);
    // the moored boat: look over its sail instead of through it
    const cx = foot.x + sx * dist, cz = foot.z + sz * dist;
    const bAlong = (boat.x - foot.x) * sx + (boat.z - foot.z) * sz, bSide = Math.abs((boat.x - foot.x) * sz - (boat.z - foot.z) * sx);
    if ((bAlong > 0 && bAlong < dist + 3 && bSide < 3.2) || dist2(cx, cz, boat.x, boat.z) < 3.5) hgt = Math.max(hgt, boat.pos3.y + 6.2);
    return new THREE.Vector3(foot.x + sx * dist, hgt, foot.z + sz * dist);
  }
  const yaw = boat.yaw + look.yaw, sx = Math.sin(yaw), sz = Math.cos(yaw), base = Math.max(boat.pos3.y + 2, 3 + look.pitch * 12);
  let dist = 15, hgt = base;
  for (let d = 3; d <= 15; d += 1.5) {
    const hh = terrainAt(boat.x + sx * d, boat.z + sz * d); if (hh < -0.3) continue;
    const need = hh + 7.5; // trees stand on land: clear their crowns
    if (need <= base + 7) hgt = Math.max(hgt, need); else { dist = Math.max(4.5, d - 2); break; }
  }
  return new THREE.Vector3(boat.x + sx * dist, hgt, boat.z + sz * dist);
}
function updateHud() {
  if (!STATE.started) return;
  const info = goalInfo(), comp = $('#compass');
  const goalEl = $('#goal'); if (goalEl.textContent !== info.text) goalEl.textContent = info.text;
  if (info.target && !STATE.cine) {
    const dir = new THREE.Vector3(); camera.getWorldDirection(dir);
    const camYaw = Math.atan2(dir.x, dir.z), tgtYaw = Math.atan2(info.target.x - camera.position.x, info.target.z - camera.position.z);
    let a = tgtYaw - camYaw; while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI;
    comp.style.display = 'block';
    $('#mark').style.left = (50 - clamp(a / (Math.PI / 2), -1, 1) * 46) + '%';
    const me = STATE.mode === 'foot' ? foot : boat;
    $('#dist').textContent = `${info.target.label}: ${Math.round(dist2(info.target.x, info.target.z, me.x, me.z))} ${TXT.m}`;
  } else comp.style.display = 'none';
  const act = currentAction(), btn = $('#actBtn');
  if (act) { const html = act.label + (isTouch ? '' : ' <kbd>E</kbd>'); if (btn.innerHTML !== html) btn.innerHTML = html; }
  btn.classList.toggle('on', !!act);
}
function fitCamera() { renderer.setSize(window.innerWidth, window.innerHeight); camera.aspect = window.innerWidth / window.innerHeight; camera.fov = camera.aspect < 1 ? 72 : 58; camera.updateProjectionMatrix(); }
window.addEventListener('resize', fitCamera); fitCamera();
camera.position.copy(desiredCam()); camTarget.copy(boat.pos3);
frame();
// debug / test hooks
window.FOG = {
  STATE, boat, foot, GOALS, ISLANDS, PICKUPS, LANTERNS, izba, look, LA, LB, lightBeacon, act: tryAction, action: () => { const a = currentAction(); return a ? a.label : null; },
  teleport(x, z, yaw) { boat.x = x; boat.z = z; if (yaw !== undefined) boat.yaw = yaw; if (STATE.mode === 'boat') camera.position.copy(desiredCam()); },
  walkTo(x, z, yaw) { foot.x = x; foot.z = z; foot.y = groundAt(x, z); if (yaw !== undefined) { foot.camYaw = yaw; foot.yaw = yaw; } camera.position.copy(desiredCam()); },
  goal: () => goalInfo().text,
};
