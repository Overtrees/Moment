import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8097/', { waitUntil: 'load' });
await page.waitForTimeout(10000);
const boot = await page.evaluate(() => ({ spacer: document.getElementById('spacer')?.style.height, scrollH: document.documentElement.scrollHeight }));
console.log('list boot:', JSON.stringify(boot));
// 切到编辑器页签（按钮行第二个）
await page.touchscreen.tap(102, 158);
await page.waitForTimeout(2500);
const ed = await page.evaluate(() => ({ spacer: document.getElementById('spacer')?.style.height, scrollH: document.documentElement.scrollHeight, y: window.scrollY }));
console.log('editor tab:', JSON.stringify(ed));
await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/59-spike-v3-editor-top.png' });
// body 滚到中段，看同步跟随
await page.evaluate(() => window.scrollTo(0, 3000));
await page.waitForTimeout(1200);
console.log('mid y:', await page.evaluate(() => window.scrollY));
await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/60-spike-v3-editor-mid.png' });
// 滚到底：文末应出现
await page.evaluate(() => window.scrollTo(0, 1e9));
await page.waitForTimeout(1200);
console.log('bottom y:', await page.evaluate(() => window.scrollY));
await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/61-spike-v3-editor-bottom.png' });
// 点一段正文放光标
await page.touchscreen.tap(210, 400);
await page.waitForTimeout(800);
await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/62-spike-v3-editor-tap.png' });
console.log('pageerrors:', errors.slice(0, 3));
await browser.close();
