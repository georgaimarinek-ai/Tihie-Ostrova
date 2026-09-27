// Автопрогон наброска: высадка, факел, маяк, лодка, фонари, второй маяк, ночь. npm run play [-- phone]
// Проверяет, что весь путь проходится без ошибок, и сохраняет скриншоты в shots/.
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
const phone = process.argv.includes('phone');
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const ctx = await browser.newContext(phone ? { viewport: { width: 412, height: 915 }, hasTouch: true, isMobile: true, locale: 'ru-RU' } : { viewport: { width: 1280, height: 720 }, locale: 'ru-RU' });
const page = await ctx.newPage();
const errors = []; page.on('pageerror', (e) => errors.push(e.message)); page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_TUNNEL')) errors.push(m.text()); });
await page.addInitScript(() => { window.__DT = 0.25; });
const file = fs.existsSync('dist/fog-isles-standalone.html') ? 'dist/fog-isles-standalone.html' : 'fog-isles-standalone.html';
await page.goto('file://' + path.resolve(file));
fs.mkdirSync('shots', { recursive: true });
const P = phone ? 'shots/pp_' : 'shots/p_';
const ev = (f, a) => page.evaluate(f, a);
const sim = () => ev(() => window.FOG.STATE.time);
async function waitSim(sec) { const t0 = await sim(); for (let i = 0; i < 400; i++) { await page.waitForTimeout(200); if ((await sim()) - t0 >= sec) return; } }
const shot = async (n) => { await page.screenshot({ path: P + n + '.png' }); };
const log = async (label) => console.log(label.padEnd(14), JSON.stringify(await ev(() => ({ mode: FOG.STATE.mode, action: FOG.action(), goal: FOG.goal(), torch: FOG.STATE.torch, b: FOG.STATE.branch, r: FOG.STATE.resin, l: FOG.STATE.lanterns, g: FOG.STATE.goal }))));
const act = async () => { await ev(() => FOG.act()); await waitSim(0.3); };
await page.click('#startBtn');
await waitSim(1);
// 1. sail to island A
await ev(() => { const L = FOG.LA, b = FOG.GOALS[0].beacon.fire; FOG.teleport(L.sea.x, L.sea.z, Math.atan2(-(b.x - L.sea.x), -(b.z - L.sea.z))); });
await waitSim(2); await log('near A'); await shot('01_shoreA');
await act(); await waitSim(2.5); await log('landed'); await shot('02_landed_fog');
// walking works
const p0 = await ev(() => [FOG.foot.x, FOG.foot.z]);
await ev(() => { window.__AUTO = { fwd: 1, trn: 0 }; }); await waitSim(1.5); await ev(() => { window.__AUTO = null; });
const p1 = await ev(() => [FOG.foot.x, FOG.foot.z]);
console.log('walked', Math.hypot(p1[0] - p0[0], p1[1] - p0[1]).toFixed(1), 'm');
// 2. gather
for (let i = 0; i < 4; i++) { await ev((i) => { const pk = FOG.PICKUPS[i]; FOG.walkTo(pk.x + 1.2, pk.z + 0.5); }, i); await waitSim(0.5); await log('at pickup ' + i); await act(); }
await log('gathered'); await act(); await waitSim(1.5); await log('torch'); await shot('03_torch');
// 3. beacon A
await ev(() => { const b = FOG.GOALS[0].beacon.base, L = FOG.LA; FOG.walkTo(b.x + L.ux * 3.5, b.z + L.uz * 3.5, Math.atan2(L.ux, L.uz)); });
await waitSim(1); await log('at beacon A'); await shot('04_beaconA_base');
await act(); await waitSim(2.5); await shot('05_cineA'); await waitSim(5); await log('after A'); await shot('06_afterA');
// 4. back to the boat
await ev(() => { const L = FOG.LA; FOG.walkTo(L.shore.x, L.shore.z); }); await waitSim(0.5); await log('at shore'); await act(); await log('boarded');
// 5. island B
await ev(() => { const L = FOG.LB, b = FOG.GOALS[1].beacon.fire; FOG.teleport(L.sea.x, L.sea.z, Math.atan2(-(b.x - L.sea.x), -(b.z - L.sea.z))); });
await waitSim(1.5); await log('near B'); await act(); await waitSim(1.5); await log('landed B'); await shot('07_landedB');
for (let i = 0; i < 3; i++) { await ev((i) => { const l = FOG.LANTERNS[i]; FOG.walkTo(l.x + 1.4, l.z + 0.6); }, i); await waitSim(0.5); await act(); await waitSim(1.2); if (i === 1) await shot('08_lanterns'); }
await log('lanterns');
await ev(() => { const b = FOG.GOALS[1].beacon.base, L = FOG.LB; FOG.walkTo(b.x + L.ux * 3.5, b.z + L.uz * 3.5, Math.atan2(L.ux, L.uz)); });
await waitSim(0.5); await log('at beacon B'); await act(); await waitSim(7); await shot('09_afterB'); await waitSim(8); await log('end'); await shot('10_night_end');
console.log('end card', await ev(() => document.querySelector('#end').classList.contains('on')), 'errors', errors.length ? errors : 'none');
await browser.close();
