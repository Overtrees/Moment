// 专用探针：新版「备忘加载失败」故障（2026-11-24 生产
// 故障，57f59539a3）回归锁。
// 故障形态（用户真机诊断 proven）：盘上 memos_json 仍含旧
// 形值（数字 id / 毫秒数值时间戳）时，新构建启动落
// `APP persisted memos_json parse err: invalid type:
// integer ..., expected a string` 并展示 load-error 空态，
// 整库判死。成因链：D3 一次性迁移的完成标记在归一函数内
// 同步置位、归一写回是其后独立的异步 save——真机首启写回
// 被同秒的 wasm trap 打断（Diag 有 MIGRATE 行、无
// persisted state applied），标记已落、存量未归一；单形
// 化后的构建见标记跳过归一、直接严格解析未归一存量即死。
// 本探针把真机实态钉进门禁：
//   夹具 = fixtures/stock_oldform_persisted.json——旧构建
//   真实落盘的 memos_json 原文（6 篇：数字 id×1、毫秒时间
//   戳×12，非手写镜像），种子页写入 IDB 的同时预置
//   localStorage 标记 mynote_stock_mig_v1=1（模拟「D3 已跑
//   过、标记已置位、盘上仍有旧形值」）。
// 断言：① boot1 加载成功（loaded persisted memos=6 +
//   persisted state applied）、无 parse err、无 load-
//   error、MIGRATE d3 行在场且 num_id≥1、millis_ts≥12；
//   ② boot1 后盘上 memos_json 已收敛写回（全部 id/时间戳
//   为字符串）；③ boot2（标记仍在）重复加载成功、无
//   parse err、且不再产生 MIGRATE 行（已收敛、幂等）；
//   ④ boot1 真实 tap 首卡后 EDIT page enter 出现（存量可
//   用而非仅可解析）。
// 用法：node probe_load_stock.mjs [distDir]
//   默认 rust/apps/web/dist；自带静态服务（需同源种子页）。
import { webkit } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
let distDir = path.join(root, 'rust', 'apps', 'web', 'dist');
if (process.argv[2] && !process.argv[2].startsWith('http')) {
  distDir = path.resolve(process.argv[2]);
}
const FIXTURE = fs.readFileSync(path.join(root, 'fixtures', 'stock_oldform_persisted.json'), 'utf8');
const MANIFEST = '{"version":1,"attachments":{}}';
const PORT = 8159;
const BASE = `http://localhost:${PORT}/`;
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
const SEED_HTML = `<!doctype html><meta charset="utf-8"><script>
localStorage.setItem('mynote_stock_mig_v1', '1');
const memos = ${JSON.stringify(FIXTURE)};
const manifest = ${JSON.stringify(MANIFEST)};
const req = indexedDB.open('mynote-web', 1);
req.onupgradeneeded = () => { const db = req.result; db.createObjectStore('kv'); db.createObjectStore('attachments'); };
req.onsuccess = () => {
  const db = req.result;
  const tx = db.transaction('kv', 'readwrite');
  tx.objectStore('kv').put(memos, 'memos_json');
  tx.objectStore('kv').put(manifest, 'manifest_raw');
  tx.oncomplete = () => location.replace('/');
};
</script>seeding`;
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Cache-Control', 'no-store');
  if (p === '/__seed.html') { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(SEED_HTML); return; }
  if (p === '/') p = '/index.html';
  const fp = path.join(distDir, p);
  if (!fp.startsWith(distDir) || !fs.existsSync(fp) || fs.statSync(fp).isDirectory()) { res.writeHead(404); res.end('nf'); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'application/octet-stream' });
  fs.createReadStream(fp).pipe(res);
});
await new Promise((r) => server.listen(PORT, r));

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'loadstock-'));
const ctx = await webkit.launchPersistentContext(dir, {
  viewport: { width: 393, height: 852 },
  colorScheme: 'dark',
  hasTouch: true,
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Mobile/15E148 Safari/604.1',
});
const page = ctx.pages()[0] || (await ctx.newPage());
const readDiag = async () => page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '').then((s) => {
  try { const v = JSON.parse(s); return Array.isArray(v) ? v : String(s).split('\n'); } catch { return String(s).split('\n'); }
}).catch(() => []);
const waitDiag = async (pred, timeout = 12000) => {
  const t0 = Date.now();
  let lines = [];
  while (Date.now() - t0 < timeout) {
    lines = await readDiag();
    if (pred(lines)) return lines;
    await sleep(600);
  }
  return lines;
};
const readPersisted = () => page.evaluate(() => new Promise((resolve) => {
  const req = indexedDB.open('mynote-web', 1);
  req.onsuccess = () => {
    const get = req.result.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
    get.onsuccess = () => resolve(get.result || '');
    get.onerror = () => resolve('');
  };
  req.onerror = () => resolve('');
})).catch(() => '');

