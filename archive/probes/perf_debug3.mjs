// 搜索行为验证：输入 ZEBRA 后 dump 页面文本与 Diag。
import { chromium } from 'playwright-core';
const base = process.argv[2];
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 15000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 15000 });
await page.setInputFiles('#file-import', '/tmp/big300.zip');
await page.waitForSelector('.backup-modal', { timeout: 15000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 30000 });
await page.reload({ waitUntil: 'load' });
await page.waitForFunction(() => [...document.querySelectorAll('.list-item .item-title-text, .img-card-title-text')]
  .some((e) => e.textContent.includes('压测笔记')), null, { timeout: 60000 });
await page.waitForTimeout(800);
await page.evaluate(() => document.querySelector('.glass-search-trigger')?.click());
await page.waitForSelector('.glass-search-input', { timeout: 10000 });
await page.evaluate(() => document.querySelector('.glass-search-input')?.focus());
const t0 = Date.now();
await page.keyboard.type('ZEBRA', { delay: 30 });
for (let i = 0; i < 5; i++) {
  await page.waitForTimeout(1000);
  const st = await page.evaluate(() => ({
    val: document.querySelector('.glass-search-input')?.value || '',
    hasZebra: document.body.innerText.includes('ZEBRA'),
    hasUnique: document.body.innerText.includes('独特关键词'),
    items: document.querySelectorAll('.list-item, .img-card').length,
    head: document.body.innerText.slice(0, 200).replace(/\n/g, ' | '),
  }));
  console.log(`t+${i + 1}s`, JSON.stringify(st));
  if (st.hasUnique) { console.log('searchMs ~', Date.now() - t0); break; }
}
const diag = await page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').filter((l) => /SEARCH|PERF/.test(l)).slice(-6); } catch { return []; }
});
console.log('DIAG:', JSON.stringify(diag));
await browser.close();
