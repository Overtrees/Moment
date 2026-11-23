import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round6';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const logs = [];
page.on('console', m => logs.push(m.type() + ': ' + m.text().slice(0, 160)));
page.on('pageerror', e => logs.push('PAGEERROR: ' + String(e).slice(0, 200)));
ctx.on('page', p => logs.push('POPUP OPENED: ' + p.url().slice(0, 120)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(10000);
const iso = await page.evaluate(() => ({
  isolated: window.crossOriginIsolated,
  wasm: performance.getEntriesByType('resource').map(e => e.name).filter(n => n.includes('wasm') || n.includes('canvaskit')).slice(0, 6),
}));
console.log('ISO:', JSON.stringify(iso));
// 进设置 → 备份与恢复
await page.touchscreen.tap(52, 84);
await page.waitForTimeout(2500);
await page.touchscreen.tap(210, 328);
await page.waitForTimeout(2500);
await page.screenshot({ path: OUT + '/05-backup.png' });
// 点「连接 Google」
await page.touchscreen.tap(210, 545);
await page.waitForTimeout(5000);
await page.screenshot({ path: OUT + '/06-drive.png' });
const diag = await page.evaluate(() => { try { return (localStorage.getItem('mynote_diag_v1') || '').slice(-600); } catch (e) { return 'ERR'; } });
console.log('DIAG:', diag);
console.log('LOGS:', logs.filter(l => /oop|COOP|COEP|popup|GIS|google|error/i.test(l)).slice(0, 12).join('\n'));
await browser.close();
