// 专用探针：点击域全量量测（批 12 P-U5，回归资产）。
// 逐页（列表/左滑开启/搜索/编辑器/编辑菜单/斜杠面板/设置/
// 备份/手势速览/语言/诊断）枚举全部可点元素命中盒，任一
// 维度 <40px 即不达标——「视觉不变、命中区外扩」补齐后
// 本探针全绿；例外须在 EXCEPTIONS 中逐项写明理由（命中
// 区由父级行整体承接的元素不重复计）。
// 用法：node probe_tap_targets.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

// 例外（逐项理由）：命中由祖先行/卡整体承接的元素，其自身
// 盒小但实际可点域 = 祖先盒（祖先另行量测达标）。
const EXCEPTIONS = [
  // 展开钮在行内，整行（.list-item ≥64px）可点展开/打开
  'button.expand-btn',
  // 标题输入是文本落字面：命中由标题胶囊容器承接
  // （.editor-title-capsule 实测 125x66，点按经落焦路由
  // 同步聚焦 input——胶囊为用户定案冻结规格、真机验证）
  'input.editor-title-input',
];

const MEASURE_JS = `(() => {
  const SEL = 'button, a, input, [role="button"], [role="checkbox"], [role="switch"], [role="tab"], [role="menuitem"], [tabindex="0"], .set-row, .about-row, .lang-row, .menu-item, .seg-btn, .bg-dot, .slash-item, .gesture-row';
  const out = [];
  const seen = new Set();
  const cand = new Set(document.querySelectorAll(SEL));
  // div 型可点元素（本应用大量以 div+onclick 实现）以
  // cursor:pointer 为兜底信号补入，但须排除「已在候选祖
  // 先内」的内部元素（行内文本 span 只是继承了行的
  // cursor、不是独立目标，实际命中由祖先行承接）；文本
  // 编辑面（contenteditable 块）是落字面不是点击域，不
  // 计（逐行高 ~28 属排版行高）。
  for (const el of document.querySelectorAll('div, span, li, label')) {
    if (el.isContentEditable) continue;
    if (getComputedStyle(el).cursor !== 'pointer') continue;
    let p = el.parentElement, nested = false;
    while (p) { if (cand.has(p)) { nested = true; break; } p = p.parentElement; }
    if (!nested) cand.add(el);
  }
  for (const el of cand) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || cs.pointerEvents === 'none') continue;
    // 命中区外扩（::after 承接）时以元素盒 + 伪元素盒并集计
    let w = r.width, h = r.height;
    const af = getComputedStyle(el, '::after');
    if (af && af.content !== 'none' && af.position === 'absolute') {
      const t = parseFloat(af.top) || 0, b = parseFloat(af.bottom) || 0;
      const l = parseFloat(af.left) || 0, rt = parseFloat(af.right) || 0;
      if (af.top !== 'auto' && af.bottom !== 'auto') h = Math.max(h, r.height - t - b);
      if (af.left !== 'auto' && af.right !== 'auto') w = Math.max(w, r.width - l - rt);
    }
    const desc = el.tagName.toLowerCase() + '.' + (typeof el.className === 'string' ? el.className.split(' ').join('.') : '') + '|' + (el.innerText || el.getAttribute('aria-label') || '').trim().slice(0, 14);
    if (seen.has(desc)) continue;
    seen.add(desc);
    out.push({ desc, w: Math.round(w), h: Math.round(h) });
  }
  return out;
})()`;

const results = new Map(); // page -> rows
async function sweep(page, name) {
  const rows = await page.evaluate(MEASURE_JS);
  results.set(name, rows);
  return rows;
}

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
const cdp = await ctx.newCDPSession(page);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);
await sweep(page, 'list');

// 左滑开启态（动作钮）
{
  const row = page.locator('.swipe-wrapper', { hasText: '好用的工具网站' }).first();
  const card = row.locator('.list-item').first();
  const box = await card.boundingBox();
  const cy = box.y + box.height / 2, sx = box.x + box.width - 40;
  await touch('touchStart', sx, cy);
  for (let dx = -20; dx >= -150; dx -= 15) { await touch('touchMove', sx + dx, cy); await page.waitForTimeout(25); }
  await touch('touchEnd', sx - 150, cy);
  await page.waitForTimeout(500);
  await sweep(page, 'list-swipe-open');
  // 点回关闭
  await card.click({ force: true }).catch(() => {});
  await page.waitForTimeout(300);
}

// 搜索开启态
await page.click('.glass-search-trigger');
await page.waitForSelector('.glass-search-input', { timeout: 8000 });
await page.waitForTimeout(400);
await sweep(page, 'search-open');
await page.keyboard.press('Escape');
await page.waitForTimeout(400);

