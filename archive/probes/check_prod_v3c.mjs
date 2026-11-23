// 生产 v3 长列表验证：每轮回顶后再点新建，确保建出独立条目；
// 验列表占位高、滚动同步、底相等。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
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

for (let i = 0; i < 14; i++) {
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(500);
  await page.touchscreen.tap(210, 233);
  await page.waitForTimeout(1800);
  await page.touchscreen.tap(210, 420);
  await page.waitForTimeout(500);
  await page.keyboard.insertText(`独立条目 ${i + 1}`);
  await page.waitForTimeout(800);
  await page.touchscreen.tap(39, 30);
  await page.waitForTimeout(1800);
}
console.log('LONG LIST:', JSON.stringify(await state()));
await page.evaluate(() => window.scrollTo(0, 0));
await page.waitForTimeout(600);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/82-prod-v3-list2-top.png' });

await page.evaluate(() => window.scrollTo(0, 800));
await page.waitForTimeout(900);
console.log('LIST SCROLLED 800:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/83-prod-v3-list2-scrolled.png' });

await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(900);
const lb = await state();
console.log('LIST BOTTOM:', JSON.stringify(lb), 'maxMatch:', lb.y === lb.scrollH - lb.innerH);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/84-prod-v3-list2-bottom.png' });
console.log('pageerrors:', JSON.stringify(errors));
await browser.close();
