// 专用探针：无障碍余项（批 12 P-U7）。
//  ① 全页扫无名交互元素：button/[role=button]/[role=
//     checkbox]/[tabindex=0]/a/input 中可见且无可达名
//     （aria-label/aria-labelledby/文本/value/placeholder
//     全空）者判红；
//  ② 玻璃控件统一焦点环：键盘模态下程序聚焦 .seg-btn /
//     .editor-fab / .backup-btn，断言 :focus-visible 命中
//     且 outline-width 为 3px。
// 用法：node probe_a11y.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const NAME_JS = `(() => {
  const SEL = 'button, [role="button"], [role="checkbox"], [role="switch"], [tabindex="0"], a[href], input';
  const bad = [];
  for (const el of document.querySelectorAll(SEL)) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    const name = (el.getAttribute('aria-label') || el.getAttribute('aria-labelledby') || (el.innerText || '').trim() || el.value || el.placeholder || el.title || '').trim();
    if (!name) bad.push(el.tagName.toLowerCase() + '.' + (typeof el.className === 'string' ? el.className.split(' ').join('.') : ''));
  }
  return bad;
})()`;

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);

async function sweepNames(name) {
  const bad = await page.evaluate(NAME_JS);
  ok(`${name} 无名交互元素为零`, bad.length === 0, bad.join(' ; '));
}
await sweepNames('list');

// 编辑器（音乐篇：卡片类按钮）
await page.locator('.swipe-wrapper', { hasText: '最近在听的歌' }).first().locator('.item-title-text').click();
await page.waitForSelector('.editor-stage', { timeout: 10000 });
await page.waitForTimeout(1200);
if (await page.locator('.gesture-hint button').count()) await page.locator('.gesture-hint button').click();
await sweepNames('editor-music');
// 编辑菜单
await page.locator('.editor-fab.right').click();
await page.waitForTimeout(700);
await sweepNames('editor-menu');
await page.keyboard.press('Escape');
await page.waitForTimeout(400);
await page.click('.editor-fab.left');
await page.waitForTimeout(1000);

// 设置 + 焦点环
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.backup-card', { timeout: 10000 });
await page.waitForTimeout(600);
await sweepNames('settings');
await page.keyboard.press('Tab'); // 进入键盘模态
const ring = await page.evaluate(() => {
  const out = {};
  for (const [k, sel] of Object.entries({ seg: '.seg-btn', fab: '.editor-fab.left', row: '.set-row' })) {
    const el = document.querySelector(sel);
    if (!el) { out[k] = 'missing'; continue; }
    el.focus();
    const cs = getComputedStyle(el);
    out[k] = `${el.matches(':focus-visible')}/${cs.outlineWidth}/${cs.outlineStyle}`;
  }
  return out;
});
ok('seg-btn 焦点环', ring.seg === 'true/3px/solid', ring.seg);
ok('editor-fab 焦点环（设置页返回钮）', ring.fab === 'true/3px/solid', ring.fab);

// 备份页 + 确认弹窗
await page.locator('.set-row', { hasText: '备份与恢复' }).first().click();
await page.waitForTimeout(900);
await sweepNames('backup');
// 导出确认弹窗内测 .backup-btn 焦点环（该类只在弹窗里）
await page.locator('.backup-row').first().click();
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.waitForTimeout(500);
await sweepNames('backup-modal');
await page.keyboard.press('Tab'); // 建键盘模态（同 settings 段口径）
const ring2 = await page.evaluate(() => {
  const el = document.querySelector('.backup-modal .backup-btn.primary');
  if (!el) return 'missing';
  el.focus();
  const cs = getComputedStyle(el);
  return `${el.matches(':focus-visible')}/${cs.outlineWidth}/${cs.outlineStyle}`;
});
ok('backup-btn 焦点环', ring2 === 'true/3px/solid', ring2);
await page.locator('.backup-modal .backup-btn.secondary').click();
await page.waitForTimeout(500);
await page.click('.editor-fab.left');
await page.waitForTimeout(900);

// 语言/手势/诊断页
await page.locator('.set-row', { hasText: '语言' }).first().click();
await page.waitForTimeout(900);
await sweepNames('language');
await page.click('.editor-fab.left');
await page.waitForTimeout(900);
await page.locator('.set-row', { hasText: '手势速览' }).first().click();
await page.waitForTimeout(900);
await sweepNames('gestures');
await page.click('.editor-fab.left');
await page.waitForTimeout(900);
await page.locator('.set-row', { hasText: '诊断日志' }).first().click();
await page.waitForTimeout(900);
await sweepNames('diag');

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
