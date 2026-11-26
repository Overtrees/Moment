// 无痕/易失会话降级 专项探针（box Playwright WebKit 主验口径）：
//   桌面 WebKit 易失上下文与 iOS Safari 无痕同为 OPFS 政策性
//   禁用（install 第 ① 步 getDirectory 失败），等价复现真机
//   无痕路径。断言：全新易失上下文打开应用 → 不出现
//   .storage-blocked 阻断层、列表可用、Diag 有结构化
//   session idb fallback 行（step=directory）、常驻横幅为
//   ephemeral 支文案、无 occupied 行；导入（save_all）与
//   编辑（save delta）均走 IDB 会话臂落盘；重载后本会话
//   数据仍在；IDB kv 有会话降级标记 session_fallback_ts。
// 用法：node probe_ephemeral_webkit.mjs [distDir]
import { webkit } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const distDir = process.argv[2] ? path.resolve(process.argv[2]) : '/workspace/moment-privfix/dist';
if (!fs.existsSync(path.join(distDir, 'storage-worker', 'worker.js'))) {
  console.log('✗ FAIL dist 不是 sqlite 构建：' + distDir);
  process.exit(1);
}
const PORT = 8243;
const BASE = `http://localhost:${PORT}/`;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream', '.zip': 'application/zip' };
const server = http.createServer((req, res) => {
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
await new Promise((r) => server.listen(PORT, r));
const servedMd5 = await new Promise((resolve) => {
  http.get(`${BASE}moment-web_bg.wasm`, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => resolve(createHash('md5').update(Buffer.concat(chunks)).digest('hex')));
  });
});
const diskMd5 = createHash('md5').update(fs.readFileSync(path.join(distDir, 'moment-web_bg.wasm'))).digest('hex');
console.log(`served wasm md5=${servedMd5} disk md5=${diskMd5} ${servedMd5 === diskMd5 ? 'MATCH' : 'MISMATCH'}`);
if (servedMd5 !== diskMd5) { console.log('✗ FAIL 服务身份不符'); process.exit(1); }

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
async function waitDiag(page, re, timeout = 45000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if ((await diagLines(page)).some((l) => re.test(l))) return true;
    await sleep(700);
  }
  return false;
}
async function listReady(page, timeout = 90000) {
  await page.waitForSelector('.list-item, .empty-state, .glass-search-trigger', { timeout }).catch(() => {});
  return page.evaluate(() => !!document.querySelector('.list-item, .empty-state, .glass-search-trigger'));
}
function makeMarkerZip(tag) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-marker-'));
  const memos = { version: 2, memos: [{ id: 'mark-1', title: 'EPHMARK-' + tag, pinned: false, createdAt: '2026-04-01T00:00:00.000Z', updatedAt: '2026-04-01T00:00:00.000Z', doc: [{ type: 'paragraph', children: [{ text: 'marker body' }] }] }] };
  fs.writeFileSync(path.join(dir, 'memos.json'), JSON.stringify(memos));
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ version: 1, attachments: {} }));
  const zip = path.join(dir, 'marker.zip');
  execSync(`cd ${dir} && python3 -c "import zipfile; z=zipfile.ZipFile('marker.zip','w'); z.write('memos.json'); z.write('manifest.json'); z.close()"`);
  return zip;
}
async function doImport(page, zipPath) {
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 15000 });
  await page.setInputFiles('#file-import', zipPath);
  await page.waitForSelector('.backup-modal', { timeout: 15000 });
  await page.click('.backup-modal .backup-btn.primary');
}
const bodyText = (page) => page.evaluate(() => document.body.innerText);

const browser = await webkit.launch();
const ctx = await browser.newContext();
const page = await ctx.newPage();
page.on('pageerror', (e) => L('  [pageerror]', String(e).slice(0, 160)));

// 首开：全程采样阻断层不得出现。
let blockedSeen = false;
const sampler = setInterval(() => {
  page.evaluate(() => !!document.querySelector('.storage-blocked')).then((v) => { if (v) blockedSeen = true; }).catch(() => {});
}, 400);
await page.goto(BASE, { waitUntil: 'load' });
ok('W1 列表就绪（易失上下文 IDB 会话）', await listReady(page));
await sleep(3000);
clearInterval(sampler);
ok('W1 全程未出现 .storage-blocked 阻断层', !blockedSeen && !(await page.evaluate(() => !!document.querySelector('.storage-blocked'))));
ok('W2 Diag backend 模式行', await waitDiag(page, /SQLITE backend mode=dual/),
  (await diagLines(page)).filter((l) => l.includes('backend mode')).pop() || 'none');
