// Diag 链验证：胶囊粘贴后 mynote_diag_v1 应含 CARD 四段
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
await page.route('**/meta?url=*', async (route) => {
  await new Promise((r) => setTimeout(r, 2500));
  await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ title: '海阔天空', subtitle: 'Beyond', source: '网易云音乐', cover: '', type: 'music' }) }).catch(() => {});
});
await page.goto('http://localhost:8197/', { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('.detail .ed-line', { timeout: 10000 });
await page.waitForTimeout(900);
const n = await page.$$eval('.detail .ed-line', (els) => els.length);
await page.click(`.detail .ed-line >> nth=${n - 1}`);
await page.keyboard.press('End');
await page.keyboard.press('Enter');
await page.waitForTimeout(400);
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 6000 });
await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="musicCard"]')?.click());
await page.waitForSelector('.music-input-pill', { timeout: 6000 });
await page.evaluate(() => {
  const el = document.querySelector('.music-input-pill');
  const dt = new DataTransfer();
  dt.setData('text/plain', 'https://music.163.com/song?id=347230');
  el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
});
await page.waitForFunction(() => !document.querySelector('.link-card-skeleton'), { timeout: 20000 });
await page.waitForTimeout(500);
const lines = await page.evaluate(() => {
  const raw = localStorage.getItem('mynote_diag_v1') || '[]';
  const arr = JSON.parse(raw);
  return arr.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).filter((s) => s.includes('CARD'));
});
console.log(lines.join('\n'));
await browser.close();
