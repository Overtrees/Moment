// spike 50 卡档位：测较矮内容高（~4.5k px）下 body 滚动全程渲染
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const OUT = '/home/hatch/workspace/mynote-shots-round6';
mkdirSync(OUT, { recursive: true });
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:8097/', { waitUntil: 'load' });
await page.waitForTimeout(12000);
await page.touchscreen.tap(172, 108); // 50 卡
await page.waitForTimeout(1500);
console.log('dims50:', JSON.stringify(await page.evaluate(() => ({
  scrollH: document.documentElement.scrollHeight,
  hostH: document.getElementById('host')?.style.height,
}))));
await page.evaluate(() => window.scrollTo(0, 2000));
await page.waitForTimeout(800);
console.log('scrollY:', await page.evaluate(() => window.scrollY));
await page.screenshot({ path: `${OUT}/55-spike50-scrolled.png` });
await page.evaluate(() => window.scrollTo(0, 1e9));
await page.waitForTimeout(800);
console.log('scrollY bottom:', await page.evaluate(() => window.scrollY));
await page.screenshot({ path: `${OUT}/56-spike50-bottom.png` });
console.log('pageerrors:', JSON.stringify(errors));
await browser.close();
