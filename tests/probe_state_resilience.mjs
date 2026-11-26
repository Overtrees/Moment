// 专用探针：状态污染恢复（毒化电池）——localStorage /
// IndexedDB 存量被写坏、旧形态残留、值类型错乱时，应用
// 仍能启动恢复、不 trap、不丢可恢复数据。
//
// 立项背景：2026-11-24 两起生产故障（启动 trap 点击全
// 死、存量旧形整库判死）都源于「盘上状态与新构建预期不
// 一致」；当时判据未定案（只留下要点：深色 + 种子已迁
// 移态 + 断言无 ERR 行）而搁置。本探针把判据定案如下
// （每条都以现行代码的容错路径为据，见各场景注）：
//
// 已迁移态存量（现行构建自身落盘的原生形：
// version=2、字符串 id、ISO 时间戳、原生节点形），3 篇
// 跨三天分组（避同组折叠），manifest_raw 为原生空形。
//
//
// R1 Diag 落 loaded persisted memos + persisted state
// applied；页面无「备忘加载失败」、Diag 无 load-
// error 行；
// R2 三篇好备忘在列表可见（标题/正文标记逐篇核）；
// R3 真实 tap 首篇好备忘 → EDIT page enter 且 EDIT
// open 身份核验（非仅可解析、是可用）；
// R4 无 error 级 Diag 行（判读与 diag::line_level 同
// 口径：'] ERR ' / '] PANIC ' 标签行与 '[时刻 E] '
// 等级标记行均算 error；污染降级应走 info/warn 或
// 结果行）、moment_panic_v1 为空、无含 unreachable
// 的 pageerror（无 wasm trap）；
// R5 应用存活证据照常：moment_boot_ok 本轮刷新、外壳
// 救援快照本轮写出（addInitScript 录 setItem，避
// init drain 先清键的竞态——probe_rescue 同教训）；
// R6 深色口径：全程 colorScheme=dark 且页面内
// matchMedia dark 命中（判据要点之一）。
//
//
// S0 基线无污染（种子自检，R 组全验）。
// S1 Diag 缓冲非 JSON（moment_diag_v1 = 非法串）：
//      diag::init 的 from_str 失败即整表丢弃、空缓冲重
// 启——R 组全验 + 缓冲被重写为合法 JSON 数组。
// S2 Diag 缓冲截断 JSON（写一半的数组串）：同 S1。
// S3 Diag 周边键垃圾：archives 非数组 JSON、day 键
// 垃圾串、level 垃圾值、autodel 垃圾值——读路径
// 分别为 filter_map 逐条丢坏条目 / 任意串作归属日
// （rotate 至多冻结一份）/ from_key 回落 All /
// 非 "1" 即关，R 组全验。
// S4 外壳暂存键垃圾：swupd_pending / rescue_log /
// panic 三键坏值——drain 均先删键后解析、失败静
// 默，R 组全验 + 三键终态（swupd/panic 已清、
// rescue_log 被外壳快照重写）+ 无 PANIC 行折入。
// S5 偏好键垃圾组：lang/pack 缓存/imgsize 缓存/
// backup_history/pending_input/slash_recent/
// sj_fontsize/sj_editor_independent_scroll/
// weather_cache/hint——读路径逐个为回落默认或整
// 键作废，R 组全验。
// S6 备忘旧形字段混入（迁移通道兜底面）：一篇备忘
// 数字 id + 毫秒戳 + title 数字 + pinned 字符串
// + deletedAt 垃圾串——normalize_value 归一（id/
// 戳转串、标量错类型剔除），R 组全验 + MIGRATE
// d3 行在场（num_id/millis_ts/fields_norm 达阈）
// + 写回后该篇 id 已收敛为字符串。
// S7 单篇坏行组（逐子场景独立 boot）：好篇中混入
// 一行坏备忘——a memos 含非对象条目 / b doc 为
// 字符串 / c createdAt 为布尔 / d 缺 id / e 节
// 点 children 为对象。判据（用户口径）：单篇坏
// 行不应整库判死——好篇须照常加载、可见、可打开
// （坏行被剔除或被消毒均可，不锁篇数），R2/R3
// 只对好篇验，R1 改验「无 load-error + 页面无加
// 载失败 + 好篇 loaded 迹象（标题可见）」。
// S8 全损保全组（逐子场景）：memos_json 整体不可
// 恢复——a 非 JSON 串 / b 根为数组。此类按设计
// 走既有失败态（代码注「真损坏走既有失败态」），
// 断言改为保全组：P1 失败态呈现（页面有「备忘加
// 载失败」+ Diag 有 parse err 行）；P2 IDB 内
// memos_json 与种子逐字一致（一行不动、不被种
// 子覆盖）；P3 无 trap（R4 同口径）；P4 存活证
// 据照常（R5 同口径，失败态是健康应用状态）。
// S9 manifest_raw 垃圾串：消费面 from_str().ok()
// 容错（封面派生取不到即无封面），R 组全验。
//
// S7 任一子场景红 = 整库判死类真缺陷，
// 本探针如实判红、不放宽判据；S8 的失败态是设计口
// 径、不算缺陷。Chromium/WebKit 无头口径，iOS 专有
// 面（如 IDB 配额）不在本探针射程。
//
// 用法：node probe_state_resilience.mjs [distDir]
// 默认 rust/apps/web/dist；自带静态服务（需同源种子页）。
import { webkit} from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath} from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
let distDir = path.join(root, '..', 'rust', 'apps', 'web', 'dist');
if (process.argv[2] &&!process.argv[2].startsWith('http')) {
distDir = path.resolve(process.argv[2]);
}
const PORT = 8173;
const BASE = `http://localhost:${PORT}/`;
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond? '✓': '✗ FAIL', name, extra); if (!cond) fails++;};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── 种子：已迁移态存量（原生形）──────────────────────
const iso = (msAgo) => new Date(Date.now() - msAgo).toISOString();
const DAY = 86_400_000;
function goodStock() {
return {
version: 2,
memos: [
{
id: 'res_alpha', title: '韧性甲篇', pinned: false,
createdAt: iso(1 * DAY), updatedAt: iso(1 * DAY),
doc: [{ type: 'paragraph', id: 'ra1', children: [{ text: 'RESILIENCE-ALPHA 甲篇正文'}]}],
},
{
id: 'res_beta', title: '韧性乙篇', pinned: false,
createdAt: iso(2 * DAY), updatedAt: iso(2 * DAY),
doc: [{ type: 'paragraph', id: 'rb1', children: [{ text: 'RESILIENCE-BETA 乙篇正文'}]}],
},
{
id: 'res_gamma', title: '韧性丙篇', pinned: false,
createdAt: iso(3 * DAY), updatedAt: iso(3 * DAY),
doc: [{ type: 'paragraph', id: 'rg1', children: [{ text: 'RESILIENCE-GAMMA 丙篇正文'}]}],
},
],
};
}
const MANIFEST = '{"version":1,"attachments":{}}';

