import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
await page.goto('http://localhost:8246/', { waitUntil: 'load' });
await page.waitForTimeout(2500);
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', '/tmp/hdrprobe/b1.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
await page.waitForTimeout(1200);
await page.touchscreen.tap(196, 353);
for (let i = 0; i < 6; i++) {
  await page.waitForTimeout(1000);
  const st = await page.evaluate(() => ({
    detail: !!document.querySelector('.detail'),
    dock: !!document.querySelector('.editor-title-dock'),
    bodyStart: document.querySelector('#main').innerHTML.slice(0, 160),
  }));
  console.log(i + 1 + 's', JSON.stringify(st).slice(0, 260));
  if (st.dock) break;
}
console.log('diag tail:', await page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || '').slice(-500)));
await browser.close();
