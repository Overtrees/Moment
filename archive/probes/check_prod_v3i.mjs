// 生产 v3 列表终验：矮视口（420x500）让演示+新建列表产生真实行程；
// 建 2 条后验占位高、滚动同步、页眉收缩、底相等。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 500 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(14000);

const state = () => page.evaluate(() => ({
  y: window.scrollY,
  spacer: document.getElementById('spacer')?.style.height || '',
  scrollH: document.documentElement.scrollHeight,
  innerH: window.innerHeight,
}));
console.log('LIST (500h):', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/96-prod-v3-list4-top.png' });

await page.evaluate(() => window.scrollTo(0, 300));
await page.waitForTimeout(900);
console.log('SCROLLED 300:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/97-prod-v3-list4-scrolled.png' });

await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(900);
const lb = await state();
console.log('BOTTOM:', JSON.stringify(lb), 'maxMatch:', lb.y === lb.scrollH - lb.innerH);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/98-prod-v3-list4-bottom.png' });
console.log('pageerrors:', JSON.stringify(errors));
await browser.close();
