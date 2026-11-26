// 存储阻断页五项统一/根治 专项探针（box Chromium 口径）：
//   S1 呈现三项 + 接管（同 context 双页）：阻断层 computed
//      background 与根色（body）逐值相等、backdrop-filter
//      none、进场动画 sheetIn/0.25s；occupied Diag 行含
//      结构化分类 install step=handle；点「立即重试」→ is-retrying 在场、
//      按钮 opacity 0.55、约 1.2s 后回落仍可再点；关第一页
//      后量接管总延迟与呈现同步差（层消失 − 列表可见）。
//   S2 池分区（两独立 context 模拟两分区）：同开互不阻
//      断、OPFS 池目录互不相同、A 导入标记篇后 B 不可见。
//   S3 存量升级（指纹键缺失分支）：预置 default 池数据 →
//      删指纹键 → 重开仍走 default（IDB 存量判定）、数据
//      在；全新 context 则铸 fp 指纹。
// 用法：node probe_blocked_ui.mjs [distDir]
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';

const distDir = process.argv[2] ? path.resolve(process.argv[2]) : '/workspace/moment-blockedui/dist';
if (!fs.existsSync(path.join(distDir, 'storage-worker', 'worker.js'))) {
  console.log('✗ FAIL dist 不是 sqlite 构建：' + distDir);
  process.exit(1);
}
const PORT = 8231;
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
// 开跑前核服务身份：本地直读 dist wasm 与被服务字节同 md5。
const servedMd5 = await new Promise((resolve) => {
  http.get(`${BASE}moment-web_bg.wasm`, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => {
      import('node:crypto').then(({ createHash }) => resolve(createHash('md5').update(Buffer.concat(chunks)).digest('hex')));
    });
  });
});
const diskMd5 = (await import('node:crypto')).createHash('md5').update(fs.readFileSync(path.join(distDir, 'moment-web_bg.wasm'))).digest('hex');
console.log(`served wasm md5=${servedMd5} disk md5=${diskMd5} ${servedMd5 === diskMd5 ? 'MATCH' : 'MISMATCH'}`);
if (servedMd5 !== diskMd5) { console.log('✗ FAIL 服务身份不符'); process.exit(1); }

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function newContext(tag) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-blockedui-' + tag + '-'));
  return chromium.launchPersistentContext(dir, { executablePath: exe, args: ['--no-sandbox'] });
}
const diagLines = (page) => page.evaluate(() => {
  try {
    const raw = localStorage.getItem('moment_diag_v1') || '[]';
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.map(String) : String(v).split('\n');
  } catch { return []; }
});
const diagHas = async (page, re) => (await diagLines(page)).some((l) => re.test(l));
const diagCount = async (page, re) => (await diagLines(page)).filter((l) => re.test(l)).length;
async function waitDiag(page, re, timeout = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (await diagHas(page, re)) return true;
    await sleep(400);
  }
  return false;
}
async function listReady(page, timeout = 60000) {
  // 就绪判据：列表壳在场 + 后端形态行（每启必打）。注意
  // 新鲜首启两后端皆空走种子路径、不打 load source 行，
  // 不能以该行判就绪（阶段三既有口径）。
  await page.waitForSelector('.list-item, .empty-state, .glass-search-trigger', { timeout }).catch(() => {});
  return waitDiag(page, /SQLITE backend mode=/, timeout);
}
async function markerVisible(page, marker, timeout = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if ((await bodyText(page)).includes(marker)) return true;
    await sleep(1000);
  }
  return false;
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
const bodyText = (page) => page.evaluate(() => document.body.innerText);