ok('W2 Diag session idb fallback 行（step=directory）', await waitDiag(page, /session idb fallback: sqlite unavailable step=directory/, 20000),
  (await diagLines(page)).filter((l) => l.includes('session idb fallback')).pop() || 'none');
ok('W2 Diag 无 occupied 行', !(await diagLines(page)).some((l) => l.includes('storage occupied')));
const banner = await page.evaluate(() => {
  const el = document.querySelector('.storage-readonly-banner');
  return el ? el.textContent.trim() : null;
});
ok('W3 横幅在场且为 ephemeral 支文案', !!banner && banner.includes('无痕/临时会话'), banner || 'no banner');
// IDB kv 降级标记在位。
const marker = await page.evaluate(() => new Promise((resolve) => {
  const req = indexedDB.open('moment-web');
  req.onerror = () => resolve('open-error');
  req.onsuccess = () => {
    const db = req.result;
    if (!db.objectStoreNames.contains('kv')) { resolve('no-kv-store'); return; }
    const get = db.transaction('kv', 'readonly').objectStore('kv').get('session_fallback_ts');
    get.onsuccess = () => resolve(get.result === undefined ? 'absent' : String(get.result));
    get.onerror = () => resolve('get-error');
  };
}));
ok('W3 IDB kv 会话降级标记 session_fallback_ts 在位', /^\d+$/.test(String(marker)) && Number(marker) > 0, 'marker=' + marker);

// 导入（save_all 走 IDB 臂）。导入后回列表页等标记篇
// 渲染（导入流程停在设置页，须先回列表再断言可见性）。
const zip = makeMarkerZip('WK');
await doImport(page, zip);
await page.goto(BASE, { waitUntil: 'load' });
await listReady(page);
await page.waitForFunction(() => document.body.innerText.includes('EPHMARK-WK'), { timeout: 30000 }).catch(() => {});
ok('W4 导入标记篇可见（save_all 经 IDB 臂）', (await bodyText(page)).includes('EPHMARK-WK'));

// 编辑（save delta 走 IDB 臂）。
const off = (await diagLines(page)).length;
await page.goto(BASE + '?open=mark-1', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 30000 }).catch(() => {});
const para = page.locator('.editor-body [data-bid]').first();
await para.click().catch(() => {});
await page.keyboard.type('E');
const idbSave = await waitDiag(page, /IDB save ok/, 30000);
const linesNow = await diagLines(page);
ok('W5 编辑保存走 IDB 臂（IDB save ok）', idbSave, linesNow.filter((l) => l.includes('save')).slice(-2).join(' | ') || 'none');
ok('W5 无 save_sync 行（未走 SQLite 主写）', !linesNow.slice(off).some((l) => l.includes('save_sync')));

// 重载：会话内 IDB 数据仍在、仍无阻断层、横幅仍在。
// 横幅随降级进入才渲染，轮询等第二条 fallback 行落盘
// 后再断言（首开同路径有时延，不裸采样）。
await page.goto(BASE, { waitUntil: 'load' });
ok('W6 重载后列表就绪', await listReady(page));
await page.waitForFunction(() => document.body.innerText.includes('EPHMARK-WK'), { timeout: 30000 }).catch(() => {});
ok('W6 重载后标记篇仍在（会话内 IDB 持久）', (await bodyText(page)).includes('EPHMARK-WK'));
ok('W6 重载后仍无阻断层', !(await page.evaluate(() => !!document.querySelector('.storage-blocked'))));
{
  const t0 = Date.now();
  let n = 0;
  while (Date.now() - t0 < 30000) {
    n = (await diagLines(page)).filter((l) => l.includes('session idb fallback')).length;
    if (n >= 2) break;
    await sleep(700);
  }
  ok('W6 重载后再次进入降级（fallback 行 ≥2）', n >= 2, 'count=' + n);
}
const banner2 = await page.evaluate(() => {
  const el = document.querySelector('.storage-readonly-banner');
  return el ? el.textContent.trim() : null;
});
ok('W6 重载后横幅仍在（ephemeral 支）', !!banner2 && banner2.includes('无痕/临时会话'), banner2 || 'no banner');
await page.goto(BASE + '?open=mark-1', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 30000 }).catch(() => {});
await sleep(1200);
ok('W6 重载后编辑内容仍在（键入字 E 已落盘）', (await bodyText(page)).includes('marker bodyE') || (await bodyText(page)).includes('Emarker body'),
  'editor text sampled');

await ctx.close();
await browser.close();
server.close();
L(fails === 0 ? 'PROBE EPHEMERAL WEBKIT ALL PASS' : `PROBE EPHEMERAL WEBKIT ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
