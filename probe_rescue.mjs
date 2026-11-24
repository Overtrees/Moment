// 专用探针：救援层（index.html 外壳脚本）。
// 守的行为（用户 2026-11-24 拍板「先取证再修复」，设计
// 见 diagnose_click_dead_round2.md）：应用冻屏/点不动时
// 设置页进不去、Diag 读不出来——救援层先于 wasm 执行、
// 不依赖应用存活：每次加载写状态快照（只记元数据）到
// mynote_rescue_log_v1；12s 未见 boot-ok 标记出救援小
// 条；?rescue=1 直达面板；面板可导出诊断（Diag 全文+
// 救援日志）、修复启动（只注销 SW + 清 Cache Storage，
// 绝不动 IDB/localStorage）、关闭；应用下次成功启动把
// 救援动作折入 Diag 成 RESCUE 行（diag.rs drain）。
// 手法：自带静态服务（COOP/COEP/CORP + no-store 口径
// 同 harness），带 wasm 击杀开关——服务端对 *.wasm 回
// 404 模拟应用死亡（走服务端而非 page.route：SW 的网
// 络优先 fetch 也必须被挡住，且新 profile 无缓存可回
// 退，死亡形态确定）。
// 场景 A：健康启动——boot-ok 落、快照落（只记元数据）、
//   12s 看门狗不出条。
// 场景 B：死亡启动——小条出 → 面板 → 导出含 Diag 标记
//   与快照 → 修复启动 → 应用复活、Diag 有 RESCUE 行、
//   预置的 IDB 库与 LS 键逐项还在。
// 场景 C：?rescue=1 在健康应用上直达面板、可关。
// 用法：node probe_rescue.mjs [distDir]
//   默认 rust/apps/web/dist（相对仓库根）；run_all_tests
//   传入的 baseURL 是 http 串、本探针需自控服务而忽略之。
import { chromium } from 'playwright-core';
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
const PORT = 8141;
const BASE = `http://localhost:${PORT}/`;
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

// ── 静态服务（带 wasm 击杀开关） ────────────────────
let killWasm = false;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
const server = http.createServer({ keepAliveTimeout: 30000 }, (req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  if (killWasm && p.endsWith('.wasm')) { res.writeHead(404); res.end('killed'); return; }
  const file = path.join(distDir, p);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('nf'); return; }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'same-origin',
    });
    res.end(data);
  });
});
await new Promise((r) => server.listen(PORT, r));

const waitCtrl = async (page) => {
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 30000 });
};
const bootApp = async (page) => {
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await waitCtrl(page);
  await page.waitForTimeout(800);
};
const diagHas = async (page, substr, tries = 25) => {
  for (let i = 0; i < tries; i++) {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
    });
    if (lines.some((l) => String(l).includes(substr))) return true;
    await page.waitForTimeout(400);
  }
  return false;
};
const rescueLog = (page) => page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('mynote_rescue_log_v1') || '[]'); } catch (e) { return []; }
});