// ── 静态服务 + 可变种子页 ─────────────────────────────
let currentSeed = { ls: {}, memosJson: '', manifestRaw: MANIFEST};
const seedHtml = () => `<!doctype html><meta charset="utf-8"><script>
const LS = ${JSON.stringify(currentSeed.ls)};
for (const k of Object.keys(LS)) localStorage.setItem(k, LS[k]);
const memos = ${JSON.stringify(currentSeed.memosJson)};
const manifest = ${JSON.stringify(currentSeed.manifestRaw)};
const req = indexedDB.open('mynote-web', 1);
req.onupgradeneeded = () => { const db = req.result; db.createObjectStore('kv'); db.createObjectStore('attachments');};
req.onsuccess = () => {
const db = req.result;
const tx = db.transaction('kv', 'readwrite');
tx.objectStore('kv').put(memos, 'memos_json');
tx.objectStore('kv').put(manifest, 'manifest_raw');
tx.oncomplete = () => location.replace('/');
};
</script>seeding`;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css'};
const server = http.createServer((req, res) => {
let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
res.setHeader('Cache-Control', 'no-store');
if (p === '/__seed.html') { res.writeHead(200, { 'Content-Type': 'text/html'}); res.end(seedHtml()); return;}
if (p === '/') p = '/index.html';
const fp = path.join(distDir, p);
if (!fp.startsWith(distDir) ||!fs.existsSync(fp) || fs.statSync(fp).isDirectory()) { res.writeHead(404); res.end('nf'); return;}
res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'application/octet-stream'});
fs.createReadStream(fp).pipe(res);
});
await new Promise((r) => server.listen(PORT, r));

// error 级行判读（diag::line_level 同口径）
const isErrLine = (l) => l.includes('] ERR ') || l.includes('] PANIC ') || /\[\d{2}:\d{2}:\d{2} E\]/.test(l);

