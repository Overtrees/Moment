// 默认池身份 专项探针（box Chromium 口径）：
//   A 现网池场景：旧构建（pool="default" 映射到
//      .opfs-sahpool-default）预置标记篇 → 同 profile 同
//      端口换新构建打开：Diag `pool resolved: default
//      dir=.opfs-sahpool-default`、标记篇在、本会话无
//      migrate 行（先探到现网池、零整库再迁移）。
//   B crate 默认池场景：新构建全新 profile（两池皆空 →
//      crate 默认开库）导入标记篇 → 重开：探用命中
//      .opfs-sahpool、dir 行指向之、标记篇在、无 migrate
//      行。
// 用法：node probe_pool_identity.mjs [newDistDir] [oldDistDir]
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const newDist = process.argv[2] ? path.resolve(process.argv[2]) : '/workspace/moment-privfix/dist';
const oldDist = process.argv[3] ? path.resolve(process.argv[3]) : '/workspace/moment-privfix/dist-old';
for (const [tag, d] of [['new', newDist], ['old', oldDist]]) {
  if (!fs.existsSync(path.join(d, 'storage-worker', 'worker.js'))) {
    console.log(`✗ FAIL ${tag} dist 不是 sqlite 构建：${d}`);
    process.exit(1);
  }
}
const PORT = 8245;
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
const diagLines = (page) => page.evaluate(() => {
  try {
    const raw = localStorage.getItem('moment_diag_v1') || '[]';
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.map(String) : String(v).split('\n');
  } catch { return []; }
});
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
  await page.click('.backup-modal .backup-btn.primary');
}
async function launchProfile(profileDir) {
  const ctx = await chromium.launchPersistentContext(profileDir, { executablePath: exe, args: ['--no-sandbox'] });
  await ctx.addInitScript(() => { try { localStorage.setItem('moment_pool_v1', 'default'); } catch {} });
  return ctx;
}

// ---------- A：现网池（.opfs-sahpool-default） ----------
// 注意：A1 旧构建的池映射把 "default" 当指纹拼成
// .opfs-sahpool-default——预置 LS 前须保证键在应用读到前
// 已在位（addInitScript 先行）。
{
  L('--- A 现网池预置（旧构建）→ 新构建探用 ---');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-poolA-'));
  let srv = await serve(oldDist);
  const md5 = await servedMd5();
  const oldMd5 = createHash('md5').update(fs.readFileSync(path.join(oldDist, 'moment-web_bg.wasm'))).digest('hex');
  ok('A0 旧构建服务身份', md5 === oldMd5, md5.slice(0, 10));
  let ctx = await launchProfile(profile);
  let page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('A1 旧构建列表就绪', await listReady(page));
  await doImport(page, makeMarkerZip('A'));
  await page.goto(BASE, { waitUntil: 'load' });
  await listReady(page);
  await page.waitForFunction(() => document.body.innerText.includes('POOLMARK-A'), { timeout: 30000 }).catch(() => {});
  ok('A1 旧构建导入标记篇可见', await page.evaluate(() => document.body.innerText.includes('POOLMARK-A')));
  // 等迁移/加载源行落盘，记 Diag 行数作二段切片起点。
  await sleep(2500);
  const offA = (await diagLines(page)).length;
  await ctx.close();
  srv.close();
  await sleep(600);

  srv = await serve(newDist);
  const md5b = await servedMd5();
  const newMd5 = createHash('md5').update(fs.readFileSync(path.join(newDist, 'moment-web_bg.wasm'))).digest('hex');
  ok('A2 新构建服务身份', md5b === newMd5, md5b.slice(0, 10));
  ctx = await launchProfile(profile);
  page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('A2 新构建列表就绪', await listReady(page));
  await page.waitForFunction(() => document.body.innerText.includes('POOLMARK-A'), { timeout: 30000 }).catch(() => {});
  ok('A2 标记篇仍在（现网池数据逐篇在）', await page.evaluate(() => document.body.innerText.includes('POOLMARK-A')));
  await sleep(2000);
  const seg = (await diagLines(page)).slice(offA);
  ok('A2 Diag dir 指向现网池 .opfs-sahpool-default',
    seg.some((l) => l.includes('pool resolved: default dir=.opfs-sahpool-default')),
    seg.filter((l) => l.includes('pool resolved')).join(' | ') || 'no pool line in segment');
  ok('A2 本会话无整库再迁移（无 migrate ok 行）',
    !seg.some((l) => /SQLITE migrate ok/.test(l)),
    seg.filter((l) => l.includes('migrate')).join(' | ') || 'no migrate lines');
  await ctx.close();
  srv.close();
  await sleep(600);
}

// ---------- B：crate 默认池（.opfs-sahpool） ----------
{
  L('--- B crate 默认池开库 → 重开探用 ---');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-poolB-'));
  const srv = await serve(newDist);
  let ctx = await launchProfile(profile);
  let page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('B1 列表就绪', await listReady(page));
  await doImport(page, makeMarkerZip('B'));
  await page.goto(BASE, { waitUntil: 'load' });
  await listReady(page);
  await page.waitForFunction(() => document.body.innerText.includes('POOLMARK-B'), { timeout: 30000 }).catch(() => {});
  ok('B1 导入标记篇可见', await page.evaluate(() => document.body.innerText.includes('POOLMARK-B')));
  await sleep(2500);
  const lines1 = await diagLines(page);
  ok('B1 首开 dir 指向 crate 默认池 .opfs-sahpool',
    lines1.some((l) => l.includes('pool resolved: default dir=.opfs-sahpool')),
    lines1.filter((l) => l.includes('pool resolved')).join(' | ') || 'no pool line');
  const offB = lines1.length;
  await ctx.close();
  await sleep(600);

  ctx = await launchProfile(profile);
  page = ctx.pages()[0] || (await ctx.newPage());
  await page.goto(BASE, { waitUntil: 'load' });
  ok('B2 重开列表就绪', await listReady(page));
  await page.waitForFunction(() => document.body.innerText.includes('POOLMARK-B'), { timeout: 30000 }).catch(() => {});
  ok('B2 标记篇仍在（crate 默认池数据在）', await page.evaluate(() => document.body.innerText.includes('POOLMARK-B')));
  await sleep(2000);
  const seg = (await diagLines(page)).slice(offB);
  ok('B2 Diag dir 仍指向 crate 默认池',
    seg.some((l) => l.includes('pool resolved: default dir=.opfs-sahpool')),
    seg.filter((l) => l.includes('pool resolved')).join(' | ') || 'no pool line in segment');
  ok('B2 本会话无整库再迁移', !seg.some((l) => /SQLITE migrate ok/.test(l)),
    seg.filter((l) => l.includes('migrate')).join(' | ') || 'no migrate lines');
  await ctx.close();
  srv.close();
}

L(fails === 0 ? 'PROBE POOL IDENTITY ALL PASS' : `PROBE POOL IDENTITY ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
