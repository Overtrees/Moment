// SQLite 阶段三演练探针（box 口径，Chromium）：对 dual
// 默认的 sqlite 构建做观察期形态五段演练——
//   T1 迁移→双写→对账：IDB 播种 302 篇生产形态存量 →
//      应用首启迁移（mode=dual / migrate ok / 收敛镜像 /
//      load source=sqlite）→ 深链编辑一篇 → save_sync 行
//      带 mirror=ok up=1 且 IDB 组装读已含编辑 → 冷启
//      （reload）对账 reconcile ok memos=302；
//   T2 漂移收敛：改 IDB 镜像一篇（标题）+ 注入幽灵篇
//      （条目 + order）→ 冷启对账 drift put=1 del=1 →
//      组装读已收敛（篡改还原、幽灵消失）；
//   T3 硬失败降级：Worker 脚本被桩替换（init 恒失败）→
//      dual 只读降级横幅 + Diag 降级行 + 列表读 IDB 镜
//      像 + 编辑被拒（EDIT save err、盘上不变）；撤桩重
//      启 → 正常迁移、数据完好；
//   T4 运行时开关：localStorage 置 idb → 冷启 mode=idb、
//      无 load source=sqlite、编辑走 IDB save ok 且无
//      save_sync；置 auto → 回 dual + 对账 ok；
//   T5 导入两段提交：dual 下导入小 zip → import_library
//      ok + idb mirror ok (import full) 两行、列表与组
//      装读均为导入态；大 zip 导入途中杀页 → 重开必为
//      完整旧态或完整新态、且对账行出现、组装读篇数与
//      加载源篇数一致。
// 证据口径：Chromium 口径（box 无头），真机门禁另行。
// 用法：node probe_sqlite_phase3.mjs [distDir]
//   默认 rust/apps/web/dist（须为 MYNOTE_SQLITE=1 构建）。
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(root, '..', '..');
let distDir = path.join(repo, 'rust', 'apps', 'web', 'dist');
if (process.argv[2]) distDir = path.resolve(process.argv[2]);
if (!fs.existsSync(path.join(distDir, 'storage-worker', 'worker.js'))) {
  console.log('✗ FAIL dist 不是 sqlite 构建（缺 storage-worker/worker.js）：' + distDir);
  process.exit(1);
}
const PORT = 8191;
const BASE = `http://localhost:${PORT}/`;
const BENCH = `${BASE}sqlite-bench/harness.html`;
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream', '.zip': 'application/zip' };
let stubWorker = false;
const STUB_JS = "self.onmessage = (e) => { const d = e.data || {}; self.postMessage({ id: d.id, ok: false, error: 'simulated worker failure' }); };";
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, BASE).pathname);
  if (stubWorker && p === '/storage-worker/worker.js') {
    res.writeHead(200, { 'Content-Type': 'text/javascript', 'Cache-Control': 'no-store', 'Cross-Origin-Resource-Policy': 'same-origin', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
    res.end(STUB_JS);
    return;
  }
  let file;
  if (p.startsWith('/sqlite-bench/')) {
    file = path.join(root, p.slice('/sqlite-bench/'.length));
  } else {
    file = path.join(distDir, p === '/' ? 'index.html' : p);
  }
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

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
async function newContext(tag) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-sqlite-p3-' + tag + '-'));
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
// 在 bench 页（同源）上以旧全量键形态播种 IDB。
async function seedLegacy(page, memosJsonText, manifestText) {
  return page.evaluate(async ([m, mf]) => {
    await new Promise((res, rej) => {
      const del = indexedDB.deleteDatabase('mynote-web');
      del.onsuccess = () => res(); del.onerror = () => rej(del.error); del.onblocked = () => res();
    });
    await new Promise((res, rej) => {
      const req = indexedDB.open('mynote-web', 2);
      req.onupgradeneeded = () => {
        const db = req.result;
        db.createObjectStore('kv');
        db.createObjectStore('memos');
        db.createObjectStore('attachments');
      };
      req.onsuccess = () => {
        const db = req.result;
        const tx = db.transaction('kv', 'readwrite');
        tx.objectStore('kv').put(m, 'memos_json');
        tx.objectStore('kv').put(mf, 'manifest_json');
        tx.oncomplete = () => { db.close(); res(); };
        tx.onerror = () => rej(tx.error);
      };
      req.onerror = () => rej(req.error);
    });
    return m.length;
  }, [memosJsonText, manifestText]);
}
// 分条组装读：{count, memos:[parsed...], ghostIds} 或 null。
const assembledRead = (page) => page.evaluate(() => new Promise((resolve) => {
  const req = indexedDB.open('mynote-web');
  req.onerror = () => resolve(null);
  req.onsuccess = () => {
    const db = req.result;
    if (!db.objectStoreNames.contains('kv')) { db.close(); resolve(null); return; }
    const tx = db.transaction(['kv', 'memos'], 'readonly');
    const kv = tx.objectStore('kv'), ms = tx.objectStore('memos');
    const out = {};
    kv.get('backup_meta').onsuccess = (e) => { out.meta = e.target.result; };
    kv.get('memos_order').onsuccess = (e) => { out.order = e.target.result; };
    ms.getAll().onsuccess = (e) => { out.vals = e.target.result; };
    ms.getAllKeys().onsuccess = (e) => { out.keys = e.target.result; };
    tx.oncomplete = () => {
      db.close();
      try {
        const order = JSON.parse(out.order || '[]').map(String);
        const byId = {};
        (out.keys || []).forEach((k, i) => { byId[String(k)] = out.vals[i]; });
        const memos = [];
        for (const id of order) {
          if (byId[id] === undefined) continue;
          memos.push(JSON.parse(byId[id]));
        }
        const ghostIds = Object.keys(byId).filter((k) => !order.includes(k));
        resolve({ count: memos.length, memos, ghostIds, hasMeta: !!out.meta });
      } catch { resolve(null); }
    };
    tx.onerror = () => { db.close(); resolve(null); };
  };
}));
async function doImport(page, zipPath) {
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .empty-state, .glass-search-trigger', { timeout: 30000 }).catch(() => {});
  await page.$eval('h1.page-title', (e) => e.click()).catch(() => {});
  await page.waitForSelector('.page-content', { timeout: 10000 }).catch(() => {});
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 10000 });
  await page.setInputFiles('#file-import', zipPath);
  await page.waitForSelector('.backup-modal', { timeout: 10000 });
  await page.click('.backup-modal .backup-btn.primary');
}
const fixtureText = fs.readFileSync(path.join(root, 'fixture', 'memos.json'), 'utf8');
const fixture = JSON.parse(fixtureText);
const UNIQUE_ID = (() => {
  const m = fixture.memos.find((x) => JSON.stringify(x).includes('鹭江夜泊'));
  return m ? String(m.id) : null;
})();
L('夹具：memos=' + fixture.memos.length + ' unique_id=' + UNIQUE_ID);

