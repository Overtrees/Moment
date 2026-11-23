import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8097/', { waitUntil: 'load' });
await page.waitForTimeout(12000);
const state = await page.evaluate(() => ({
  loading: document.getElementById('loading')?.style.display,
  spacerH: document.getElementById('spacer')?.style.height,
  hostH: document.getElementById('host')?.getBoundingClientRect().height,
  bodyChildren: [...document.body.children].map(e => e.tagName + '#' + (e.id || '')),
  scrollH: document.documentElement.scrollHeight,
}));
console.log(JSON.stringify(state, null, 1));
console.log('pageerrors:', errors.slice(0, 3));
await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/58-spike-v3-local.png' });
await browser.close();