// 一次完整 boot：新 profile（隔离污染）→ 种子页 → 应用。
async function boot(seed) {
currentSeed = seed;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'resil-'));
const ctx = await webkit.launchPersistentContext(dir, {
viewport: { width: 393, height: 852},
colorScheme: 'dark',
hasTouch: true,
userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Mobile/15E148 Safari/604.1',
});
const page = ctx.pages()[0] || (await ctx.newPage());
const pageErrors = [];
page.on('pageerror', (e) => pageErrors.push(String(e)));
// 救援快照写入录制（外壳经 localStorage.setItem 写
// moment_rescue_log_v1；应用 init 的 drain 会删键，
// 事后读键必竞态——录制写入流本身）。
await ctx.addInitScript(() => {
window.__rescueWrites = [];
const orig = Storage.prototype.setItem;
Storage.prototype.setItem = function (k, v) {
if (k === 'moment_rescue_log_v1') {
try { window.__rescueWrites.push(String(v));} catch (e) {}
}
return orig.apply(this, arguments);
};
});
const bootStart = Date.now();
await page.goto(BASE + '__seed.html', { waitUntil: 'load'}).catch(() => {});
const readDiag = async () => page.evaluate(() => localStorage.getItem('moment_diag_v1') || '').then((s) => {
try { const v = JSON.parse(s); return Array.isArray(v)? v: String(s).split('\n');} catch { return String(s).split('\n');}
}).catch(() => []);
const waitDiag = async (pred, timeout = 15000) => {
const t0 = Date.now();
let lines = [];
while (Date.now() - t0 < timeout) {
lines = await readDiag();
if (pred(lines)) return lines;
await sleep(500);
}
return lines;
};
const lines = await waitDiag((ls) => ls.some((l) => l.includes('persisted state applied') || l.includes('persisted memos_json parse err')), 15000);
const bodyText = await page.evaluate(() => document.body.innerText).catch(() => '');
return { ctx, page, pageErrors, lines, bodyText, readDiag, waitDiag, bootStart};
}

// R4/R5 共用核验（无 trap + 存活证据）。Diag 行现读
// 新鲜集（不用 boot 时的旧快照——tap 后新行入环，旧快
// 照会漏检 tap 期的 ERR/PANIC）。
async function checkAlive(tag, b) {
const { page, pageErrors, bootStart} = b;
const lines = await b.readDiag();
ok(`${tag} 无 error 级 Diag 行`,!lines.some(isErrLine), lines.filter(isErrLine).join(' | ').slice(0, 160));
ok(`${tag} 无 PANIC 行`,!lines.some((l) => l.includes('PANIC')), lines.filter((l) => l.includes('PANIC')).join(' | ').slice(0, 160));
ok(`${tag} moment_panic_v1 为空`,!(await page.evaluate(() => localStorage.getItem('moment_panic_v1')).catch(() => '?')));
ok(`${tag} 无 unreachable pageerror`,!pageErrors.some((e) => /unreachable|RuntimeError/i.test(e)), pageErrors.slice(0, 2).join(' | ').slice(0, 160));
// boot_ok：init 后 2s 存活闭包写，轮询等新鲜值
let bootOkFresh = false;
for (let i = 0; i < 14 &&!bootOkFresh; i++) {
const v = await page.evaluate(() => localStorage.getItem('moment_boot_ok')).catch(() => null);
try { bootOkFresh =!!v && JSON.parse(v).t >= bootStart - 1000;} catch { bootOkFresh = false;}
if (!bootOkFresh) await sleep(500);
}
ok(`${tag} moment_boot_ok 本轮刷新`, bootOkFresh);
const writes = await page.evaluate(() => window.__rescueWrites || []).catch(() => []);
const snapOk = writes.some((w) => {
try {
const a = JSON.parse(w);
return Array.isArray(a) && a.some((e) => e && e.kind === 'snapshot' && Date.parse(e.t) >= bootStart - 1000);
} catch { return false;}
});
ok(`${tag} 救援快照本轮写出`, snapOk, `writes=${writes.length}`);
const dark = await page.evaluate(() => window.matchMedia('(prefers-color-scheme: dark)').matches).catch(() => false);
ok(`${tag} 深色口径在场（matchMedia dark）`, dark === true);
}

