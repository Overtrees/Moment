// 二分实验：探针时序下点卡不开的原因。
import { chromium } from 'playwright-core';
const base = process.argv[2];
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 160)));
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
console.log('import ok');
await page.reload({ waitUntil: 'load' });
await page.waitForFunction(() => [...document.querySelectorAll('.list-item .item-title-text, .img-card-title-text')]
  .some((e) => e.textContent.includes('压测笔记')), null, { timeout: 60000 });
await page.waitForTimeout(800);
const info = await page.evaluate(() => {
  const cards = [...document.querySelectorAll('.list-item, .img-card')];
  const target = cards.find((e) => e.textContent.includes('压测笔记'));
  const before = {
    nCards: cards.length,
    targetCls: target ? target.className : null,
    targetText: target ? target.textContent.slice(0, 40) : null,
    rect: target ? JSON.stringify(target.getBoundingClientRect()) : null,
    visible: target ? (target.offsetParent !== null) : null,
  };
  if (target) target.click();
  return before;
});
console.log('CLICK INFO:', JSON.stringify(info));
// 先展开（首卡属折叠组时首击只展开），再点一次打开
await page.waitForTimeout(800);
await page.evaluate(() => {
  const card = [...document.querySelectorAll('.list-item, .img-card')]
    .find((e) => e.textContent.includes('压测笔记'));
  card && card.click();
});
await page.waitForTimeout(1500);
console.log('state:', await page.evaluate(() => ({
  detail: !!document.querySelector('.detail'),
  editorBody: !!document.querySelector('.editor-body'),
  title: document.querySelector('#editor-title-text')?.textContent || '',
  bidAll: document.querySelectorAll('[data-bid]').length,
  bidInBody: document.querySelectorAll('.editor-body [data-bid]').length,
  bidInDetail: document.querySelectorAll('.detail [data-bid]').length,
  bodyCls: document.querySelector('.editor-body')?.className || '',
  bodyChildren: document.querySelector('.editor-body')?.children.length ?? -1,
  child0: document.querySelector('.editor-body')?.children[0]?.outerHTML.slice(0, 300) || '',
  editables: document.querySelectorAll('.editor-body [contenteditable]').length,
})));
const diag = await page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').slice(-6); } catch { return []; }
});
console.log('DIAG:', JSON.stringify(diag));
await browser.close();