// ── 场景 A：健康启动 ────────────────────────────────
const dirA = fs.mkdtempSync(path.join(os.tmpdir(), 'rescue-profA-'));
const ctxA = await chromium.launchPersistentContext(dirA, { executablePath: exe, args: ['--no-sandbox'] });
const pageA = await ctxA.newPage();
pageA.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
// 快照由外壳在加载起点写、应用 diag::init 的 drain 会
// 把纯快照日志静默清除（设计口径）——断言必须赶在
// drain 之前：goto 一返回就紧窗轮询日志键。
const t0 = Date.now();
await pageA.goto(BASE, { waitUntil: 'load' });
let snapA = null;
for (let i = 0; i < 40 && !snapA; i++) {
  const log = await rescueLog(pageA).catch(() => []);
  snapA = log.find((e) => e.kind === 'snapshot');
  if (!snapA) await pageA.waitForTimeout(100);
}
ok('A 状态快照已落（drain 前捕获）', !!snapA);
if (snapA) {
  const metaOnly = (snapA.ls || []).every((e) => Object.keys(e).every((k) => ['k', 'len', 'lines'].includes(k)));
  ok('A 快照只记元数据（无值字段）', metaOnly);
  ok('A 快照含 SW/缓存/IDB 清单', Array.isArray(snapA.sw) && Array.isArray(snapA.caches) && Array.isArray(snapA.idb));
}
await pageA.waitForSelector('.list-item', { timeout: 30000 });
await waitCtrl(pageA);
await pageA.evaluate(() => localStorage.setItem('probe_rescue_keep', '1'));
let bootOk = null;
for (let i = 0; i < 15 && !bootOk; i++) {
  bootOk = await pageA.evaluate(() => localStorage.getItem('mynote_boot_ok'));
  if (!bootOk) await pageA.waitForTimeout(400);
}
ok('A boot-ok 标记已落', !!bootOk, String(bootOk));
ok('A 健康启动 Diag 无 RESCUE 行（纯快照静默清除）', !(await diagHas(pageA, 'RESCUE', 3)));
const elapsed = Date.now() - t0;
if (elapsed < 13500) await pageA.waitForTimeout(13500 - elapsed);
ok('A 健康时 12s 看门狗不出救援条', (await pageA.locator('#mn-rescue-bar').count()) === 0);
ok('A 健康时无救援面板', (await pageA.locator('#mn-rescue').count()) === 0);

// ── 场景 C：?rescue=1 直达（借 A 的健康 profile） ──
await pageA.goto(BASE + '?rescue=1', { waitUntil: 'load' });
await pageA.waitForSelector('#mn-rescue', { timeout: 8000 });
const panelTitle = await pageA.locator('#mn-rescue .mn-rescue-title').innerText();
ok('C ?rescue=1 直达面板', panelTitle === '应用救援', panelTitle);
await pageA.locator('#mn-rescue .mn-rescue-close').click();
await pageA.waitForTimeout(300);
ok('C 面板可关闭', (await pageA.locator('#mn-rescue').count()) === 0);
ok('C 应用仍健康', (await pageA.locator('.list-item').count()) > 0);
await ctxA.close();