// ---------- T1 迁移 → 双写 → 对账全等 ----------
{
  const ctx = await newContext('t1');
  const seed = await ctx.newPage();
  await seed.goto(BENCH, { waitUntil: 'load' });
  const n = await seedLegacy(seed, fixtureText, '{"version":1,"attachments":{}}');
  ok('T1 IDB 播种完成', n > 1500000, n + ' chars');
  await seed.close();

  const page = await ctx.newPage();
  const t0 = Date.now();
  await page.goto(BASE, { waitUntil: 'load' });
  const listOk = await page.waitForFunction(
    () => document.body && document.body.innerText.includes('演练存量'),
    null, { timeout: 90000, polling: 500 }).then(() => true).catch(() => false);
  const coldMs = Date.now() - t0;
  ok('T1 首启列表呈现存量', listOk, 'cold_ms=' + coldMs);
  ok('T1 Diag 后端形态 dual', await waitDiag(page, /SQLITE backend mode=dual source=default/));
  ok('T1 Diag 迁移成功行', await diagHas(page, /SQLITE migrate ok memos=302/));
  ok('T1 Diag 收敛镜像行', await waitDiag(page, /SQLITE idb mirror converged after migrate/, 30000));
  ok('T1 Diag 加载源 sqlite', await waitDiag(page, /SQLITE load source=sqlite memos=302/, 30000));
  const asm = await assembledRead(page);
  ok('T1 IDB 镜像组装读 302 篇', !!asm && asm.count === 302, asm ? 'count=' + asm.count : 'null');

  // 双写编辑：深链打开唯一词篇，键入一个字。
  const off = (await diagLines(page)).length;
  await page.goto(BASE + '?open=' + encodeURIComponent(UNIQUE_ID), { waitUntil: 'load' });
  await page.waitForFunction(
    (o) => { try { const v = JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); return v.slice(o).some((l) => String(l).includes('EDIT page enter')); } catch { return false; } },
    off, { timeout: 30000, polling: 500 }).catch(() => {});
  const para = page.locator('.editor-body [data-bid]').first();
  await para.click().catch(() => {});
  await page.keyboard.type('Z');
  const saveOk = await waitDiag(page, /SQLITE save_sync .*mirror=ok up=1 del=0/, 30000);
  ok('T1 双写 save_sync 行带 mirror=ok up=1', saveOk,
    (await diagLines(page)).filter((l) => l.includes('save_sync')).pop() || 'no save_sync line');
  const asm2 = await assembledRead(page);
  const edited = asm2 && asm2.memos.find((m) => String(m.id) === UNIQUE_ID);
  ok('T1 IDB 镜像已含编辑（双写差量）', !!edited && JSON.stringify(edited).includes('Z'),
    edited ? 'edited memo found' : 'not found');

  // 冷启对账全等。
  await page.goto(BASE, { waitUntil: 'load' });
  const recOk = await waitDiag(page, /SQLITE reconcile ok memos=302/, 60000);
  ok('T1 冷启对账全等 reconcile ok', recOk,
    (await diagLines(page)).filter((l) => l.includes('reconcile')).pop() || 'no reconcile line');

  // ---------- T2 漂移收敛 ----------
  const tamper = await ctx.newPage();
  await tamper.goto(BENCH, { waitUntil: 'load' });
  const tRes = await tamper.evaluate((uid) => new Promise((resolve) => {
    const req = indexedDB.open('mynote-web');
    req.onsuccess = () => {
      const db = req.result;
      const tx = db.transaction(['kv', 'memos'], 'readwrite');
      const kv = tx.objectStore('kv'), ms = tx.objectStore('memos');
      ms.get(uid).onsuccess = (e) => {
        const raw = e.target.result;
        const v = JSON.parse(raw);
        v.title = 'TAMPERED-TITLE';
        ms.put(JSON.stringify(v), uid);
      };
      kv.get('memos_order').onsuccess = (e) => {
        const order = JSON.parse(e.target.result || '[]');
        order.push('ghost-999');
        kv.put(JSON.stringify(order), 'memos_order');
        ms.put(JSON.stringify({ id: 'ghost-999', title: 'ghost', pinned: false, createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z', doc: [] }), 'ghost-999');
      };
      tx.oncomplete = () => { db.close(); resolve('tampered'); };
      tx.onerror = () => { db.close(); resolve('txerr'); };
    };
    req.onerror = () => resolve('openerr');
  }), UNIQUE_ID);
  ok('T2 漂移注入完成', tRes === 'tampered', tRes);
  await tamper.close();
  await page.reload({ waitUntil: 'load' });
  const driftOk = await waitDiag(page, /SQLITE reconcile drift put=1 del=1/, 60000);
  ok('T2 对账漂移行 drift put=1 del=1', driftOk,
    (await diagLines(page)).filter((l) => l.includes('reconcile')).pop() || 'no reconcile line');
  const asm3 = await assembledRead(page);
  const restored = asm3 && asm3.memos.find((m) => String(m.id) === UNIQUE_ID);
  ok('T2 篡改已收敛还原', !!restored && restored.title !== 'TAMPERED-TITLE', restored ? restored.title : 'missing');
  ok('T2 幽灵篇已清除', !!asm3 && !asm3.memos.some((m) => String(m.id) === 'ghost-999') && asm3.count === 302,
    asm3 ? 'count=' + asm3.count : 'null');
  await ctx.close();
}

// ---------- T3 硬失败只读降级 ----------
{
  const ctx = await newContext('t3');
  const small = {
    version: 2,
    memos: [1, 2, 3].map((i) => ({
      id: 'deg-' + i, title: '降级篇 ' + i, pinned: false,
      createdAt: '2026-01-0' + i + 'T00:00:00.000Z', updatedAt: '2026-01-0' + i + 'T00:00:00.000Z',
      doc: [{ id: 'deg-' + i + '-p1', type: 'paragraph', children: [{ text: '降级正文 ' + i }] }],
    })),
  };
  const seed = await ctx.newPage();
  await seed.goto(BENCH, { waitUntil: 'load' });
  await seedLegacy(seed, JSON.stringify(small), '{"version":1,"attachments":{}}');
  await seed.close();
  stubWorker = true;
  const page = await ctx.newPage();
  await page.goto(BASE, { waitUntil: 'load' });
  const banner = await page.waitForSelector('.storage-readonly-banner', { timeout: 30000 }).then(() => true).catch(() => false);
  ok('T3 只读横幅出现', banner);
  ok('T3 Diag 降级行', await waitDiag(page, /SQLITE backend unavailable, readonly fallback/, 30000));
  const listTxt = await page.evaluate(() => document.body.innerText);
  ok('T3 列表读 IDB 镜像呈现', listTxt.includes('降级篇'));
  // 编辑应被拒、盘上不变。
  await page.goto(BASE + '?open=deg-1', { waitUntil: 'load' });
  await sleep(2500);
  const para = page.locator('.editor-body [data-bid]').first();
  await para.click().catch(() => {});
  await page.keyboard.type('Q');
  const rejected = await waitDiag(page, /EDIT save err/, 20000);
  ok('T3 只读态编辑被拒（EDIT save err）', rejected);
  const asm = await assembledRead(page);
  const m1 = asm && asm.memos.find((m) => m.id === 'deg-1');
  ok('T3 盘上镜像未被写入', !!m1 && !JSON.stringify(m1).includes('Q'));
  // 撤桩重启：正常迁移、数据完好。SW 已把桩预缓存进
  // CORE，先注销 SW + 清缓存（模拟部署修复后的干净态）。
  stubWorker = false;
  const clean = await ctx.newPage();
  await clean.goto(BENCH, { waitUntil: 'load' });
  await clean.evaluate(async () => {
    if (navigator.serviceWorker) {
      const regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map((r) => r.unregister()));
    }
    if (window.caches) {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    }
  });
  await clean.close();
  await page.goto(BASE, { waitUntil: 'load' });
  ok('T3 撤桩后迁移恢复', await waitDiag(page, /SQLITE migrate ok memos=3/, 60000));
  ok('T3 撤桩后加载源 sqlite', await diagHas(page, /SQLITE load source=sqlite memos=3/));
  await ctx.close();
}

// ---------- T4 运行时开关 + T5 导入两段 ----------
{
  const ctx = await newContext('t4');
  const small = {
    version: 2,
    memos: [1, 2].map((i) => ({
      id: 'sw-' + i, title: '开关篇 ' + i, pinned: false,
      createdAt: '2026-02-0' + i + 'T00:00:00.000Z', updatedAt: '2026-02-0' + i + 'T00:00:00.000Z',
      doc: [{ id: 'sw-' + i + '-p1', type: 'paragraph', children: [{ text: '开关正文 ' + i }] }],
    })),
  };
  const seed = await ctx.newPage();
  await seed.goto(BENCH, { waitUntil: 'load' });
  await seedLegacy(seed, JSON.stringify(small), '{"version":1,"attachments":{}}');
  await seed.close();
  const page = await ctx.newPage();
  await page.goto(BASE, { waitUntil: 'load' });
  ok('T4 dual 首启迁移', await waitDiag(page, /SQLITE migrate ok memos=2/, 60000));

  await page.evaluate(() => localStorage.setItem('moment_backend_v1', 'idb'));
  const sqliteLoads = await diagCount(page, /SQLITE load source=sqlite/);
  await page.reload({ waitUntil: 'load' });
  ok('T4 开关 idb 生效（mode=idb）', await waitDiag(page, /SQLITE backend mode=idb source=stored/, 30000));
  await sleep(2000);
  ok('T4 idb 态不再走 sqlite 加载', (await diagCount(page, /SQLITE load source=sqlite/)) === sqliteLoads);
  const off = (await diagLines(page)).length;
  await page.goto(BASE + '?open=sw-1', { waitUntil: 'load' });
  await sleep(2500);
  const para = page.locator('.editor-body [data-bid]').first();
  await para.click().catch(() => {});
  await page.keyboard.type('W');
  const idbSave = await waitDiag(page, /IDB save ok up=1 del=0/, 20000);
  ok('T4 idb 态编辑走分条保存', idbSave);
  const newLines = (await diagLines(page)).slice(off);
  ok('T4 idb 态无 save_sync 行', !newLines.some((l) => l.includes('save_sync')));

  await page.evaluate(() => localStorage.setItem('moment_backend_v1', 'auto'));
  await page.goto(BASE, { waitUntil: 'load' });
  ok('T4 回 auto 恢复 dual', await waitDiag(page, /SQLITE backend mode=dual source=stored/, 30000));
  ok('T4 回 dual 对账全等（镜像含 idb 期编辑）', await waitDiag(page, /SQLITE reconcile (ok|drift)/, 60000),
    (await diagLines(page)).filter((l) => l.includes('reconcile')).pop() || 'none');

  // ---------- T5 导入两段提交 ----------
  const imp = {
    version: 2,
    memos: [1, 2, 3, 4].map((i) => ({
      id: 'imp-' + i, title: '导入篇 ' + i, pinned: false,
      createdAt: '2026-03-0' + i + 'T00:00:00.000Z', updatedAt: '2026-03-0' + i + 'T00:00:00.000Z',
      doc: [{ id: 'imp-' + i + '-p1', type: 'paragraph', children: [{ text: '导入正文 ' + i }] }],
    })),
  };
  // zip 由运行脚本预先打包（memos.json=imp 库 + 空附件
  // manifest），路径经环境变量传入。
  const zipPath = process.env.P3_IMPORT_ZIP;
  if (zipPath && fs.existsSync(zipPath)) {
    await doImport(page, zipPath);
    ok('T5 导入 SQLite 段成功行', await waitDiag(page, /SQLITE import_library ok/, 60000));
    ok('T5 导入 IDB 全量镜像行', await diagHas(page, /import_library ok.*idb mirrored/));
    await sleep(1500);
    const asm = await assembledRead(page);
    ok('T5 组装读为导入态 4 篇', !!asm && asm.count === 4 && asm.memos.every((m) => String(m.id).startsWith('imp-')),
      asm ? 'count=' + asm.count : 'null');
    await page.reload({ waitUntil: 'load' });
    ok('T5 导入后加载源 sqlite memos=4', await waitDiag(page, /SQLITE load source=sqlite memos=4/, 60000));
  } else {
    L('⚠ T5 跳过：P3_IMPORT_ZIP 未提供或不存在');
  }
  await ctx.close();
}

// ---------- T5b 导入途中杀页 ----------
{
  const bigZip = process.env.P3_BIG_ZIP;
  if (bigZip && fs.existsSync(bigZip)) {
    const ctx = await newContext('t5b');
    const small = {
      version: 2,
      memos: [{ id: 'pre-1', title: '杀前篇', pinned: false, createdAt: '2026-04-01T00:00:00.000Z', updatedAt: '2026-04-01T00:00:00.000Z', doc: [{ id: 'pre-1-p1', type: 'paragraph', children: [{ text: '杀前正文' }] }] }],
    };
    const seed = await ctx.newPage();
    await seed.goto(BENCH, { waitUntil: 'load' });
    await seedLegacy(seed, JSON.stringify(small), '{"version":1,"attachments":{}}');
    await seed.close();
    const page = await ctx.newPage();
    await page.goto(BASE, { waitUntil: 'load' });
    ok('T5b dual 首启迁移', await waitDiag(page, /SQLITE migrate ok memos=1/, 60000));
    await page.$eval('h1.page-title', (e) => e.click()).catch(() => {});
    await page.waitForSelector('.page-content', { timeout: 10000 }).catch(() => {});
    await page.click('.set-row:has-text("备份与恢复")');
    await page.waitForSelector('#file-import', { state: 'attached', timeout: 10000 });
    await page.setInputFiles('#file-import', bigZip);
    await page.waitForSelector('.backup-modal', { timeout: 10000 });
    await page.click('.backup-modal .backup-btn.primary');
    await sleep(150);
    await page.close().catch(() => {});
    const page2 = await ctx.newPage();
    await page2.goto(BASE, { waitUntil: 'load' });
    const applied = await waitDiag(page2, /persisted state applied|SQLITE load source=sqlite/, 90000);
    ok('T5b 杀页后重开可加载', applied);
    ok('T5b 对账行出现（收敛兜底）', await waitDiag(page2, /SQLITE reconcile (ok|drift)/, 60000),
      (await diagLines(page2)).filter((l) => l.includes('reconcile')).pop() || 'none');
    const srcLine = (await diagLines(page2)).filter((l) => l.includes('load source=sqlite')).pop() || '';
    const mN = srcLine.match(/memos=(\d+)/);
    const asm = await assembledRead(page2);
    ok('T5b 终态完整（旧 1 或新 302）且镜像与加载源一致',
      !!mN && !!asm && asm.count === Number(mN[1]) && (asm.count === 1 || asm.count === 302),
      'src=' + srcLine + ' asm=' + (asm ? asm.count : 'null'));
    await ctx.close();
  } else {
    L('⚠ T5b 跳过：P3_BIG_ZIP 未提供或不存在');
  }
}

L(fails === 0 ? 'PROBE SQLITE PHASE3 ALL PASS' : `PROBE SQLITE PHASE3 FAILS=${fails}`);
process.exit(fails === 0 ? 0 : 1);
