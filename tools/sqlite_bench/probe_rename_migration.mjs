// 改名迁移 专项探针（box Chromium 口径，2026-11-26 改名批 2）：
//   A 存量场景 ×2（legacyDir 不同）：
//      A1 旧构建 ffdc0845e2（池解析已修）全新开库 → 旧池
//         .opfs-sahpool；A2 旧构建 3a0665fb96（池映射 bug
//         期）全新开库 → 旧池 .opfs-sahpool-default。
//      两者同断言组：旧构建预置标记篇与代表性 LS 旧键 →
//      同 profile 同端口换新构建打开：
//      · 标记篇在（数据跨 IDB+池双改名存活）
//      · Diag 有 IDB rename migrated 行、pool renamed 行
//        （<legacyDir> -> .opfs-moment）、pool resolved
//        dir=.opfs-moment
//      · 无 SQLITE migrate ok（字节级搬运、无整库再迁移）
//      · LS 无 mynote_ 残留、moment_ 键齐（含 pack_ 前缀族）
//      · IDB 仅 moment-web、memos 计数 ≥1（物理落点）
//      · OPFS 根有 .opfs-moment 目录
//      · 三启：无 rename/migrated 重复行、标记篇仍在（幂等）
//   B 全新场景：新构建全新 profile：dir=.opfs-moment、
//      无 renamed/migrated 行、导入标记篇后重开仍在。
// 用法：node probe_rename_migration.mjs [newDist] [oldDistFfdc] [oldDist3a06]
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const newDist = process.argv[2] ? path.resolve(process.argv[2]) : '/workspace/mynote-tidy/rust/apps/web/dist';
const oldDistFfdc = process.argv[3] ? path.resolve(process.argv[3]) : '/workspace/rename-old-ffdc';
const oldDist3a06 = process.argv[4] ? path.resolve(process.argv[4]) : '/workspace/rename-old-3a06';
for (const [tag, d] of [['new', newDist], ['oldFfdc', oldDistFfdc], ['old3a06', oldDist3a06]]) {
  if (!fs.existsSync(path.join(d, 'storage-worker', 'worker.js'))) {
    console.log(`✗ FAIL ${tag} dist 不是 sqlite 构建：${d}`);
    process.exit(1);
  }
}
const PORT = 8247;
const BASE = `http://localhost:${PORT}/`;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream', '.zip': 'application/zip' };
function serve(distDir) {
  const srv = http.createServer((req, res) => {
    const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    const file = path.join(distDir, p === '/' ? 'index.html' : p);
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
  return new Promise((r) => srv.listen(PORT, () => r(srv)));
}
async function servedMd5() {
  return new Promise((resolve) => {
    http.get(`${BASE}moment-web_bg.wasm`, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(createHash('md5').update(Buffer.concat(chunks)).digest('hex')));
    });
  });
}
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const diagLines = (page, key) => page.evaluate((k) => {
  try {
    const raw = localStorage.getItem(k) || '[]';
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.map(String) : String(v).split('\n');
  } catch { return []; }
}, key);
async function listReady(page, timeout = 60000) {
  await page.waitForSelector('.list-item, .empty-state, .glass-search-trigger', { timeout }).catch(() => {});
  return page.evaluate(() => !!document.querySelector('.list-item, .empty-state, .glass-search-trigger'));
}
function makeMarkerZip(tag) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-marker-'));
  const memos = { version: 2, memos: [{ id: 'mark-1', title: 'POOLMARK-' + tag, pinned: false, createdAt: '2026-04-01T00:00:00.000Z', updatedAt: '2026-04-01T00:00:00.000Z', doc: [{ type: 'paragraph', children: [{ text: 'marker body' }] }] }] };
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
  await sleep(800);
  await page.click('.backup-modal .backup-btn.primary');
}
const opfsRootNames = (page) => page.evaluate(async () => {
  const root = await navigator.storage.getDirectory();
  const names = [];
  for await (const n of root.keys()) names.push(n);
  return names;
});
const idbNames = (page) => page.evaluate(async () => {
  const dbs = await indexedDB.databases();
  return dbs.map((d) => d.name);
});
const lsKeys = (page) => page.evaluate(() => Object.keys(localStorage).sort());

