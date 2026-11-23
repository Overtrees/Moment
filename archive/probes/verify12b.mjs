import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(12000);
await page.touchscreen.tap(210, 320); // 装修（对照）
await page.waitForTimeout(2500);
let diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').map(e => String(e)).slice(-3); } catch { return ['?']; } });
console.log('AFTER ZHUANGXIU TAP:', JSON.stringify(diag));
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(1800);
for (const y of [745, 775, 800]) {
  await page.touchscreen.tap(210, y);
  await page.waitForTimeout(2200);
  diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').map(e => String(e)).slice(-3); } catch { return ['?']; } });
  console.log('AFTER MUSIC TAP y=' + y + ':', JSON.stringify(diag));
  const loaded = diag.some(d => d.includes('load memo=demo_music'));
  if (loaded) break;
}
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/22-tapscan.png' });
await browser.close();
