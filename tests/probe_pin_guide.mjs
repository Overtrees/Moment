// 专用探针：种子置顶改指使用指南（pin-guide）回归锁。
// 种子层：demo_guide「使用指南」改为种子置顶篇，原种子
// 置顶 demo_home「装修踩坑清单」改为不置顶。存量层：种子
// 只在首启写入、用户存量早已落盘，加载期 seed_pin_swap
// 在两篇均为种子原形（标题+正文逐值一致、非待删）且
// demo_home 仍置顶 / demo_guide 仍未置顶时一次性互换
// pinned 并写回收敛 + Diag 行；用户已自行改过置顶或任一
// 篇被编辑/删除则不干预（数据主权口径）。
// 夹具 = fixtures/stock_seed_oldpin_persisted.json——改版
// 前种子构造器（sample_data_at）直出的落盘形态原文（6 篇，
// guide 未置顶 / home 置顶），非手写镜像。
// 场景：A 新种子首启（无存量）——置顶组为使用指南、装修
// 踩坑清单不在置顶组；B 旧存量启动——Diag 互换行在场、
// 盘上 guide/home pinned 互换且其余字段与其余篇逐值不变
// （完整性断言）、boot2 幂等不再互换；C 用户已自行取消
// home 置顶的存量——不干预（无互换行、盘上 pins 不变、
// 无置顶组）。
// 用法：node probe_pin_guide.mjs [distDir]
//   默认 rust/apps/web/dist；自带静态服务（需同源种子页）。
import { webkit } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
let distDir = path.join(root, '..', 'rust', 'apps', 'web', 'dist');
if (process.argv[2] && !process.argv[2].startsWith('http')) {
  distDir = path.resolve(process.argv[2]);
}
const FIXTURE = fs.readFileSync(path.join(root, 'fixtures', 'stock_seed_oldpin_persisted.json'), 'utf8');
const MANIFEST = '{"version":1,"attachments":{}}';
const PORT = 8167;
const BASE = `http://localhost:${PORT}/`;
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
let currentFixture = null;
const SEED_HTML = `<!doctype html><meta charset="utf-8"><script>
fetch('/__fixture.json').then((r) => r.text()).then((memos) => {
  const req = indexedDB.open('moment-web', 1);
  req.onupgradeneeded = () => { const db = req.result; db.createObjectStore('kv'); db.createObjectStore('attachments'); };
  req.onsuccess = () => {
    const db = req.result;
    const tx = db.transaction('kv', 'readwrite');
    tx.objectStore('kv').put(memos, 'memos_json');
    tx.objectStore('kv').put(${JSON.stringify(MANIFEST)}, 'manifest_raw');
    tx.oncomplete = () => location.replace('/');
  };
});
</script>seeding`;
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Cache-Control', 'no-store');
  if (p === '/__seed.html') { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(SEED_HTML); return; }
  if (p === '/__fixture.json') { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(currentFixture || '{}'); return; }
  if (p === '/') p = '/index.html';
  const fp = path.join(distDir, p);
  if (!fp.startsWith(distDir) || !fs.existsSync(fp) || fs.statSync(fp).isDirectory()) { res.writeHead(404); res.end('nf'); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'application/octet-stream' });
  fs.createReadStream(fp).pipe(res);
});
await new Promise((r) => server.listen(PORT, r));