// ---------- S1 ----------
{
  L('--- S1 呈现/接管（同 context 双页）---');
  const ctx = await newContext('s1');
  const p1 = await ctx.newPage();
  await p1.goto(BASE, { waitUntil: 'load' });
  ok('S1 第一页列表就绪（sqlite 加载）', await listReady(p1));
  const p2 = await ctx.newPage();
  await p2.goto(BASE, { waitUntil: 'load' });
  const blocked = await p2.waitForSelector('.storage-blocked', { timeout: 30000 }).then(() => true).catch(() => false);
  ok('S1 第二页出现阻断层', blocked);
  const st = await p2.evaluate(() => {
    const el = document.querySelector('.storage-blocked');
    const cs = getComputedStyle(el);
    const btn = el.querySelector('.empty-state-btn');
    return {
      bg: cs.backgroundColor,
      bodyBg: getComputedStyle(document.body).backgroundColor,
      rootVar: getComputedStyle(document.documentElement).getPropertyValue('--mn-root-bg').trim(),
      bf: cs.backdropFilter,
      anim: cs.animationName,
      dur: cs.animationDuration,
      btnOpacity: btn ? getComputedStyle(btn).opacity : null,
    };
  });
  L('   styles:', JSON.stringify(st));
  ok('S1 阻断层底色与根色（body）逐值相等', st.bg === st.bodyBg, `${st.bg} vs ${st.bodyBg}`);
  ok('S1 无 backdrop-filter 玻璃', st.bf === 'none', st.bf);
  ok('S1 进场动画 sheetIn', st.anim.split(',').map((s) => s.trim()).includes('sheetIn'), st.anim);
  ok('S1 进场时长 0.25s', st.dur.split(',').map((s) => s.trim()).includes('0.25s'), st.dur);
  ok('S1 occupied Diag 行含 install step=handle', await waitDiag(p2, /storage occupied.*install step=handle/, 30000),
    (await diagLines(p2)).filter((l) => l.includes('occupied')).pop() || 'none');
  // 重试按钮反馈
  await p2.click('.storage-blocked .empty-state-btn');
  let busySeen = false; let busyOpacity = null;
  const tb = Date.now();
  while (Date.now() - tb < 600) {
    const s = await p2.evaluate(() => {
      const el = document.querySelector('.storage-blocked');
      const btn = el ? el.querySelector('.empty-state-btn') : null;
      return el ? { cls: el.classList.contains('is-retrying'), op: btn ? getComputedStyle(btn).opacity : null } : null;
    }).catch(() => null);
    if (s && s.cls) { busySeen = true; busyOpacity = s.op; break; }
    await sleep(30);
  }
  ok('S1 点重试后 is-retrying 忙碌态在场', busySeen);
  ok('S1 忙碌态按钮 opacity 0.55', busyOpacity === '0.55', String(busyOpacity));
  await sleep(1800);
  const after = await p2.evaluate(() => {
    const el = document.querySelector('.storage-blocked');
    return el ? { cls: el.classList.contains('is-retrying'), present: true } : { present: false };
  });
  ok('S1 反馈回落后仍阻断且可再点', after.present && !after.cls, JSON.stringify(after));
  // 接管计时
  const t0 = Date.now();
  await p1.close();
  let tList = -1; let tGone = -1;
  while (Date.now() - t0 < 25000) {
    const s = await p2.evaluate(() => ({
      list: !!document.querySelector('.list-item, .glass-search-trigger'),
      gone: !document.querySelector('.storage-blocked'),
    })).catch(() => ({ list: false, gone: false }));
    const now = Date.now() - t0;
    if (s.list && tList < 0) tList = now;
    if (s.gone) { tGone = now; break; }
    await sleep(20);
  }
  ok('S1 关第一页后接管成功（层消失）', tGone >= 0, `close→gone=${tGone}ms`);
  L(`   接管总延迟 close→gone=${tGone}ms；列表可见=${tList}ms；呈现同步差 gone-list=${tList >= 0 && tGone >= 0 ? tGone - tList : 'n/a'}ms`);
  await ctx.close();
}