// R 组主核验（恢复组）：加载成功 + 好篇可见 + 可打开
async function checkRecovered(tag, b, { expectMemos = 3, tapTitle = '韧性甲篇', tapId = 'res_alpha'} = {}) {
const { page, lines, bodyText} = b;
ok(`${tag} loaded persisted memos=${expectMemos}`, lines.some((l) => l.includes(`loaded persisted memos=${expectMemos}`)), lines.filter((l) => l.includes('loaded persisted')).join(' | ').slice(0, 120));
ok(`${tag} persisted state applied`, lines.some((l) => l.includes('persisted state applied')));
ok(`${tag} 无 parse err`,!lines.some((l) => l.includes('persisted memos_json parse err')));
ok(`${tag} 无 load-error`,!lines.some((l) => l.includes('load-error')));
ok(`${tag} 页面无「备忘加载失败」`,!bodyText.includes('备忘加载失败'));
for (const t of ['韧性甲篇', '韧性乙篇', '韧性丙篇']) {
ok(`${tag} 列表可见「${t}」`, bodyText.includes(t));
}
// 真实 tap 打开首篇（按标题锁定，避新建行误 tap）
const pt = await page.evaluate((title) => {
const els = [...document.querySelectorAll('.img-card,.list-item')];
const el = els.find((e) => e.innerText && e.innerText.includes(title));
if (!el) return null;
const r = el.getBoundingClientRect();
return { x: r.x + r.width / 2, y: r.y + Math.min(r.height / 2, 40)};
}, tapTitle);
ok(`${tag} 「${tapTitle}」卡可定位`,!!pt);
if (pt) {
const off = (await b.readDiag()).length;
if (page.touchscreen) await page.touchscreen.tap(pt.x, pt.y); else await page.mouse.click(pt.x, pt.y);
const ls2 = await b.waitDiag((ls) => ls.slice(off).some((l) => l.includes('EDIT page enter')), 9000);
ok(`${tag} tap 后 EDIT page enter`, ls2.slice(off).some((l) => l.includes('EDIT page enter')));
ok(`${tag} 打开身份 = ${tapId}`, ls2.slice(off).some((l) => l.includes(`EDIT open memo=${tapId}`)));
// 不用 page.goBack() 回列表：应用内导航不落浏览器
// 历史，goBack 会退出应用到不透明源（evaluate 抛
// SecurityError、localStorage 不可读）——存活证据
// 在编辑页内直接验（同源同应用，口径不变）。
}
await checkAlive(tag, b);
}

const readPersisted = (page) => page.evaluate(() => new Promise((resolve) => {
// 组装读（IDB 分条合流适配，只换读取通道、断言不变）：
// memos_json 在则直用（S8 全损保全即此路：不可解析旧形不
// 被迁移、逐字保留）；否则 backup_meta + memos_order +
// memos 店组装回全量 JSON（S6 收敛核验走此路）。
const req = indexedDB.open('mynote-web');
req.onsuccess = () => {
const db = req.result;
const getKv = (k) => new Promise((r2) => { const g = db.transaction('kv', 'readonly').objectStore('kv').get(k); g.onsuccess = () => r2(g.result); g.onerror = () => r2(undefined); });
(async () => {
const legacy = await getKv('memos_json');
if (legacy !== undefined) { resolve(legacy); return; }
const meta = await getKv('backup_meta');
if (!meta) { resolve(''); return; }
const order = JSON.parse((await getKv('memos_order')) || '[]');
const [vals, ks] = await Promise.all([
new Promise((r2) => { const g = db.transaction('memos', 'readonly').objectStore('memos').getAll(); g.onsuccess = () => r2(g.result || []); g.onerror = () => r2([]); }),
new Promise((r2) => { const g = db.transaction('memos', 'readonly').objectStore('memos').getAllKeys(); g.onsuccess = () => r2(g.result || []); g.onerror = () => r2([]); }),
]);
const byId = new Map(ks.map((k, i) => [String(k), vals[i]]));
const root = JSON.parse(meta);
root.memos = order.map((id) => byId.get(String(id))).filter((v) => v !== undefined).map((v) => JSON.parse(v));
resolve(JSON.stringify(root));
})().catch(() => resolve(''));
};
req.onerror = () => resolve('');
})).catch(() => '');

const seedOf = (ls, stock) => ({ ls, memosJson: typeof stock === 'string'? stock: JSON.stringify(stock), manifestRaw: MANIFEST});

// ── S0 基线无污染 ────────────────────────────────────
{
  const b = await boot(seedOf({}, goodStock()));
  await checkRecovered('S0', b);
  await b.ctx.close();
}

