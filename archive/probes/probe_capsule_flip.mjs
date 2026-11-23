// 紧凑标题胶囊 + 搜索面板：翻转重挂与 computed 复核（Rust 新构建）
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8118/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'light' });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 25000 });
await page.waitForTimeout(800);

// 滚动出紧凑标题胶囊
await page.evaluate(() => window.scrollTo(0, 300));
await page.waitForTimeout(600);
const before = await page.evaluate(() => {
  const c = document.querySelector('.page-title.compact');
  window.__compact = c;
  const cs = getComputedStyle(c);
  return { vis: cs.visibility, op: cs.opacity, bg: cs.backgroundColor, bf: cs.backdropFilter, radius: cs.borderRadius };
});
console.log('compact before flip:', JSON.stringify(before));
// 打开搜索面板
await page.evaluate(() => window.scrollTo(0, 0));
await page.waitForTimeout(400);
await page.click('.glass-search-trigger');
await page.waitForSelector('.glass-search-panel', { timeout: 5000 });
await page.waitForTimeout(400);
const panelBefore = await page.evaluate(() => {
  const p = document.querySelector('.glass-search-panel');
  window.__panel = p;
  const cs = getComputedStyle(p);
  return { bg: cs.backgroundColor, bf: cs.backdropFilter, radius: cs.borderRadius, border: cs.borderTopWidth + ' ' + cs.borderTopColor };
});
console.log('panel before flip:', JSON.stringify(panelBefore));

await page.emulateMedia({ colorScheme: 'dark' });
await page.waitForTimeout(700);
const after = await page.evaluate(() => {
  const c = document.querySelector('.page-title.compact');
  const p = document.querySelector('.glass-search-panel');
  const cs = c ? getComputedStyle(c) : null;
  const ps = p ? getComputedStyle(p) : null;
  return {
    compactRemounted: c !== window.__compact,
    compactBg: cs && cs.backgroundColor, compactBf: cs && cs.backdropFilter, compactRadius: cs && cs.borderRadius,
    panelRemounted: p !== window.__panel,
    panelBg: ps && ps.backgroundColor, panelBf: ps && ps.backdropFilter, panelRadius: ps && ps.borderRadius,
    panelBorder: ps && (ps.borderTopWidth + ' ' + ps.borderTopColor),
    inputValueKept: document.querySelector('.glass-search-input') ? 'present' : 'absent',
  };
});
console.log('after flip:', JSON.stringify(after, null, 1));
await browser.close();