// ---------- A：存量场景（参数化旧构建与旧池目录） ----------
async function scenarioLegacy(tag, oldDist, legacyDir) {
  L(`--- ${tag} 旧构建预置存量（旧池 ${legacyDir}）→ 新构建改名搬运 ---`);
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), `mn-ren${tag}-`));
  let srv = await serve(oldDist);
  let ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  await ctx.addInitScript(() => { try { localStorage.setItem('mynote_pool_v1', 'default'); } catch {} });
  let page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok(`${tag}1 旧构建列表就绪`, await listReady(page));
  await doImport(page, makeMarkerZip(tag));
  await page.goto(BASE, { waitUntil: 'load' });
  await listReady(page);
  await page.waitForFunction((t) => document.body.innerText.includes('POOLMARK-' + t), { timeout: 30000 }, tag).catch(() => {});
  ok(`${tag}1 旧构建导入标记篇可见`, await page.evaluate((t) => document.body.innerText.includes('POOLMARK-' + t), tag));
  // 代表性 LS 键（旧名）：应用自带 diag 键之外补 hint 与
  // pack_ 前缀族哨兵键、swupd 忽略键。
  await page.evaluate(() => {
    localStorage.setItem('mynote_hint_editor_v1', '1');
    localStorage.setItem('mynote_pack_xx', 'sentinel');
    localStorage.setItem('mynote_swupd_dismissed_v1', 'testver');
  });
  await sleep(2500);
  const legacyIdb = await idbNames(page);
  ok(`${tag}1 旧 IDB 库 mynote-web 在位`, legacyIdb.includes('mynote-web'), legacyIdb.join(','));
  const legacyOpfs = await opfsRootNames(page);
  ok(`${tag}1 旧池目录 ${legacyDir} 在位`, legacyOpfs.includes(legacyDir), legacyOpfs.join(','));
  const offA = (await diagLines(page, 'mynote_diag_v1')).length;
  ok(`${tag}1 旧 Diag 行已落盘`, offA > 0, `lines=${offA}`);
  await ctx.close();
  srv.close();
  await sleep(600);

  srv = await serve(newDist);
  const md5b = await servedMd5();
  const newMd5 = createHash('md5').update(fs.readFileSync(path.join(newDist, 'moment-web_bg.wasm'))).digest('hex');
  ok(`${tag}2 新构建服务身份`, md5b === newMd5, md5b.slice(0, 10));
  ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok(`${tag}2 新构建列表就绪`, await listReady(page));
  await page.waitForFunction((t) => document.body.innerText.includes('POOLMARK-' + t), { timeout: 30000 }, tag).catch(() => {});
  ok(`${tag}2 标记篇仍在（双改名后数据存活）`, await page.evaluate((t) => document.body.innerText.includes('POOLMARK-' + t), tag));
  await sleep(2500);
  const seg = (await diagLines(page, 'moment_diag_v1')).slice(offA);
  ok(`${tag}2 Diag 有 IDB rename migrated 行`,
    seg.some((l) => l.includes('IDB rename migrated mynote-web -> moment-web')),
    seg.filter((l) => l.includes('rename')).join(' | ') || 'no rename lines');
  ok(`${tag}2 Diag 有 pool renamed 行（${legacyDir} -> .opfs-moment）`,
    seg.some((l) => l.includes(`pool renamed: ${legacyDir} -> .opfs-moment`)),
    seg.filter((l) => l.includes('renamed')).join(' | ') || 'no renamed line');
  ok(`${tag}2 Diag pool resolved dir=.opfs-moment`,
    seg.some((l) => l.includes('pool resolved: default dir=.opfs-moment')),
    seg.filter((l) => l.includes('pool resolved')).join(' | ') || 'no pool line');
  ok(`${tag}2 无整库再迁移（字节级搬运）`,
    !seg.some((l) => /SQLITE migrate ok/.test(l)),
    seg.filter((l) => l.includes('migrate')).join(' | ') || 'no migrate lines');
  const keys = await lsKeys(page);
  ok(`${tag}2 LS 无 mynote_ 残留`, !keys.some((k) => k.startsWith('mynote_')), keys.join(','));
  ok(`${tag}2 LS moment_pool_v1=default 已搬运`,
    await page.evaluate(() => localStorage.getItem('moment_pool_v1')) === 'default');
  ok(`${tag}2 LS moment_hint_editor_v1 已搬运`,
    await page.evaluate(() => localStorage.getItem('moment_hint_editor_v1')) === '1');
  ok(`${tag}2 LS moment_pack_xx 前缀族已搬运`,
    await page.evaluate(() => localStorage.getItem('moment_pack_xx')) === 'sentinel');
  ok(`${tag}2 LS moment_swupd_dismissed_v1 已搬运`,
    await page.evaluate(() => localStorage.getItem('moment_swupd_dismissed_v1')) === 'testver');
  const newIdb = await idbNames(page);
  ok(`${tag}2 IDB 仅 moment-web（旧库已删）`,
    newIdb.includes('moment-web') && !newIdb.includes('mynote-web'), newIdb.join(','));
  const memoCount = await page.evaluate(async () => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open('moment-web');
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    });
    return new Promise((res, rej) => {
      const rq = db.transaction('memos', 'readonly').objectStore('memos').count();
      rq.onsuccess = () => res(rq.result);
      rq.onerror = () => rej(rq.error);
    });
  });
  ok(`${tag}2 moment-web memos 计数 ≥1（物理落点核对）`, memoCount >= 1, `count=${memoCount}`);
  const newOpfs = await opfsRootNames(page);
  ok(`${tag}2 OPFS 根有新池目录 .opfs-moment`, newOpfs.includes('.opfs-moment'), newOpfs.join(','));
  const offA2 = (await diagLines(page, 'moment_diag_v1')).length;
  await ctx.close();
  await sleep(600);

  // 三启：幂等——不再出现 rename/migrated 行，数据仍在。
  ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok(`${tag}3 三启列表就绪`, await listReady(page));
  await page.waitForFunction((t) => document.body.innerText.includes('POOLMARK-' + t), { timeout: 30000 }, tag).catch(() => {});
  ok(`${tag}3 标记篇仍在`, await page.evaluate((t) => document.body.innerText.includes('POOLMARK-' + t), tag));
  await sleep(2000);
  const seg3 = (await diagLines(page, 'moment_diag_v1')).slice(offA2);
  ok(`${tag}3 无重复 IDB rename migrated 行`,
    !seg3.some((l) => l.includes('IDB rename migrated')));
  ok(`${tag}3 无重复 pool renamed 行`,
    !seg3.some((l) => l.includes('pool renamed:')));
  ok(`${tag}3 无整库再迁移`, !seg3.some((l) => /SQLITE migrate ok/.test(l)));
  await ctx.close();
  srv.close();
  await sleep(600);
}

