// 会话降级恢复链 专项探针（box Chromium 口径）：
//   Chromium 无法原生造 OPFS 政策性禁用（Playwright 路由
//   又拦不到 Dedicated Worker 脚本），故 S1 改用磁盘桩
//   dist：storage-worker/worker.js 整体换成桩文件（init
//   恒回结构化 unavailable：step=directory + 隐私签名，
//   其余命令报错），S2 同端口同 profile 换回真 dist 冷启。
//   S1 桩在位：应用进会话 IDB 降级（Diag fallback 行 +
//      ephemeral 横幅），导入标记篇落 IDB、kv 降级标记在位。
//   S2 撤桩同 profile 冷启：SQLite 恢复，标记新于库戳 →
//      replace 式再迁移，Diag `session fallback recovered`
//      行、标记已清、标记篇经 SQLite 加载源在列、对账 ok。
// 用法：node probe_fallback_recovery.mjs [distDir]
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const distDir = process.argv[2] ? path.resolve(process.argv[2]) : '/workspace/mynote-privfix/dist';
const stubDist = process.argv[3] ? path.resolve(process.argv[3]) : '/workspace/mynote-privfix/dist-stub';
for (const [tag, d] of [['真', distDir], ['桩', stubDist]]) {
  if (!fs.existsSync(path.join(d, 'storage-worker', 'worker.js'))) {
    console.log(`✗ FAIL ${tag} dist 不是 sqlite 构建：${d}`);
    process.exit(1);
  }
}
let serveRoot = stubDist;
const PORT = 8247;
const BASE = `http://localhost:${PORT}/`;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream', '.zip': 'application/zip' };
const server = http.createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = path.join(serveRoot, p === '/' ? 'index.html' : p);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('nf'); return; }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'same-origin',
      'Cache-Control': 'no-store',
    });
    res.end(data);
  });
});
await new Promise((r) => server.listen(PORT, r));
const servedMd5 = await new Promise((resolve) => {
  http.get(`${BASE}mynote-web_bg.wasm`, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => resolve(createHash('md5').update(Buffer.concat(chunks)).digest('hex')));
  });
});
const diskMd5 = createHash('md5').update(fs.readFileSync(path.join(distDir, 'mynote-web_bg.wasm'))).digest('hex');
console.log(`served wasm md5=${servedMd5} disk md5=${diskMd5} ${servedMd5 === diskMd5 ? 'MATCH' : 'MISMATCH'}`);
if (servedMd5 !== diskMd5) { console.log('✗ FAIL 服务身份不符'); process.exit(1); }

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const diagLines = (page) => page.evaluate(() => {
  try {
    const raw = localStorage.getItem('mynote_diag_v1') || '[]';
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.map(String) : String(v).split('\n');
  } catch { return []; }
});
async function waitDiag(page, re, timeout = 45000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if ((await diagLines(page)).some((l) => re.test(l))) return true;
    await sleep(700);
  }
  return false;
}
async function listReady(page, timeout = 60000) {
  await page.waitForSelector('.list-item, .empty-state, .glass-search-trigger', { timeout }).catch(() => {});
  return page.evaluate(() => !!document.querySelector('.list-item, .empty-state, .glass-search-trigger'));
}
function makeMarkerZip(tag) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-marker-'));
  const memos = { version: 2, memos: [{ id: 'mark-1', title: 'RECMARK-' + tag, pinned: false, createdAt: '2026-04-01T00:00:00.000Z', updatedAt: '2026-04-01T00:00:00.000Z', doc: [{ type: 'paragraph', children: [{ text: 'marker body' }] }] }] };
  fs.writeFileSync(path.join(dir, 'memos.json'), JSON.stringify(memos));
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ version: 1, attachments: {} }));
  const zip = path.join(dir, 'marker.zip');
  execSync(`cd ${dir} && python3 -c "import zipfile; z=zipfile.ZipFile('marker.zip','w'); z.write('memos.json'); z.write('manifest.json'); z.close()"`);
  return zip;
}
async function doImport(page, zipPath) {
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 10000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 10000 });
  await page.setInputFiles('#file-import', zipPath);
  await page.waitForSelector('.backup-modal', { timeout: 10000 });
  // 模态进场/暂存态落定后再点确认：waitForSelector 命中
  // 只保证元素在 DOM，紧贴点击曾赶在确认处理接线前使
  // 模态空关（dbg_imp 对照：加 800ms 落定后 IMPORT ok）。
  await sleep(800);
  await page.click('.backup-modal .backup-btn.primary');
  await sleep(1500);
}
const readMarker = (page) => page.evaluate(() => new Promise((resolve) => {
  const req = indexedDB.open('mynote-web');
  req.onerror = () => resolve('open-error');
  req.onsuccess = () => {
    const db = req.result;
    if (!db.objectStoreNames.contains('kv')) { resolve('no-kv-store'); return; }
    const get = db.transaction('kv', 'readonly').objectStore('kv').get('session_fallback_ts');
    get.onsuccess = () => resolve(get.result === undefined ? 'absent' : String(get.result));
    get.onerror = () => resolve('get-error');
  };
}));

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-rec-'));
// ---------- S1 桩在位：降级会话 ----------
{
  L('--- S1 桩 Worker → 会话 IDB 降级 ---');
  const ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  const page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('S1 列表就绪（降级会话）', await listReady(page));
  ok('S1 无阻断层', !(await page.evaluate(() => !!document.querySelector('.storage-blocked'))));
  ok('S1 Diag fallback 行（step=directory）', await waitDiag(page, /session idb fallback: sqlite unavailable step=directory/),
    (await diagLines(page)).filter((l) => l.includes('session idb fallback')).pop() || 'none');
  const banner = await page.evaluate(() => {
    const el = document.querySelector('.storage-readonly-banner');
    return el ? el.textContent.trim() : null;
  });
  ok('S1 横幅为 ephemeral 支', !!banner && banner.includes('无痕/临时会话'), banner || 'no banner');
  await doImport(page, makeMarkerZip('RC'));
  await page.goto(BASE, { waitUntil: 'load' });
  await listReady(page);
  await page.waitForFunction(() => document.body.innerText.includes('RECMARK-RC'), { timeout: 30000 }).catch(() => {});
  ok('S1 降级期导入标记篇可见（IDB 落盘）', await page.evaluate(() => document.body.innerText.includes('RECMARK-RC')));
  const m = await readMarker(page);
  ok('S1 kv 降级标记在位', /^\d+$/.test(String(m)) && Number(m) > 0, 'marker=' + m);
  await ctx.close();
  await sleep(600);
}
// ---------- S2 撤桩冷启：再迁移恢复 ----------
{
  L('--- S2 撤桩冷启 → 再迁移收敛 ---');
  serveRoot = distDir;
  const ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  const page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('S2 列表就绪', await listReady(page));
  await page.waitForFunction(() => document.body.innerText.includes('RECMARK-RC'), { timeout: 30000 }).catch(() => {});
  ok('S2 降级期标记篇经再迁移后仍在', await page.evaluate(() => document.body.innerText.includes('RECMARK-RC')));
  ok('S2 Diag 加载源 sqlite', await waitDiag(page, /SQLITE load source=sqlite/),
    (await diagLines(page)).filter((l) => l.includes('load source')).pop() || 'none');
  ok('S2 Diag recovered 行', await waitDiag(page, /session fallback recovered: idb re-migrated to sqlite/, 30000),
    (await diagLines(page)).filter((l) => l.includes('session fallback')).slice(-2).join(' | ') || 'none');
  const m2 = await readMarker(page);
  ok('S2 kv 降级标记已清', m2 === 'absent', 'marker=' + m2);
  // 对账不在迁移同会话跑：migrate 成功即置 SESSION_ALIGNED
  // （迁移本身已收敛镜像，persist.rs 既有设计），reconcile
  // 守卫据此早退——S3 再冷启才断言对账行。
  await ctx.close();
  await sleep(600);
}
// ---------- S3 再冷启：对账全等 ----------
{
  L('--- S3 再冷启 → 冷启对账 ---');
  const ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  const page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('S3 列表就绪', await listReady(page));
  ok('S3 冷启对账 ok', await waitDiag(page, /SQLITE reconcile ok memos=1/, 60000),
    (await diagLines(page)).filter((l) => l.includes('reconcile')).pop() || 'none');
  await ctx.close();
}
server.close();
L(fails === 0 ? 'PROBE FALLBACK RECOVERY ALL PASS' : `PROBE FALLBACK RECOVERY ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