// ── boot1：标记已置位 + 旧形存量 ─────────────────────
await page.goto(BASE + '__seed.html', { waitUntil: 'load' }).catch(() => {});
let lines = await waitDiag((ls) => ls.some((l) => l.includes('persisted state applied') || l.includes('parse err')), 15000);
ok('boot1 loaded persisted memos=6', lines.some((l) => l.includes('loaded persisted memos=6')));
ok('boot1 persisted state applied', lines.some((l) => l.includes('persisted state applied')));
ok('boot1 无 parse err', !lines.some((l) => l.includes('persisted memos_json parse err')));
ok('boot1 无 load-error', !lines.some((l) => l.includes('load-error')));
const mig = lines.find((l) => l.includes('MIGRATE d3 memos='));
ok('boot1 MIGRATE d3 在场（标记已置位仍归一）', !!mig, mig || '');
if (mig) {
  const numId = Number((mig.match(/num_id=(\d+)/) || [])[1] || 0);
  const millis = Number((mig.match(/millis_ts=(\d+)/) || [])[1] || 0);
  ok('boot1 归一覆盖数字 id 与毫秒时间戳', numId >= 1 && millis >= 12, `num_id=${numId} millis_ts=${millis}`);
}
const bodyText = await page.evaluate(() => document.body.innerText).catch(() => '');
ok('boot1 页面无「备忘加载失败」', !bodyText.includes('备忘加载失败'));

// ── 收敛写回：盘上 memos_json 全部字符串形 ───────────
const persisted = await readPersisted();
let converged = false;
try {
  const v = JSON.parse(persisted);
  converged = Array.isArray(v.memos) && v.memos.length === 6 && v.memos.every((m) =>
    typeof m.id === 'string' && typeof m.createdAt === 'string' && typeof m.updatedAt === 'string');
} catch { converged = false; }
ok('boot1 后盘上存量已收敛（id/时间戳全字符串、篇数守恒）', converged);

// ── boot1 可用性：真实 tap 首卡进编辑器 ──────────────
const pt = await page.evaluate(() => {
  const el = document.querySelector('.img-card, .list-item:not(.set-row)');
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + Math.min(r.height / 2, 40) };
});
ok('boot1 首卡可定位', !!pt);
if (pt) {
  const off = (await readDiag()).length;
  if (page.touchscreen) await page.touchscreen.tap(pt.x, pt.y); else await page.mouse.click(pt.x, pt.y);
  lines = await waitDiag((ls) => ls.slice(off).some((l) => l.includes('EDIT page enter')), 9000);
  ok('boot1 tap 后 EDIT page enter 出现', lines.slice(off).some((l) => l.includes('EDIT page enter')));
  await page.goBack().catch(() => {});
  await sleep(800);
}

// ── boot2：收敛后重载（标记仍在）幂等 ────────────────
const off2 = (await readDiag()).length;
await page.goto(BASE, { waitUntil: 'load' }).catch(() => {});
lines = await waitDiag((ls) => ls.slice(off2).some((l) => l.includes('persisted state applied') || l.includes('parse err')), 15000);
const seg2 = lines.slice(off2);
ok('boot2 loaded persisted memos=6', seg2.some((l) => l.includes('loaded persisted memos=6')));
ok('boot2 persisted state applied', seg2.some((l) => l.includes('persisted state applied')));
ok('boot2 无 parse err', !seg2.some((l) => l.includes('persisted memos_json parse err')));
ok('boot2 无 load-error', !seg2.some((l) => l.includes('load-error')));
ok('boot2 不再产生 MIGRATE 行（已收敛）', !seg2.some((l) => l.includes('MIGRATE d3')));

await ctx.close();
server.close();
L(fails === 0 ? 'ALL PASS' : `FAILED ${fails}`);
process.exit(fails === 0 ? 0 : 1);