// ── S1 Diag 缓冲非 JSON ──────────────────────────────
{
  const b = await boot(seedOf({ moment_diag_v1: 'not-json{{{garbage' }, goodStock()));
  await checkRecovered('S1', b);
  const raw = await b.page.evaluate(() => localStorage.getItem('moment_diag_v1') || '').catch(() => '');
  let valid = false;
  try { valid = Array.isArray(JSON.parse(raw)); } catch { valid = false; }
  ok('S1 Diag 缓冲已被重写为合法 JSON 数组', valid);
  await b.ctx.close();
}

// ── S2 Diag 缓冲截断 JSON ────────────────────────────
{
  const b = await boot(seedOf({ moment_diag_v1: '["[10:00:00] APP start", "[10:00:0' }, goodStock()));
  await checkRecovered('S2', b);
  await b.ctx.close();
}

// ── S3 Diag 周边键垃圾 ───────────────────────────────
{
  const b = await boot(seedOf({
    moment_diag_archives_v1: '{"oops":1}',
    moment_diag_day_v1: 'garbage-day-xx',
    moment_diag_level_v1: 'ultra-max',
    moment_diag_autodel_v1: 'yes-please',
    moment_diag_v1: JSON.stringify(['[09:00:00] APP start (stale)']),
  }, goodStock()));
  await checkRecovered('S3', b);
  await b.ctx.close();
}

// ── S4 外壳暂存键垃圾 ────────────────────────────────
{
  const b = await boot(seedOf({
    moment_swupd_pending_v1: '][bad-json',
    moment_rescue_log_v1: '42',
    moment_panic_v1: '[123,45]',
  }, goodStock()));
  await checkRecovered('S4', b);
  ok('S4 swupd_pending 键已清', !(await b.page.evaluate(() => localStorage.getItem('moment_swupd_pending_v1')).catch(() => '?')));
  ok('S4 panic 键已清', !(await b.page.evaluate(() => localStorage.getItem('moment_panic_v1')).catch(() => '?')));
  await b.ctx.close();
}

// ── S5 偏好键垃圾组 ──────────────────────────────────
{
  const b = await boot(seedOf({
    moment_lang: 'xx-YY',
    'moment_pack_xx-YY': 'broken{pack',
    moment_imgsize_v1: '[1,2',
    moment_backup_history: '{"bad"',
    moment_pending_input_v1: 'zzz-not-a-map',
    memos_slash_recent_v1: '{"a":1}',
    sj_fontsize: 'huge',
    sj_editor_independent_scroll: 'banana',
    weather_cache: '{"v":999}',
    moment_hint_editor_v1: 'garbage',
  }, goodStock()));
  await checkRecovered('S5', b);
  await b.ctx.close();
}

// ── S6 备忘旧形字段混入（迁移通道兜底面）────────────
{
  const stock = goodStock();
  stock.memos[1] = {
    id: 123456,
    title: 777,
    pinned: 'yes',
    deletedAt: 'junk-string',
    createdAt: Date.now() - 2 * DAY,
    updatedAt: Date.now() - 2 * DAY,
    doc: [{ type: 'paragraph', id: 'rb1', children: [{ text: 'RESILIENCE-BETA 乙篇正文' }] }],
  };
  const b = await boot(seedOf({}, stock));
  const { lines, bodyText } = b;
  ok('S6 loaded persisted memos=3', lines.some((l) => l.includes('loaded persisted memos=3')));
  ok('S6 persisted state applied', lines.some((l) => l.includes('persisted state applied')));
  ok('S6 无 load-error / 页面无加载失败', !lines.some((l) => l.includes('load-error')) && !bodyText.includes('备忘加载失败'));
  const mig = lines.find((l) => l.includes('MIGRATE d3'));
  ok('S6 MIGRATE d3 行在场', !!mig, mig || '');
  if (mig) {
    const s = {};
    for (const mm of mig.matchAll(/([a-z_]+)=(\d+)/g)) s[mm[1]] = Number(mm[2]);
    ok('S6 归一覆盖数字 id / 毫秒戳 / 标量错类型', (s.num_id || 0) >= 1 && (s.millis_ts || 0) >= 2 && (s.fields_norm || 0) >= 2,
      `num_id=${s.num_id} millis_ts=${s.millis_ts} fields_norm=${s.fields_norm}`);
  }
  ok('S6 乙篇正文标记可见（title 被剔除后正文兜底）', bodyText.includes('RESILIENCE-BETA'));
  ok('S6 甲/丙篇可见', bodyText.includes('韧性甲篇') && bodyText.includes('韧性丙篇'));
  const persisted = await readPersisted(b.page);
  let conv = false;
  try {
    const v = JSON.parse(persisted);
    const beta = v.memos.find((m) => String(m.id) === '123456');
    conv = !!beta && typeof beta.id === 'string' && typeof beta.createdAt === 'string';
  } catch { conv = false; }
  ok('S6 写回后乙篇 id/时间戳已收敛为字符串', conv);
  await checkAlive('S6', b);
  await b.ctx.close();
}