await scenarioLegacy('A', oldDistFfdc, '.opfs-sahpool');
await scenarioLegacy('B', oldDist3a06, '.opfs-sahpool-default');

// ---------- C：全新 profile（新构建） ----------
{
  L('--- C 全新 profile 新构建 ---');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-renC-'));
  const srv = await serve(newDist);
  let ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  let page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('C1 列表就绪', await listReady(page));
  await doImport(page, makeMarkerZip('C'));
  await page.goto(BASE, { waitUntil: 'load' });
  await listReady(page);
  await page.waitForFunction(() => document.body.innerText.includes('POOLMARK-C'), { timeout: 30000 }).catch(() => {});
  ok('C1 导入标记篇可见', await page.evaluate(() => document.body.innerText.includes('POOLMARK-C')));
  await sleep(2500);
  const lines1 = await diagLines(page, 'moment_diag_v1');
  ok('C1 dir 指向新名池 .opfs-moment',
    lines1.some((l) => l.includes('pool resolved: default dir=.opfs-moment')),
    lines1.filter((l) => l.includes('pool resolved')).join(' | ') || 'no pool line');
  ok('C1 无 pool renamed 行（无存量）',
    !lines1.some((l) => l.includes('pool renamed:')));
  ok('C1 无 IDB rename migrated 行（无存量）',
    !lines1.some((l) => l.includes('IDB rename migrated')));
  const offB = lines1.length;
  await ctx.close();
  await sleep(600);

  ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
  page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('C2 重开列表就绪', await listReady(page));
  await page.waitForFunction(() => document.body.innerText.includes('POOLMARK-C'), { timeout: 30000 }).catch(() => {});
  ok('C2 标记篇仍在', await page.evaluate(() => document.body.innerText.includes('POOLMARK-C')));
  await sleep(2000);
  const segB = (await diagLines(page, 'moment_diag_v1')).slice(offB);
  ok('C2 无整库再迁移', !segB.some((l) => /SQLITE migrate ok/.test(l)));
  await ctx.close();
  srv.close();
}

L(fails === 0 ? 'PROBE RENAME MIGRATION ALL PASS' : `PROBE RENAME MIGRATION ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
