import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errs = [];
page.on('pageerror', e => errs.push(String(e)));
try {
  await page.goto('https://mynote-flutter.pages.dev', { waitUntil: 'load', timeout: 45000 });
} catch (e) { console.log('goto err', String(e).slice(0,200)); }
await page.waitForTimeout(20000);
const info = await page.evaluate(() => ({
  loading: !!document.getElementById('app-loading'),
  bodyChildren: Array.from(document.body.children).map(c => c.tagName + '#' + (c.id||'')),
  spacerH: document.getElementById('spacer')?.style.height || '',
  scrollH: document.documentElement.scrollHeight,
  diag: (localStorage.getItem('mynote_diag_v1') || '').slice(-600),
})).catch(e => ({ evalErr: String(e) }));
console.log(JSON.stringify(info, null, 1));
console.log('pageerrors:', errs.slice(0,5));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/99-live-check.png' });
await browser.close();
