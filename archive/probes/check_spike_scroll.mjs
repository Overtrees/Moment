// spike 滚动态检查：滚到中段截图——面板应完全消失、胶囊贴顶；
// 再滚到底部截图——标记停靠。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:8097/', { waitUntil: 'load' });
await page.waitForTimeout(13000);
await page.evaluate(() => window.scrollTo(0, 4000));
await page.waitForTimeout(900);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/67-spike-overlay-mid.png' });
const mid = await page.evaluate(() => window.scrollY);
await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(900);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/68-spike-overlay-bottom.png' });
const bot = await page.evaluate(() => ({
  y: window.scrollY,
  max: document.documentElement.scrollHeight - window.innerHeight,
}));
console.log('mid scrollY:', mid, 'bottom:', JSON.stringify(bot), 'errors:', JSON.stringify(errors));
await browser.close();