// 编辑器（待办备忘：复选框）
await page.locator('.swipe-wrapper', { hasText: '装修踩坑清单' }).first().locator('.item-title-text').click();
await page.waitForSelector('.editor-stage', { timeout: 10000 });
await page.waitForTimeout(1000);
// 关掉首次提示（若在场，避免遮挡量测）
if (await page.locator('.gesture-hint button').count()) {
  await page.locator('.gesture-hint button').click();
  await page.waitForTimeout(300);
}
await sweep(page, 'editor');
// 编辑菜单
await page.locator('.editor-fab.right, .menu-trigger, [class*="menu-btn"]').first().click().catch(() => {});
await page.waitForTimeout(700);
await sweep(page, 'editor-menu');
// 背景底表（菜单内「背景」项）
await page.locator('.menu-item', { hasText: '背景' }).first().click().catch(() => {});
await page.waitForTimeout(800);
await sweep(page, 'bg-sheet');
await page.locator('.sheet-scrim').first().click({ force: true }).catch(() => {});
await page.waitForTimeout(500);
// 导出面板（重开菜单点「导出」）
await page.locator('.editor-fab.right').first().click().catch(() => {});
await page.waitForTimeout(700);
await page.locator('.menu-item', { hasText: '导出' }).first().click().catch(() => {});
await page.waitForTimeout(800);
await sweep(page, 'export-sheet');
await page.locator('.sheet-scrim').first().click({ force: true }).catch(() => {});
await page.waitForTimeout(500);
await page.keyboard.press('Escape').catch(() => {});
await page.waitForTimeout(400);
await page.click('.editor-fab.left');
await page.waitForTimeout(1000);

// 斜杠面板（使用指南篇尾空段输 /）+ 块长按菜单
await page.locator('.swipe-wrapper', { hasText: '使用指南' }).first().locator('.item-title-text').click();
await page.waitForSelector('.editor-stage', { timeout: 10000 });
await page.waitForTimeout(1000);
await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
await page.waitForTimeout(400);
await page.locator('.blk-p.ed-line').last().click();
await page.keyboard.type('/');
await page.waitForTimeout(900);
await sweep(page, 'slash-panel');
await page.keyboard.press('Escape');
await page.waitForTimeout(400);
{
  // 长按一块（todo 行）调块菜单
  const blk = page.locator('.todo-row').first();
  const box = await blk.boundingBox();
  if (box) {
    await touch('touchStart', box.x + 60, box.y + box.height / 2);
    await page.waitForTimeout(700);
    await touch('touchEnd', box.x + 60, box.y + box.height / 2);
    await page.waitForTimeout(800);
    await sweep(page, 'block-menu');
    await page.locator('.sheet-scrim, .menu-scrim').first().click({ force: true }).catch(() => {});
    await page.waitForTimeout(400);
  }
}
await page.click('.editor-fab.left');
await page.waitForTimeout(1000);

// 设置与子页
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.backup-card', { timeout: 10000 });
await page.waitForTimeout(600);
await sweep(page, 'settings');
await page.locator('.set-row', { hasText: '手势速览' }).first().click();
await page.waitForTimeout(900);
await sweep(page, 'gestures');
await page.click('.editor-fab.left');
await page.waitForTimeout(900);
await page.locator('.set-row', { hasText: '备份与恢复' }).first().click();
await page.waitForTimeout(900);
await sweep(page, 'backup');
await page.click('.editor-fab.left');
await page.waitForTimeout(900);
await page.locator('.set-row', { hasText: '语言' }).first().click();
await page.waitForTimeout(900);
await sweep(page, 'language');
await page.click('.editor-fab.left');
await page.waitForTimeout(900);
await page.locator('.set-row', { hasText: '诊断日志' }).first().click();
await page.waitForTimeout(900);
await sweep(page, 'diag');
await page.click('.editor-fab.left');
await page.waitForTimeout(900);

let total = 0;
for (const [name, rows] of results) {
  total += rows.length;
  const under = rows.filter((r) => (r.w < 40 || r.h < 40) && !EXCEPTIONS.some((e) => r.desc.startsWith(e)));
  L(`— ${name}: ${rows.length} 个可点元素，<40px ${under.length} 个`);
  if (process.env.VERBOSE) for (const r of rows) L(`    ${r.desc} ${r.w}x${r.h}`);
  for (const u of under) L(`  <40 ${u.desc} ${u.w}x${u.h}`);
  ok(`${name} 页无 <40px 点击域`, under.length === 0);
}
L(`共量测 ${total} 个可点元素（去重后逐页计）`);
await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