// ── 场景 B：应用死亡 → 救援全链 ────────────────────
killWasm = true;
const dirB = fs.mkdtempSync(path.join(os.tmpdir(), 'rescue-profB-'));
const ctxB = await chromium.launchPersistentContext(dirB, { executablePath: exe, args: ['--no-sandbox'] });
await ctxB.addInitScript(() => {
  try {
    // 只种一次（sessionStorage 守卫）：修复后重载的新文
    // 档不得重种，否则「LS 还在」断言会被种子假绿。
    if (sessionStorage.getItem('__rescue_probe_seeded')) return;
    sessionStorage.setItem('__rescue_probe_seeded', '1');
    localStorage.setItem('mynote_diag_v1', JSON.stringify(['[00:00:01] TEST rescue-probe-marker']));
    localStorage.setItem('probe_rescue_keep', '1');
  } catch (e) {}
});
const pageB = await ctxB.newPage();
pageB.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
await pageB.goto(BASE, { waitUntil: 'load' });
// 预置一个 IDB 库（修复启动绝不动 IDB 的判据物）
await pageB.evaluate(() => new Promise((resolve) => {
  const req = indexedDB.open('probe-keep-db', 1);
  req.onupgradeneeded = () => req.result.createObjectStore('keep', { keyPath: 'id' });
  req.onsuccess = () => {
    const tx = req.result.transaction('keep', 'readwrite');
    tx.objectStore('keep').put({ id: 1, v: 'alive' });
    tx.oncomplete = () => { req.result.close(); resolve(); };
  };
  req.onerror = () => resolve();
}));
await pageB.waitForSelector('#mn-rescue-bar', { timeout: 25000 });
const barTextB = await pageB.locator('#mn-rescue-bar .mn-rescue-bar-text').innerText();
ok('B 死亡 12s 内救援条出现', barTextB === '应用似乎没有响应', barTextB);
const snapB = (await rescueLog(pageB)).find((e) => e.kind === 'snapshot');
const snapBDiag = snapB && (snapB.ls || []).find((x) => x.k === 'mynote_diag_v1');
ok('B 死亡加载的快照已落（Diag 标记 1 行）', !!snapBDiag && snapBDiag.lines === 1, JSON.stringify(snapBDiag));
await pageB.locator('#mn-rescue-bar .mn-rescue-bar-btn').click();
await pageB.waitForSelector('#mn-rescue', { timeout: 8000 });
ok('B 小条点开面板', true);
// headless 下 navigator.share 可能吞掉下载：强制走下载路
await pageB.evaluate(() => {
  try { Object.defineProperty(navigator, 'canShare', { value: () => false }); } catch (e) {}
});
const dlP = pageB.waitForEvent('download', { timeout: 15000 });
await pageB.locator('#mn-rescue .mn-rescue-export').click();
const dl = await dlP;
const dlPath = path.join(os.tmpdir(), 'rescue-export-' + Date.now() + '.txt');
await dl.saveAs(dlPath);
const exportText = fs.readFileSync(dlPath, 'utf8');
ok('B 导出含 Diag 标记行', exportText.includes('rescue-probe-marker'));
ok('B 导出含救援日志与快照', exportText.includes('Rescue log') && exportText.includes('"kind": "snapshot"'));
// 修复瞬间清零的直读观察（导航可能打断 evaluate，失败
// 则以事后 Diag 的 RESCUE 回执为据，二者取其一）
const zeroP = pageB.evaluate(() => new Promise((resolve) => {
  const t0 = Date.now();
  const iv = setInterval(async () => {
    try {
      const regs = await navigator.serviceWorker.getRegistrations();
      const cks = await caches.keys();
      if (regs.length === 0 && cks.length === 0) { clearInterval(iv); resolve(true); }
      else if (Date.now() - t0 > 4000) { clearInterval(iv); resolve(false); }
    } catch (e) { clearInterval(iv); resolve(false); }
  }, 100);
})).catch(() => false);
await pageB.locator('#mn-rescue .mn-rescue-repair').click();
killWasm = false; // 修复的重载必须能取到好 wasm
const zeroObs = await zeroP;
await pageB.waitForSelector('.list-item', { timeout: 30000 });
await waitCtrl(pageB);
ok('B 修复后应用复活', true);
const keepLs = await pageB.evaluate(() => localStorage.getItem('probe_rescue_keep'));
ok('B 修复后 LS 键还在', keepLs === '1', String(keepLs));
const keepIdb = await pageB.evaluate(() => new Promise((resolve) => {
  const req = indexedDB.open('probe-keep-db', 1);
  req.onsuccess = () => {
    const tx = req.result.transaction('keep', 'readonly');
    const get = tx.objectStore('keep').get(1);
    get.onsuccess = () => { const v = get.result && get.result.v; req.result.close(); resolve(v || null); };
    get.onerror = () => resolve(null);
  };
  req.onerror = () => resolve(null);
}));
ok('B 修复后 IDB 数据还在', keepIdb === 'alive', String(keepIdb));
const rescueRepair = await diagHas(pageB, 'RESCUE repair boot');
ok('B Diag 有 RESCUE repair 回执', rescueRepair);
ok('B Diag 有 RESCUE snapshot 摘要', await diagHas(pageB, 'RESCUE snapshot'));
ok('B SW/缓存清零（直读或回执）', zeroObs || rescueRepair, 'zeroObs=' + zeroObs);
await pageB.waitForTimeout(600);
ok('B 复活后无救援条残留', (await pageB.locator('#mn-rescue-bar').count()) === 0);
await ctxB.close();

server.close();
fs.rmSync(dirA, { recursive: true, force: true });
fs.rmSync(dirB, { recursive: true, force: true });
L(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