// ---------- S2 ----------
{
  L('--- S2 两分区独立（双 context）---');
  const ctxA = await newContext('s2a');
  const ctxB = await newContext('s2b');
  const pa = await ctxA.newPage();
  const pb = await ctxB.newPage();
  await Promise.all([pa.goto(BASE, { waitUntil: 'load' }), pb.goto(BASE, { waitUntil: 'load' })]);
  const ra = await listReady(pa);
  const rb = await listReady(pb);
  ok('S2 两 context 均加载完成', ra && rb);
  await sleep(3000);
  const blockedA = await pa.evaluate(() => !!document.querySelector('.storage-blocked'));
  const blockedB = await pb.evaluate(() => !!document.querySelector('.storage-blocked'));
  ok('S2 两分区同开互不阻断', !blockedA && !blockedB, `A=${blockedA} B=${blockedB}`);
  ok('S2 A 池解析为 fp', await diagHas(pa, /pool resolved: fp hash=/));
  ok('S2 B 池解析为 fp', await diagHas(pb, /pool resolved: fp hash=/));
  const poolDirs = async (page) => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const names = [];
    for await (const [name] of root.entries()) names.push(name);
    return names.filter((n) => n.startsWith('.opfs-moment'));
  });
  const dirsA = await poolDirs(pa);
  const dirsB = await poolDirs(pb);
  L('   poolDirs A:', JSON.stringify(dirsA), ' B:', JSON.stringify(dirsB));
  ok('S2 两分区池目录不同', dirsA.length >= 1 && dirsB.length >= 1 && dirsA[0] !== dirsB[0]);
  const zip = makeMarkerZip('A');
  await doImport(pa, zip);
  ok('S2 A 导入 Diag ok', await waitDiag(pa, /IMPORT ok memos=1/, 30000));
  await pa.reload({ waitUntil: 'load' });
  await listReady(pa);
  ok('S2 A 导入标记篇可见（重载后列表）', await markerVisible(pa, 'POOLMARK-A'));
  await pb.reload({ waitUntil: 'load' });
  await listReady(pb);
  ok('S2 B 看不到 A 的标记篇（数据集独立）', !(await bodyText(pb)).includes('POOLMARK-A'));
  await ctxA.close();
  await ctxB.close();
}

// ---------- S3 ----------
{
  L('--- S3 存量升级（默认池不换池）---');
  const ctx = await newContext('s3');
  await ctx.addInitScript(() => {
    if (!sessionStorage.getItem('__poolseed')) {
      localStorage.setItem('moment_pool_v1', 'default');
      sessionStorage.setItem('__poolseed', '1');
    }
  });
  const page = await ctx.newPage();
  await page.goto(BASE, { waitUntil: 'load' });
  ok('S3 预置 default 指纹 → 默认池', (await listReady(page)) && (await diagHas(page, /pool resolved: default/)));
  const zip = makeMarkerZip('S3');
  await doImport(page, zip);
  ok('S3 默认池写入标记篇（导入 Diag）', await waitDiag(page, /IMPORT ok memos=1/, 30000));
  await page.evaluate(() => localStorage.removeItem('moment_pool_v1'));
  await page.reload({ waitUntil: 'load' });
  // 同标签 reload 后旧 Worker 句柄释放可滞后（占用等待+
  // 重建接管），第二行解析与数据呈现都按轮询等（≤120s）。
  let secondDefault = false;
  for (let i = 0; i < 60 && !secondDefault; i++) {
    secondDefault = (await diagCount(page, /pool resolved: default/)) >= 2;
    if (!secondDefault) await sleep(2000);
  }
  ok('S3 删指纹键后重开仍为默认池（IDB 存量判定）', secondDefault,
    (await diagLines(page)).filter((l) => l.includes('pool resolved')).join(' | '));
  ok('S3 数据完好（标记篇仍在、未换池）', await markerVisible(page, 'POOLMARK-S3', 120000));
  await ctx.close();
  const ctxD = await newContext('s3d');
  const pd = await ctxD.newPage();
  await pd.goto(BASE, { waitUntil: 'load' });
  ok('S3 全新分区铸 fp 指纹', (await listReady(pd)) && (await diagHas(pd, /pool resolved: fp hash=/)));
  await ctxD.close();
}

L(fails === 0 ? 'PROBE BLOCKED UI ALL PASS' : `PROBE BLOCKED UI FAILS=${fails}`);
process.exit(fails === 0 ? 0 : 1);