// ── S7 单篇坏行组（逐子场景；判据见文件头）──────────
const s7variants = [
  ['S7a 非对象条目', (stock) => { stock.memos.splice(1, 0, 'garbage-row'); }],
  ['S7b doc 为字符串', (stock) => { stock.memos[1].doc = 'not-an-array'; }],
  ['S7c createdAt 为布尔', (stock) => { stock.memos[1].createdAt = true; }],
  ['S7d 缺 id', (stock) => { delete stock.memos[1].id; }],
  ['S7e children 为对象', (stock) => { stock.memos[1].doc = [{ type: 'paragraph', id: 'rb1', children: { text: 'x' } }]; }],
];
for (const [name, mutate] of s7variants) {
  const stock = goodStock();
  mutate(stock);
  const b = await boot(seedOf({}, stock));
  const { page, lines, bodyText } = b;
  ok(`${name} 无 load-error 行`, !lines.some((l) => l.includes('load-error')));
  ok(`${name} 页面无「备忘加载失败」`, !bodyText.includes('备忘加载失败'));
  ok(`${name} 好篇甲/丙可见`, bodyText.includes('韧性甲篇') && bodyText.includes('韧性丙篇'));
  const pt = await page.evaluate(() => {
    const els = [...document.querySelectorAll('.img-card, .list-item')];
    const el = els.find((e) => e.innerText && e.innerText.includes('韧性甲篇'));
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + Math.min(r.height / 2, 40) };
  });
  ok(`${name} 好篇卡可定位`, !!pt);
  if (pt) {
    const off = (await b.readDiag()).length;
    if (page.touchscreen) await page.touchscreen.tap(pt.x, pt.y); else await page.mouse.click(pt.x, pt.y);
    const ls2 = await b.waitDiag((ls) => ls.slice(off).some((l) => l.includes('EDIT page enter')), 9000);
    ok(`${name} tap 好篇 EDIT page enter`, ls2.slice(off).some((l) => l.includes('EDIT page enter')));
    ok(`${name} 打开身份 = res_alpha`, ls2.slice(off).some((l) => l.includes('EDIT open memo=res_alpha')));
    // 不 goBack（退出应用落不透明源，见 checkRecovered 注）。
  }
  await checkAlive(name, b);
  await b.ctx.close();
}

// ── S8 全损保全组（设计失败态；断言保全而非恢复）────
const s8variants = [
  ['S8a memos_json 非 JSON', 'TOTALLY-NOT-JSON{{{'],
  ['S8b memos_json 根为数组', '[]'],
];
for (const [name, rawStock] of s8variants) {
  const b = await boot(seedOf({}, rawStock));
  const { page, lines, bodyText } = b;
  ok(`${name} 失败态呈现（页面有「备忘加载失败」）`, bodyText.includes('备忘加载失败'));
  ok(`${name} Diag 有 parse err 行`, lines.some((l) => l.includes('persisted memos_json parse err')),
    lines.filter((l) => l.includes('parse')).join(' | ').slice(0, 140));
  ok(`${name} Diag 有 load-error 空态行`, lines.some((l) => l.includes('load-error')));
  const after = await readPersisted(page);
  ok(`${name} IDB memos_json 逐字未动（不丢弃不覆盖）`, after === rawStock, `len ${after.length} vs ${rawStock.length}`);
  await checkAlive(name, b);
  await b.ctx.close();
}

// ── S9 manifest_raw 垃圾串 ───────────────────────────
{
  currentSeed = { ls: {}, memosJson: JSON.stringify(goodStock()), manifestRaw: 'garbage{{{manifest' };
  const b = await boot(currentSeed);
  await checkRecovered('S9', b);
  await b.ctx.close();
}

server.close();
L(fails === 0 ? 'ALL PASS' : `FAILED ${fails}`);
process.exit(fails === 0 ? 0 : 1);
