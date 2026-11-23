// 触发胶囊单独验证：面板不打开，直接量测+标记 .glass-search-trigger
// 后翻转方案，验数值与节点重挂载（marked 丢失 = 新节点）。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = process.argv[2] || 'http://localhost:8213/';

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForTimeout(2500);
await page.emulateMedia({ colorScheme: 'light' });
await page.waitForTimeout(400);
const read = () => page.evaluate(`(() => {
  const el = document.querySelector('.glass-search-trigger');
  if (!el) return null;
  const cs = getComputedStyle(el);
  return { bg: cs.backgroundColor, bf: cs.backdropFilter, br: cs.borderTopLeftRadius, marked: !!el.__mnMark };
})()`);
console.log('light:', JSON.stringify(await read()));
await page.evaluate(`document.querySelector('.glass-search-trigger').__mnMark = true`);
await page.emulateMedia({ colorScheme: 'dark' });
await page.waitForTimeout(900);
console.log('dark :', JSON.stringify(await read()));
await page.screenshot({ path: '/tmp/dual-rust2-dark.png' });
await browser.close();
