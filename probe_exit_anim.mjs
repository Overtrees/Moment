// 浮层出场动效断言探针（Chromium 口径）：编辑菜单 / 背景色底表 /
// 图文全文面板三处出场必须真实播放（采样中间态）、关闭后无残留
// DOM、关闭计时重排（代际语义）不误关；背景色选色回调按原版
// closeWithAnim 口径在卸载时点才生效（延迟生效断言）。
// 原 §6 灯箱段已于 2026-11-24 摘除：浮层灯箱退役、改独立图片页，
// 其覆盖归 probe_lightbox_page；原 §7 导出链顺延为 §6。
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
  await page.waitForSelector('#file-import', { state: 'detached', timeout: 8000 }).catch(() => {});
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item:not(.set-row), .img-card', { timeout: 10000 });
  await page.waitForTimeout(400);
}
async function openMemo(title) {
  // 开备忘按 probe_pages_editor_rust 已验证的坐标点按法（ba67c27 同法）：
  // 等卡在场 → scrollIntoView → 待进场/展开动画落定 → 重量坐标 →
  // touchscreen.tap（现行列表走真实指针手势链）。折叠日期组内的卡
  // 需先点 .expand-btn 展开，原有口径保留。
  const findCard = (t) => page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt
        && !e.querySelector('.expand-btn'));
    if (!card) return false;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    return true;
  }, t);
  let found = false;
  for (let attempt = 0; attempt < 4 && !found; attempt++) {
    found = await findCard(title);
    if (found) break;
    const ex = await page.evaluate(() => {
      const b = document.querySelector('.expand-btn');
      if (!b) return null;
      b.scrollIntoView({ block: 'center' });
      const r = b.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (ex) { await page.touchscreen.tap(ex.x, ex.y); await page.waitForTimeout(700); }
    else await page.waitForTimeout(500);
  }
  if (!found) throw new Error('card not found: ' + title);
  await page.waitForTimeout(450); // 动画落定后再量坐标，避免量到中间位
  const pt = await page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt);
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, title);
  if (!pt) throw new Error('card not measurable: ' + title);
  await page.touchscreen.tap(pt.x, pt.y);
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
// Diag 落盘有批 10 的 1s 节流：计数读数改轮询等落盘
// （waitDiagCount），「只落一条」判据本身不放宽。基线同理：
// §1 那条 'menu closed' 可能还在节流缓冲里未落盘，基线必须
// 等计数静默（>1 个节流窗不再增长）后才取，否则基线少计、
// 两条合并落盘会被误读成「落了两条」。
const diagCount = (needle) => page.evaluate((n) => JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').filter((e) => JSON.stringify(e).includes(n)).length, needle);
const stableDiagCount = async (needle, quietMs = 1200) => {
  let prev = await diagCount(needle);
  let quietFor = 0;
  while (quietFor < quietMs) {
    await page.waitForTimeout(250);
    const c = await diagCount(needle);
    if (c === prev) quietFor += 250; else { prev = c; quietFor = 0; }
  }
  return prev;
};
const waitDiagCount = async (needle, target, timeout = 6000) => {
  const t0 = Date.now();
  let c = await diagCount(needle);
  while (c < target && Date.now() - t0 < timeout) {
    await page.waitForTimeout(250);
    c = await diagCount(needle);
  }
  return c;
};
const closedBefore = await stableDiagCount('menu closed');
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
await waitDiagCount('menu closed', closedBefore + 1);
await page.waitForTimeout(1500); // 再过一个节流窗：若误落第二条，此时应已落盘
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
// 开表管线按现行卡片交互口径（卡片交互专项，probe_card_menu ③
// 同法）：非编辑态点文本区被桥拦下只选中、不开表；须先长按开
// 卡片菜单、点「编辑」入编辑态，再点文本区才放行开表。卡已在
// 编辑态时跳过菜单步（编辑态长按是文本选择、不会开菜单）。
// 本段断言（出场中间态 + 无残留）口径不变，只修开表管线。
await page.click('#editor-root .editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
await importZip(process.env.HOME + '/workspace/Mynote/fixtures/allblocks.zip');
await openMemo('全块渲染测试');
const itc = await page.$('.itc-text, .itr-text');
ok(!!itc, 'sheet: img-text card present in fixture memo');
const cdp = await ctx.newCDPSession(page);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});
const itcZone = () => page.evaluate(() => {
  const el = document.querySelector('.itc-text, .itr-text');
  if (!el) return null;
  const wrap = el.closest('.blk-wrap');
  if (wrap) wrap.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  const wr = wrap ? wrap.getBoundingClientRect() : r;
  return {
    tx: r.x + r.width / 2, ty: r.y + r.height / 2,
    cx: wr.x + wr.width / 2, cy: wr.y + wr.height / 2,
    editing: !!wrap && wrap.classList.contains('card-editing'),
  };
});
async function openImgTextSheet() {
  let z = await itcZone();
  if (!z) return false;
  await page.waitForTimeout(500); // 滚动/进场落定后重量坐标
  z = await itcZone();
  if (!z.editing) {
    await touch('touchStart', z.cx, z.cy);
    await page.waitForTimeout(750); // 长按拾起 → 卡片菜单
    const editPt = await page.evaluate(() => {
      const b = [...document.querySelectorAll('.card-menu-panel .menu-item')].find((x) => !x.classList.contains('danger'));
      if (!b) return null;
      const r = b.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    await touch('touchEnd');
    if (!editPt) return false;
    await page.waitForTimeout(650); // 合成 click 抑制窗（桥既有口径）
    await page.touchscreen.tap(editPt.x, editPt.y);
    await page.waitForTimeout(500);
    z = await itcZone();
    if (!z || !z.editing) return false;
  }
  await page.touchscreen.tap(z.tx, z.ty);
  await page.waitForSelector('.image-text-sheet', { timeout: 8000 }).catch(() => {});
  return (await page.$('.image-text-sheet')) !== null;
}
if (itc) {
  ok(await openImgTextSheet(), 'sheet: opens through card-editing gate (long-press menu -> edit -> text tap)');
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
  await openImgTextSheet();
  await page.waitForTimeout(300);
  await page.keyboard.press('Escape');
  const eSamples = [];
  for (const w of [60, 70]) { await page.waitForTimeout(w); eSamples.push(await sample('.image-text-sheet-wrap')); }
  ok(eSamples[0] && eSamples[0].closing, 'sheet: Esc sets is-closing on wrap', JSON.stringify(eSamples[0]));
  ok(midAnim(eSamples), 'sheet: Esc exit animation actually plays', JSON.stringify(eSamples));
  await page.waitForSelector('.image-text-sheet-wrap', { state: 'detached', timeout: 3000 });
  ok((await page.$('.image-text-sheet-backdrop')) === null, 'sheet: no residual backdrop after Esc close');
}

// ---------- 6. 导出链时序回归：菜单出场 220ms 后才挂导出面板 ----------
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
