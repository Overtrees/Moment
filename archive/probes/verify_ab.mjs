import { chromium } from 'playwright-core';
const url = process.argv[2];
const browser = await chromium.launch({ executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell', args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(9000);
const info = await page.evaluate(() => ({
  flutterView: !!document.querySelector('flutter-view'),
  rootH: document.getElementById('root')?.getBoundingClientRect().height ?? null,
  docH: document.documentElement.scrollHeight,
  hostH: document.getElementById('host')?.getBoundingClientRect().height ?? null,
}));
console.log(JSON.stringify({ url, ...info, pageerrors: errors }));
await browser.close();
