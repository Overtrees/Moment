// 专用探针：SW 新版本可用提示（index.html 外壳脚本）。
// 守的行为（用户 2026-11-24 拍板）：现行 SW 静默更新下，
// 已打开页面一直跑内存旧版而用户无从知晓——外壳脚本检
// 测到更新装好（installed 且已有 controller）时出底部提
// 示条，点「点击更新」才重载到新版；首装绝不出提示；关
// 闭后同一版本不再重复弹；展示/点击事件经 localStorage
// 暂存（mynote_swupd_pending_v1），应用启动时读入 Diag
// 成 SWUPD 行（应用死了也不丢、下次启动补记）。
// 手法：自带静态服务（同 harness 的 COOP/COEP/CORP 口
// 径、no-store 防 HTTP 缓存掩盖换代）服务一份可变目录：
// 先放「旧代」= 当前 dist 仅改 sw.js 的 VERSION 戳（缓
// 存代与应用戳随之而异，模拟已带本功能的上一版），持
// 久 profile 建 SW 后原地换成新代 dist，以
// visibilitychange 触发 registration.update() 查更新。
// 场景 A 点更新全链；场景 B 关闭后同版不再弹。
// 用法：node probe_sw_update.mjs [distDir]
//   默认 rust/apps/web/dist（相对仓库根）；run_all_tests
//   传入的 baseURL 是 http 串、本探针需自控服务换代而
//   忽略之。
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
const PORT = 8137;
const BASE = `http://localhost:${PORT}/`;
const OLD_VER = 'probeold01';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const newVer = (() => {
  const t = fs.readFileSync(path.join(distDir, 'sw.js'), 'utf8');
  const m = /VERSION = '([^']+)'/.exec(t);
  return m ? m[1] : '';
})();
if (!newVer || newVer === OLD_VER) { L('✗ FAIL 无法解析新代 VERSION', newVer); process.exit(1); }
L('新代 VERSION =', newVer, '旧代模拟戳 =', OLD_VER);

// ── 可变目录静态服务 ────────────────────────────────
const serveDir = fs.mkdtempSync(path.join(os.tmpdir(), 'swupd-serve-'));
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
const server = http.createServer({ keepAliveTimeout: 30000 }, (req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  const file = path.join(serveDir, p);
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

function stageGeneration(ver) {
  fs.rmSync(serveDir, { recursive: true, force: true });
  fs.mkdirSync(serveDir, { recursive: true });
  fs.cpSync(distDir, serveDir, { recursive: true });
  if (ver !== newVer) {
    const swp = path.join(serveDir, 'sw.js');
    fs.writeFileSync(swp, fs.readFileSync(swp, 'utf8').replace(/VERSION = '[^']+'/, `VERSION = '${ver}'`));
  }
}

const waitCtrl = async (page) => {
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 30000 });
};
const bootApp = async (page) => {
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await waitCtrl(page);
  await page.waitForTimeout(800);
};
const fireVisible = async (page) => {
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
};
const promptCount = (page) => page.locator('#mn-swupd').count();
const diagHas = async (page, substr, tries = 20) => {
  for (let i = 0; i < tries; i++) {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
    });
    if (lines.some((l) => String(l).includes(substr))) return true;
    await page.waitForTimeout(400);
  }
  return false;
};

// ── 场景 A：首装无提示 → 换代出提示 → 点更新到新版 ──
stageGeneration(OLD_VER);
const dirA = fs.mkdtempSync(path.join(os.tmpdir(), 'swupd-profA-'));
const ctxA = await chromium.launchPersistentContext(dirA, { executablePath: exe, args: ['--no-sandbox'] });
const pageA = await ctxA.newPage();
pageA.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
await bootApp(pageA);
ok('A 首装全程无提示', (await promptCount(pageA)) === 0);
await fireVisible(pageA); // 无更新可查时回前台也不得误报
await pageA.waitForTimeout(1500);
ok('A 首装查更新后仍无提示', (await promptCount(pageA)) === 0);
const stagedA0 = await pageA.evaluate(() => localStorage.getItem('mynote_swupd_pending_v1'));
ok('A 首装未暂存任何事件', !stagedA0, String(stagedA0));

stageGeneration(newVer);
await fireVisible(pageA);
await pageA.waitForSelector('#mn-swupd', { timeout: 30000 });
ok('A 换代后提示出现', true);
const barText = await pageA.locator('#mn-swupd .mn-swupd-text').innerText();
const btnText = await pageA.locator('#mn-swupd .mn-swupd-btn').innerText();
ok('A 文案为 zh-CN 默认', barText === '新版本可用' && btnText === '点击更新', `${barText} / ${btnText}`);
const stagedA1 = await pageA.evaluate(() => JSON.parse(localStorage.getItem('mynote_swupd_pending_v1') || '[]'));
ok('A shown 事件已暂存（ver=新代）', stagedA1.some((e) => e.e === 'shown' && e.v === newVer), JSON.stringify(stagedA1));

// 点击重载以状态口径断言（不用 waitForNavigation：本
// harness 下导航事件口径曾被资源抖动饿死，而结果状态
// 可直读）——点击前埋标记，点击后等标记随旧文档消失
// 且新文档列表在场，即重载完成。
await pageA.evaluate(() => { window.__swupdMark = 1; });
const btnBox = await pageA.locator('#mn-swupd .mn-swupd-btn').boundingBox();
await pageA.mouse.click(btnBox.x + btnBox.width / 2, btnBox.y + btnBox.height / 2);
await pageA.waitForFunction(
  () => window.__swupdMark === undefined && document.querySelectorAll('.list-item').length > 0,
  null,
  { timeout: 30000 },
);
ok('A 点击后重载到新文档', true);
await waitCtrl(pageA);
const cacheKeys = await pageA.evaluate(() => caches.keys());
ok('A 重载后新代缓存接管', cacheKeys.includes('mynote-rustweb-' + newVer), cacheKeys.join(','));
ok('A Diag 补记 SWUPD shown', await diagHas(pageA, 'SWUPD prompt shown'));
ok('A Diag 补记 SWUPD clicked', await diagHas(pageA, 'SWUPD update clicked'));
ok('A 重载后提示不再出现', (await promptCount(pageA)) === 0);
await ctxA.close();

// ── 场景 B：关闭后同一版本不再重复弹 ────────────────
stageGeneration(OLD_VER);
const dirB = fs.mkdtempSync(path.join(os.tmpdir(), 'swupd-profB-'));
const ctxB = await chromium.launchPersistentContext(dirB, { executablePath: exe, args: ['--no-sandbox'] });
const pageB = await ctxB.newPage();
pageB.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
await bootApp(pageB);
stageGeneration(newVer);
await fireVisible(pageB);
await pageB.waitForSelector('#mn-swupd', { timeout: 30000 });
await pageB.locator('#mn-swupd .mn-swupd-close').click();
await pageB.waitForTimeout(300);
ok('B 关闭后提示消失', (await promptCount(pageB)) === 0);
const dismissed = await pageB.evaluate(() => localStorage.getItem('mynote_swupd_dismissed_v1'));
ok('B 关闭标记记新代版本', dismissed === newVer, String(dismissed));
await fireVisible(pageB); // 同版再查更新不得重弹
await pageB.waitForTimeout(2000);
ok('B 同版再查仍不重弹', (await promptCount(pageB)) === 0);
await ctxB.close();

server.close();
fs.rmSync(serveDir, { recursive: true, force: true });
fs.rmSync(dirA, { recursive: true, force: true });
fs.rmSync(dirB, { recursive: true, force: true });
L(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
