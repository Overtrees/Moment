import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
await page.goto('http://localhost:8097/', { waitUntil: 'load' });
await page.waitForTimeout(12000);
await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/57-spike-fullpage.png', fullPage: true });
console.log('done');
await browser.close();