const newCtx = async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pinguide-'));
  const ctx = await webkit.launchPersistentContext(dir, {
    viewport: { width: 393, height: 852 },
    colorScheme: 'dark',
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Mobile/15E148 Safari/604.1',
  });
  const page = ctx.pages()[0] || (await ctx.newPage());
  return { ctx, page };
};
const readDiag = async (page) => page.evaluate(() => localStorage.getItem('moment_diag_v1') || '').then((s) => {
  try { const v = JSON.parse(s); return Array.isArray(v) ? v : String(s).split('\n'); } catch { return String(s).split('\n'); }
}).catch(() => []);
const waitDiag = async (page, pred, timeout = 15000) => {
  const t0 = Date.now();
  let lines = [];
  while (Date.now() - t0 < timeout) {
    lines = await readDiag(page);
    if (pred(lines)) return lines;
    await sleep(600);
  }
  return lines;
};
const readPersisted = (page) => page.evaluate(() => new Promise((resolve) => {
  // 组装读（IDB 分条合流适配，只换读取通道、断言不变）：
  // memos_json 在则直用；否则 backup_meta + memos_order +
  // memos 店组装回全量 JSON。
  const req = indexedDB.open('moment-web');
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
const readGroups = (page) => page.evaluate(() => [...document.querySelectorAll('.section-header')].map((h) => {
  const box = h.parentElement;
  return {
    label: h.innerText.trim(),
    titles: [...box.querySelectorAll('.item-title-text')].map((e) => e.innerText.trim()),
  };
})).catch(() => []);
const waitGroups = async (page, timeout = 15000) => {
  const t0 = Date.now();
  let groups = [];
  while (Date.now() - t0 < timeout) {
    groups = await readGroups(page);
    if (groups.length > 0) return groups;
    await sleep(500);
  }
  return groups;
};
// 规范化深比较（键序无关）：盘上重序列化与夹具原文键序
// 应同源，但比较口径不押在键序上。另把「值为 null 的键」
// 与「键缺席」视为等价：Node.meta 是 Option<Value>，种子
// 构造写的 Some(Null) 序列化为 "meta": null、解析回 None
// 后写回即省键——这是模型往返的既有口径（任一写回触发
// 皆然、与置顶互换无关，2026-11-25 本探针首跑实证：差
// 异仅 demo_music 四个 musicCard 节点的 meta 键存废）。
// 等价只限 null↔缺席，任何非 null 值的增删改照样判红。
const canon = (v) => {
  if (Array.isArray(v)) return v.map(canon);
  if (v && typeof v === 'object') {
    return Object.fromEntries(
      Object.keys(v).sort().filter((k) => v[k] !== null).map((k) => [k, canon(v[k])]),
    );
  }
  return v;
};
const deepEq = (a, b) => JSON.stringify(canon(a)) === JSON.stringify(canon(b));
const pinOf = (backup, id) => (backup.memos.find((m) => m.id === id) || {}).pinned;

// ── 场景 A：新种子首启（无存量） ─────────────────────
{
  const { ctx, page } = await newCtx();
  await page.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  const groups = await waitGroups(page);
  const pinnedGroup = groups.find((g) => g.label === '置顶');
  ok('A 首启出现置顶组', !!pinnedGroup, JSON.stringify(groups.map((g) => g.label)));
  ok('A 置顶组含使用指南', !!pinnedGroup && pinnedGroup.titles.includes('使用指南'), pinnedGroup ? pinnedGroup.titles.join(',') : '');
  ok('A 置顶组不含装修踩坑清单', !!pinnedGroup && !pinnedGroup.titles.includes('装修踩坑清单'));
  ok('A 使用指南只在置顶组出现', groups.filter((g) => g.titles.includes('使用指南')).length === 1);
  ok('A 装修踩坑清单在普通组', groups.some((g) => g.label !== '置顶' && g.titles.includes('装修踩坑清单')));
  await ctx.close();
}

// ── 场景 B：旧存量启动 → 一次性互换 + 完整性 + 幂等 ──
{
  const { ctx, page } = await newCtx();
  currentFixture = FIXTURE;
  await page.goto(BASE + '__seed.html', { waitUntil: 'load' }).catch(() => {});
  let lines = await waitDiag(page, (ls) => ls.some((l) => l.includes('persisted state applied') || l.includes('parse err')));
  ok('B 存量加载成功', lines.some((l) => l.includes('loaded persisted memos=6')) && lines.some((l) => l.includes('persisted state applied')));
  ok('B Diag 互换行在场', lines.some((l) => l.includes('seed pin retargeted: demo_guide pinned, demo_home unpinned')), lines.filter((l) => l.includes('seed pin')).join(' | '));
  ok('B 无 parse err / PANIC', !lines.some((l) => l.includes('parse err') || l.includes('PANIC')));
  const groups = await waitGroups(page);
  const pinnedGroup = groups.find((g) => g.label === '置顶');
  ok('B 置顶组为使用指南', !!pinnedGroup && pinnedGroup.titles.includes('使用指南') && !pinnedGroup.titles.includes('装修踩坑清单'), JSON.stringify(groups.map((g) => [g.label, g.titles])));
  const persisted = await readPersisted(page);
  let after = null;
  try { after = JSON.parse(persisted); } catch { after = null; }
  ok('B 盘上可解析且篇数守恒', !!after && after.memos.length === 6);
  if (after) {
    ok('B 盘上 guide 已置顶 / home 已取消置顶', pinOf(after, 'demo_guide') === true && pinOf(after, 'demo_home') === false,
      `guide=${pinOf(after, 'demo_guide')} home=${pinOf(after, 'demo_home')}`);
    // 完整性：期望 = 夹具只翻两处 pinned，其余逐值不变。
    const expected = JSON.parse(FIXTURE);
    for (const m of expected.memos) {
      if (m.id === 'demo_guide') m.pinned = true;
      if (m.id === 'demo_home') m.pinned = false;
    }
    ok('B 除两处 pinned 外全库逐值不变', deepEq(after, expected));
  }
  // boot2：同 context 重载，互换不得再发生。
  await page.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  lines = await waitDiag(page, (ls) => {
    const starts = ls.map((l, i) => (l.includes('APP start') ? i : -1)).filter((i) => i >= 0);
    if (starts.length < 2) return false;
    return ls.slice(starts[starts.length - 1]).some((l) => l.includes('persisted state applied') || l.includes('parse err'));
  });
  const startIdx = lines.map((l, i) => (l.includes('APP start') ? i : -1)).filter((i) => i >= 0);
  const seg2 = lines.slice(startIdx[startIdx.length - 1] ?? 0);
  ok('B boot2 加载成功', seg2.some((l) => l.includes('persisted state applied')));
  ok('B boot2 不再互换（幂等）', !seg2.some((l) => l.includes('seed pin retargeted')));
  const persisted2 = await readPersisted(page);
  let after2 = null;
  try { after2 = JSON.parse(persisted2); } catch { after2 = null; }
  ok('B boot2 盘上 pins 保持', !!after2 && pinOf(after2, 'demo_guide') === true && pinOf(after2, 'demo_home') === false);
  await ctx.close();
}

// ── 场景 C：用户已自行取消 home 置顶 → 不干预 ────────
{
  const { ctx, page } = await newCtx();
  const variant = JSON.parse(FIXTURE);
  for (const m of variant.memos) if (m.id === 'demo_home') m.pinned = false;
  currentFixture = JSON.stringify(variant);
  await page.goto(BASE + '__seed.html', { waitUntil: 'load' }).catch(() => {});
  const lines = await waitDiag(page, (ls) => ls.some((l) => l.includes('persisted state applied') || l.includes('parse err')));
  ok('C 存量加载成功', lines.some((l) => l.includes('persisted state applied')));
  ok('C 无互换行（不干预）', !lines.some((l) => l.includes('seed pin retargeted')));
  const persisted = await readPersisted(page);
  let after = null;
  try { after = JSON.parse(persisted); } catch { after = null; }
  ok('C 盘上 pins 保持用户安排', !!after && pinOf(after, 'demo_guide') === false && pinOf(after, 'demo_home') === false,
    after ? `guide=${pinOf(after, 'demo_guide')} home=${pinOf(after, 'demo_home')}` : 'unparsed');
  const groups = await waitGroups(page);
  ok('C 无置顶组', !groups.some((g) => g.label === '置顶'), JSON.stringify(groups.map((g) => g.label)));
  await ctx.close();
}

server.close();
L(fails === 0 ? 'ALL PASS' : `FAILED ${fails}`);
process.exit(fails === 0 ? 0 : 1);
