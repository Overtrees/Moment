// 浮层出场动效断言探针（Chromium 口径）：编辑菜单 / 背景色底表 /
// 图文全文面板三处出场必须真实播放（采样中间态）、关闭后无残留
// DOM、关闭计时重排（代际语义）不误关；背景色选色回调按原版
// closeWithAnim 口径在卸载时点才生效（延迟生效断言）。
// 用法：node probe_exit_anim.mjs [base]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8096/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (cond, name, extra = '') => {
  console.log((cond ? '✓ ' : '✗ ') + name + (extra ? ' | ' + extra : ''));
  if (!cond) fails++;
};

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

async function importZip(zip) {
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 }).catch(() => {});
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  await page.waitForTimeout(400);
}
async function openMemo(title) {
  const titlePt = (t) => page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt
        && !e.querySelector('.expand-btn'));
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, t);
  let pt = null;
  for (let attempt = 0; attempt < 4 && !pt; attempt++) {
    pt = await titlePt(title);
    if (pt) break;
    const ex = await page.evaluate(() => {
      const b = document.querySelector('.expand-btn');
      if (!b) return null;
      b.scrollIntoView({ block: 'center' });
      const r = b.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (ex) { await page.mouse.click(ex.x, ex.y); await page.waitForTimeout(700); }
    else await page.waitForTimeout(500);
  }
  if (!pt) throw new Error('card not found: ' + title);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(800);
}
const sample = (sel) => page.evaluate((s) => {
  const el = document.querySelector(s);
  if (!el) return null;
  const cs = getComputedStyle(el);
  return { opacity: parseFloat(cs.opacity), transform: cs.transform, closing: el.className.includes('is-closing') };
}, sel);
const midAnim = (samples) => samples.some((s) => s && (s.opacity > 0.03 && s.opacity < 0.97 || /matrix/.test(s.transform) && !/matrix\(1, 0, 0, 1, 0, 0\)/.test(s.transform)));

// ---------- 0. 种子备忘 ----------
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('.detail .ed-line', { timeout: 8000 });
await page.waitForTimeout(400);

// ---------- 1. 菜单出场：中间态 + 无残留 ----------
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(350); // 进场播完
await page.click('.menu-scrim');
const mSamples = [];
for (const w of [60, 70]) { await page.waitForTimeout(w); mSamples.push(await sample('.editor-menu-panel')); }
ok(mSamples[0] && mSamples[0].closing, 'menu: close sets is-closing', JSON.stringify(mSamples[0]));
ok(midAnim(mSamples), 'menu: exit animation actually plays (intermediate state)', JSON.stringify(mSamples));
await page.waitForSelector('.editor-menu-panel', { state: 'detached', timeout: 3000 });
ok((await page.$('.menu-scrim')) === null && (await page.$('.editor-menu-panel')) === null, 'menu: no residual DOM after close');

// ---------- 2. 菜单关闭重排：连点两次遮罩，第二下重排计时 ----------
// 第二下用 dispatchEvent 直派（Playwright 点击管线在高负载
// 下派发延迟可达数百 ms，会与 220ms 计时竞速失真）；完成
// 判据另加 Diag 计数：两次关闭只应落一条 'menu closed'
// （被重排作废的计时回调不写日志）。
const diagCount = (needle) => page.evaluate((n) => JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').filter((e) => JSON.stringify(e).includes(n)).length, needle);
const closedBefore = await diagCount('menu closed');
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(350);
await page.click('.menu-scrim');           // 第一次关闭（计时 A）
await page.waitForTimeout(120);
await page.evaluate(() => document.querySelector('.menu-scrim')?.dispatchEvent(new MouseEvent('click', { bubbles: true }))); // 第二次关闭（重排计时 B，A 应作废）
await page.waitForTimeout(120);            // 距 A 的 220ms 期限已过：若 A 未作废面板已卸载
ok((await page.$('.editor-menu-panel')) !== null, 'menu: re-armed close timer supersedes the first (panel still mounted past A deadline)');
await page.waitForSelector('.editor-menu-panel', { state: 'detached', timeout: 3000 });
ok(true, 'menu: re-armed close completes and unmounts');
await page.waitForTimeout(300);
ok((await diagCount('menu closed')) === closedBefore + 1, 'menu: exactly one close completion logged for two close taps');
// 重开后不得被任何旧计时误关
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(600);
const reopened = await sample('.editor-menu-panel');
ok(reopened && !reopened.closing && reopened.opacity === 1, 'menu: reopened menu stays open (no stale timer kill)', JSON.stringify(reopened));
await page.click('.menu-scrim');
await page.waitForSelector('.editor-menu-panel', { state: 'detached', timeout: 3000 });

// ---------- 3. 背景色底表：菜单延迟开表 + 出场中间态 + 选色延迟生效 ----------
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(350);
const t0 = Date.now();
await page.locator('.editor-menu-panel .menu-item:has-text("更换背景色")').click();
await page.waitForSelector('.bg-sheet', { timeout: 8000 });
const sheetDelay = Date.now() - t0;
ok(sheetDelay >= 150, 'bg: sheet opens after menu exit (~220ms, original sequencing)', sheetDelay + 'ms');
// 选色延迟生效：点色点后 +90ms 根背景不应已变（回调在卸载时点），+600ms 应已变
const rootBg = () => page.$eval('#editor-root', (e) => e.style.background);
const before = await rootBg();
const dotColor = await page.evaluate((cur) => {
  const dots = [...document.querySelectorAll('.bg-dot')];
  const pick = dots.find((d) => !cur.includes(d.style.background) && d.style.background) || dots[2] || dots[0];
  return pick ? pick.style.background : null;
}, before);
await page.evaluate((bg) => {
  const d = [...document.querySelectorAll('.bg-dot')].find((x) => x.style.background === bg);
  if (d) d.click();
}, dotColor);
await page.waitForTimeout(90);
const at90 = await rootBg();
ok(at90 === before, 'bg: color NOT applied yet at +90ms (afterClose timing)', `before=${before} at90=${at90}`);
const bSamples = [];
for (const w of [40, 60]) { await page.waitForTimeout(w); bSamples.push(await sample('.sheet-wrap')); }
ok(bSamples.some((s) => s && s.closing), 'bg: close sets is-closing on .sheet-wrap', JSON.stringify(bSamples));
ok(midAnim(bSamples), 'bg: exit animation actually plays (intermediate state)', JSON.stringify(bSamples));
await page.waitForSelector('.sheet-wrap', { state: 'detached', timeout: 3000 });
ok((await page.$('.sheet-scrim')) === null, 'bg: no residual scrim after close');
await page.waitForTimeout(400);
const after = await rootBg();
ok(after !== before && after.length > 0, 'bg: color applied after sheet closed', `after=${after}`);
// 清理：移除背景色（同样走出场路径）
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(350);
await page.locator('.editor-menu-panel .menu-item:has-text("更换背景色")').click();
await page.waitForSelector('.bg-sheet', { timeout: 8000 });
if (await page.$('.bg-remove')) {
  await page.click('.bg-remove');
  await page.waitForSelector('.sheet-wrap', { state: 'detached', timeout: 3000 });
  await page.waitForTimeout(300);
}

// ---------- 4. 图文面板出场 ----------
await page.click('#editor-root .editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
await importZip(process.env.HOME + '/workspace/Mynote/fixtures/allblocks.zip');
await openMemo('全块渲染测试');
const itc = await page.$('.itc-text, .itr-text');
ok(!!itc, 'sheet: img-text card present in fixture memo');
if (itc) {
  await itc.click();
  await page.waitForSelector('.image-text-sheet', { timeout: 8000 });
  await page.waitForTimeout(300);
  await page.click('.image-text-sheet-backdrop');
  const sSamples = [];
  for (const w of [60, 70]) { await page.waitForTimeout(w); sSamples.push(await sample('.image-text-sheet-wrap')); }
  ok(sSamples[0] && sSamples[0].closing, 'sheet: backdrop click sets is-closing on wrap', JSON.stringify(sSamples[0]));
  ok(midAnim(sSamples), 'sheet: exit animation actually plays (intermediate state)', JSON.stringify(sSamples));
  await page.waitForSelector('.image-text-sheet-wrap', { state: 'detached', timeout: 3000 });
  ok((await page.$('.image-text-sheet-backdrop')) === null, 'sheet: no residual backdrop after close');
}

// ---------- 5. 图文面板 Esc 出场（原版 ImageTextSheet 自带 Esc 口径） ----------
if (itc) {
  await itc.click();
  await page.waitForSelector('.image-text-sheet', { timeout: 8000 });
  await page.waitForTimeout(300);
  await page.keyboard.press('Escape');
  const eSamples = [];
  for (const w of [60, 70]) { await page.waitForTimeout(w); eSamples.push(await sample('.image-text-sheet-wrap')); }
  ok(eSamples[0] && eSamples[0].closing, 'sheet: Esc sets is-closing on wrap', JSON.stringify(eSamples[0]));
  ok(midAnim(eSamples), 'sheet: Esc exit animation actually plays', JSON.stringify(eSamples));
  await page.waitForSelector('.image-text-sheet-wrap', { state: 'detached', timeout: 3000 });
  ok((await page.$('.image-text-sheet-backdrop')) === null, 'sheet: no residual backdrop after Esc close');
}

// ---------- 6. 灯箱视觉视口定尺（100lvh 口径） ----------
const imgEl = await page.$('.atomic[data-type="image"] img, .editor-body img');
ok(!!imgEl, 'lightbox: image present in fixture memo');
if (imgEl) {
  await imgEl.click();
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  await page.waitForTimeout(200);
  const lb = await page.evaluate(() => {
    const el = document.querySelector('.lightbox');
    const r = el.getBoundingClientRect();
    let ruleHasLvh = false;
    for (const sh of document.styleSheets) {
      let rules;
      try { rules = sh.cssRules; } catch { continue; }
      for (const rule of rules) {
        if (rule.selectorText === '.lightbox' && rule.cssText.includes('100lvh')) ruleHasLvh = true;
      }
    }
    return { top: r.top, height: r.height, bottom: r.bottom, inner: window.innerHeight, ruleHasLvh };
  });
  ok(lb.ruleHasLvh, 'lightbox: CSS rule uses 100lvh sizing', JSON.stringify(lb));
  ok(lb.top === 0 && lb.height === lb.inner && lb.bottom === lb.inner, 'lightbox: covers full visual viewport height', JSON.stringify(lb));
  await page.click('.lightbox');
  await page.waitForSelector('.lightbox', { state: 'detached', timeout: 3000 });
  ok(true, 'lightbox: click closes');
}

// ---------- 7. 导出链时序回归：菜单出场 220ms 后才挂导出面板 ----------
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(350);
await page.locator('.editor-menu-panel .menu-item:has-text("导出")').click();
await page.waitForTimeout(80);
ok((await page.$('.editor-export-panel')) === null, 'export chain: panel not mounted during menu exit (220ms sequencing)');
const chainMenu = await sample('.editor-menu-panel');
ok(chainMenu && chainMenu.closing, 'export chain: menu is closing after export tap', JSON.stringify(chainMenu));
await page.waitForSelector('.editor-export-panel', { timeout: 5000 });
await page.waitForTimeout(400);
ok((await page.$('.editor-menu-panel')) !== null || (await page.$('.editor-export-panel')) !== null, 'export chain: export panel mounted after menu exit');
await page.click('.export-back');
await page.waitForTimeout(400);
ok((await page.$('.editor-export-panel')) === null && (await page.$('.editor-menu-panel')) !== null, 'export chain: back returns to menu panel');
await page.click('.menu-scrim');
await page.waitForSelector('.editor-menu-panel', { state: 'detached', timeout: 3000 });
ok((await page.$('.menu-scrim')) === null, 'export chain: scrim click fully closes');

ok(errors.length === 0, 'no pageerror', errors.join(' | '));
console.log(fails === 0 ? 'EXIT ANIM ALL PASS' : `EXIT ANIM FAILURES: ${fails}`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
