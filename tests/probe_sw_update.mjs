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
// 场景 A 点更新全链；场景 B 关闭后同版不再弹；场景
// A/C 另守呈现收敛（2026-11-24 与应用 toast 统一）：
// 提示条与同页注入的 .backup-toast 探针元素 computed
// 逐项同值（浅色在 A、深色在 C）；场景 D 守外壳单态
// 按下态自带（2026-11-25 加严：应用永不挂载时 tap
// 高亮透明 + 圆角 999px，不靠应用全局规则兜底）。
// 场景 A 点击后的观察点在同 context 第二页（同 profile
// 核验终态），不在被重载页上等——定性与映射见 A 段注释。
// 场景 E（2026-11-25 用户指定我方自测补）：模拟用户
// 真实的一跳——旧代 = 现行 dist 原戳（其 index.html
// 已带 5e9b9db 按下态口径），新代 = 同源码仅 VERSION
// 戳递增；在旧代页面弹出的真实条上核按钮 computed
// 绝对值（tap 透明 / 圆角 999px）、真实按压保持时
// :active 底、关闭钮 :active 规则在位，再松开走完
// 点击更新全链（第二页核验递增戳接管 + SWUPD 行）。
// 定级边界：Chromium 只证 computed 口径与规则在位；
// iOS Safari 触摸高亮的实际绘制形状 Chromium 证不
// 了，属 inferred（依据 = computed 口径 + CSS 绘制
// 规则），box 绿不等于真机结论。
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
let distDir = path.join(root, '..', 'rust', 'apps', 'web', 'dist');
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
// 呈现比对：真实提示条 vs 同页注入的应用 toast 探针
// 元素（.backup-toast + 文本/动作钮子类），computed
// 逐项应同值（外壳同值复刻口径，见 index.html 注）。
const barVsToast = async (page) => page.evaluate(() => {
  const toast = document.createElement('div');
  toast.className = 'backup-toast';
  toast.innerHTML = '<span class="backup-toast-text">对齐</span><button class="undo-toast-btn">动作</button>';
  document.body.appendChild(toast);
  const pick = (el, props) => { const cs = getComputedStyle(el); const o = {}; for (const p of props) o[p] = cs[p]; return o; };
  const boxProps = ['backgroundColor', 'backdropFilter', 'borderTopColor', 'borderTopWidth', 'borderTopLeftRadius', 'boxShadow', 'paddingTop', 'paddingRight', 'bottom', 'animationDuration', 'animationTimingFunction'];
  const txtProps = ['fontSize', 'fontWeight', 'lineHeight', 'color'];
  const btnProps = ['fontSize', 'fontWeight', 'color', 'paddingTop', 'paddingLeft', 'webkitTapHighlightColor', 'borderTopLeftRadius'];
  const r = {
    bar: pick(document.querySelector('#mn-swupd'), boxProps),
    toast: pick(toast, boxProps),
    barText: pick(document.querySelector('#mn-swupd .mn-swupd-text'), txtProps),
    toastText: pick(toast.querySelector('.backup-toast-text'), txtProps),
    barBtn: pick(document.querySelector('#mn-swupd .mn-swupd-btn'), btnProps),
    toastBtn: pick(toast.querySelector('.undo-toast-btn'), btnProps),
  };
  toast.remove();
  return r;
});
const cmpOk = (tag, cmp) => {
  const diff = (a, b) => Object.keys(a).filter((k) => a[k] !== b[k]).map((k) => `${k}: ${a[k]} ≠ ${b[k]}`);
  const dBox = diff(cmp.bar, cmp.toast);
  const dTxt = diff(cmp.barText, cmp.toastText);
  const dBtn = diff(cmp.barBtn, cmp.toastBtn);
  ok(`${tag} 提示条盒与 toast computed 逐项同值`, dBox.length === 0, dBox.join('; ') || `bg=${cmp.bar.backgroundColor} bdf=${cmp.bar.backdropFilter} radius=${cmp.bar.borderTopLeftRadius} shadow=${cmp.bar.boxShadow} anim=${cmp.bar.animationDuration}/${cmp.bar.animationTimingFunction}`);
  ok(`${tag} 提示条文字与 toast 文字 computed 同值`, dTxt.length === 0, dTxt.join('; ') || `color=${cmp.barText.color} size=${cmp.barText.fontSize} weight=${cmp.barText.fontWeight} lh=${cmp.barText.lineHeight}`);
  ok(`${tag} 提示条动作钮与 toast 动作钮 computed 同值`, dBtn.length === 0, dBtn.join('; ') || `color=${cmp.barBtn.color} padding=${cmp.barBtn.paddingTop}/${cmp.barBtn.paddingLeft}`);
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
cmpOk('A', await barVsToast(pageA));

// 点击后改走同 context 第二页核验终态（观察法变更，
// 2026-11-24 关单）：原法在被重载页上 waitForFunction
// 等标记消失，两轮实测（57f59539a3 / 7cc10b87d8 两构
// 建）均卡死于此——重载实际发生、产品终态在同 profile
// 第二页完全可达，但被重载页在 box 无头 Chromium
// （headless shell 1255）下渲染进程无响应（evaluate /
// 截图 50s+ 无回、无 crash 事件），属 harness 面而非
// 产品面；真机侧该重载路径已实活。故点击仍在原页走
// 真实鼠标点（手势链不打折），其后一概不在原页观察。
// 旧断言 → 新观察点映射：
//   「点击后重载到新文档」+「重载后新代缓存接管」
//     → A2 直读 registration：新 SW activated、无
//       waiting、controller 在场；缓存含新代且不含旧
//       代（旧断言仅 includes 新代，新法略强）；
//   「Diag 补记 SWUPD shown / clicked」
//     → A2 读同 profile localStorage：暂存 drain 在任
//       一新启动发生、行落盘后与具体页面无关；
//   「重载后提示不再出现」
//     → A2 在新代下启动后不出现 #mn-swupd。
const btnBox = await pageA.locator('#mn-swupd .mn-swupd-btn').boundingBox();
await pageA.mouse.click(btnBox.x + btnBox.width / 2, btnBox.y + btnBox.height / 2);
const pageA2 = await ctxA.newPage();
pageA2.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
await bootApp(pageA2);
const swState = await pageA2.evaluate(async () => {
  const reg = await navigator.serviceWorker.getRegistration();
  return {
    controlled: !!navigator.serviceWorker.controller,
    activeState: reg && reg.active ? reg.active.state : null,
    waiting: !!(reg && reg.waiting),
    caches: await caches.keys(),
  };
});
ok('A2 新 SW activated 并接管', swState.controlled && swState.activeState === 'activated' && !swState.waiting, JSON.stringify(swState));
ok('A2 缓存为新代接管（不含旧代）', swState.caches.includes('mynote-rustweb-' + newVer) && !swState.caches.includes('mynote-rustweb-' + OLD_VER), swState.caches.join(','));
ok('A2 应用在新 SW 下启动到列表', (await pageA2.locator('.list-item').count()) > 0);
ok('A2 Diag 补记 SWUPD shown', await diagHas(pageA2, 'SWUPD prompt shown'));
ok('A2 Diag 补记 SWUPD clicked', await diagHas(pageA2, 'SWUPD update clicked'));
await pageA2.waitForTimeout(1500);
ok('A2 新代下提示不再出现', (await promptCount(pageA2)) === 0);
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

// ── 场景 C：深色下提示条呈现与 toast 同值 ────────────
stageGeneration(OLD_VER);
const dirC = fs.mkdtempSync(path.join(os.tmpdir(), 'swupd-profC-'));
const ctxC = await chromium.launchPersistentContext(dirC, { executablePath: exe, args: ['--no-sandbox'], colorScheme: 'dark' });
const pageC = await ctxC.newPage();
pageC.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
await bootApp(pageC);
stageGeneration(newVer);
await fireVisible(pageC);
await pageC.waitForSelector('#mn-swupd', { timeout: 30000 });
ok('C 深色换代后提示出现', true);
cmpOk('C', await barVsToast(pageC));
await ctxC.close();

// ── 场景 D：仅外壳层（应用永不挂载）按下态自带 ──────
// 外壳独立性底线（2026-11-25 真机报「点击更新」按下
// 呈方形后加严）：拦截应用 JS/wasm、应用 CSS 永不注
// 入时，外壳钮的 tap 高亮仍须透明、圆角仍须胶囊形——
// 不得靠应用 base.css 全局 * 规则兜底（修复前本场景
// 量得 UA 默认 rgba(0,0,0,0.18) + 圆角 0px）。
{
  const brD = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
  const pageD = await brD.newPage();
  await pageD.route('**/mynote-web.js', (r) => r.abort());
  await pageD.route('**/*.wasm', (r) => r.abort());
  await pageD.goto(BASE, { waitUntil: 'load' });
  await pageD.waitForTimeout(1200);
  ok('D 应用未挂载（启动屏残留）', await pageD.evaluate(() => !!document.querySelector('#main .splash')));
  await pageD.evaluate(() => {
    const bar = document.createElement('div');
    bar.id = 'mn-swupd';
    bar.innerHTML = '<span class="mn-swupd-text">新版本可用</span><button class="mn-swupd-btn">点击更新</button><button class="mn-swupd-close">×</button>';
    document.body.appendChild(bar);
  });
  const dPress = await pageD.evaluate(() => {
    const pick = (sel) => { const cs = getComputedStyle(document.querySelector(sel)); return { tap: cs.webkitTapHighlightColor, radius: cs.borderTopLeftRadius }; };
    return { btn: pick('#mn-swupd .mn-swupd-btn'), close: pick('#mn-swupd .mn-swupd-close') };
  });
  ok('D 外壳单态动作钮 tap 透明', dPress.btn.tap === 'rgba(0, 0, 0, 0)', dPress.btn.tap);
  ok('D 外壳单态动作钮圆角 999px', dPress.btn.radius === '999px', dPress.btn.radius);
  ok('D 外壳单态关闭钮 tap 透明', dPress.close.tap === 'rgba(0, 0, 0, 0)', dPress.close.tap);
  ok('D 外壳单态关闭钮圆角 999px', dPress.close.radius === '999px', dPress.close.radius);
  await brD.close();
}

// ── 场景 E：已修口径双版跳全链 + 真实条按下态 ──────
// 旧代 = 现行 dist 原戳（= 生产 518f101dcf 同源、条的
// HTML/CSS 即已修口径）；新代 = 同源码仅戳递增
// （NEWER_VER = 本代戳 + 'e'，造版手法同 A/B/C、
// 不动任何业务码）。按下态在真实条上量：动作钮走
// 真实鼠标按压保持读 :active computed，关闭钮只查
// :active 规则在位（实压松开会把条关掉、断链）。
const NEWER_VER = newVer + 'e';
stageGeneration(newVer);
const dirE = fs.mkdtempSync(path.join(os.tmpdir(), 'swupd-profE-'));
const ctxE = await chromium.launchPersistentContext(dirE, { executablePath: exe, args: ['--no-sandbox'] });
const pageE = await ctxE.newPage();
pageE.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
await bootApp(pageE);
ok('E 旧代（现行戳）首装无提示', (await promptCount(pageE)) === 0);
stageGeneration(NEWER_VER);
await fireVisible(pageE);
await pageE.waitForSelector('#mn-swupd', { timeout: 30000 });
ok('E 递增戳换代后提示出现', true);
await pageE.waitForTimeout(600); // 等进场动画落定再量测/按压（量测只认落定值）
cmpOk('E', await barVsToast(pageE));
const eVals = await pageE.evaluate(() => {
  const pick = (sel) => { const cs = getComputedStyle(document.querySelector(sel)); return { tap: cs.webkitTapHighlightColor, radius: cs.borderTopLeftRadius }; };
  let closeActiveBg = null;
  for (const sheet of document.styleSheets) {
    let rules; try { rules = sheet.cssRules; } catch (err) { continue; }
    for (const r of rules) {
      if (r.selectorText === '#mn-swupd .mn-swupd-close:active') closeActiveBg = r.style.backgroundColor;
    }
  }
  return { btn: pick('#mn-swupd .mn-swupd-btn'), close: pick('#mn-swupd .mn-swupd-close'), closeActiveBg };
});
ok('E 真实条动作钮 tap 透明', eVals.btn.tap === 'rgba(0, 0, 0, 0)', eVals.btn.tap);
ok('E 真实条动作钮圆角 999px', eVals.btn.radius === '999px', eVals.btn.radius);
ok('E 真实条关闭钮 tap 透明', eVals.close.tap === 'rgba(0, 0, 0, 0)', eVals.close.tap);
ok('E 真实条关闭钮圆角 999px', eVals.close.radius === '999px', eVals.close.radius);
ok('E 关闭钮 :active 底规则在位', eVals.closeActiveBg === 'rgba(127, 127, 127, 0.1)', String(eVals.closeActiveBg));
const eBtnBox = await pageE.locator('#mn-swupd .mn-swupd-btn').boundingBox();
await pageE.mouse.move(eBtnBox.x + eBtnBox.width / 2, eBtnBox.y + eBtnBox.height / 2);
await pageE.mouse.down();
await pageE.waitForTimeout(200);
const eActiveBg = await pageE.evaluate(() => getComputedStyle(document.querySelector('#mn-swupd .mn-swupd-btn')).backgroundColor);
ok('E 按压保持时动作钮 :active 底', eActiveBg === 'rgba(0, 122, 255, 0.1)', eActiveBg);
await pageE.screenshot({ path: path.join(os.tmpdir(), 'swupd-e-pressed.png') });
await pageE.mouse.up(); // 松开 = 点击更新；终态观察同 A 走第二页（被重载页在 box 无头下无响应、非产品面）
const pageE2 = await ctxE.newPage();
pageE2.on('pageerror', (e) => L('PAGE_ERROR', String(e).slice(0, 200)));
await bootApp(pageE2);
const swStateE = await pageE2.evaluate(async () => {
  const reg = await navigator.serviceWorker.getRegistration();
  return {
    controlled: !!navigator.serviceWorker.controller,
    activeState: reg && reg.active ? reg.active.state : null,
    waiting: !!(reg && reg.waiting),
    caches: await caches.keys(),
  };
});
ok('E2 新 SW activated 并接管', swStateE.controlled && swStateE.activeState === 'activated' && !swStateE.waiting, JSON.stringify(swStateE));
ok('E2 缓存为递增戳新代接管（不含旧代）', swStateE.caches.includes('mynote-rustweb-' + NEWER_VER) && !swStateE.caches.includes('mynote-rustweb-' + newVer), swStateE.caches.join(','));
ok('E2 Diag 补记 SWUPD shown', await diagHas(pageE2, 'SWUPD prompt shown'));
ok('E2 Diag 补记 SWUPD clicked', await diagHas(pageE2, 'SWUPD update clicked'));
await pageE2.waitForTimeout(1500);
ok('E2 新代下提示不再出现', (await promptCount(pageE2)) === 0);
await ctxE.close();

server.close();
fs.rmSync(serveDir, { recursive: true, force: true });
fs.rmSync(dirA, { recursive: true, force: true });
fs.rmSync(dirB, { recursive: true, force: true });
fs.rmSync(dirC, { recursive: true, force: true });
fs.rmSync(dirE, { recursive: true, force: true });
L(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
