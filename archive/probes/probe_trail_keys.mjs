// 尾随段方向键跨块小探针（记录型）：甲 [段, 代码预览, 尾随段]
// 1) 点入尾随段 → ArrowUp：选区去向
// 2) 点首段末尾 → ArrowDown 两次：选区去向
import { chromium } from 'playwright-core';
const url = process.argv[2] || 'http://localhost:8208/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', 'fixtures/trail.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForTimeout(600);
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
await page.waitForTimeout(500);
const openMemo = async (t) => {
  const titlePt = () => page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt && !e.querySelector('.expand-btn'));
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, t);
  let pt = null;
  for (let a = 0; a < 4 && !pt; a++) {
    pt = await titlePt();
    if (pt) break;
    const ex = await page.evaluate(() => {
      const b = document.querySelector('.expand-btn');
      if (!b) return null;
      b.scrollIntoView({ block: 'center' });
      const r = b.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (ex) { await page.mouse.click(ex.x, ex.y); await page.waitForTimeout(700); } else await page.waitForTimeout(400);
  }
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(800);
};
const selInfo = () => page.evaluate(() => {
  const s = window.getSelection();
  if (!s || !s.rangeCount) return null;
  const n = s.anchorNode;
  const el = n && (n.nodeType === 1 ? n : n.parentElement);
  const bidEl = el && el.closest ? el.closest('[data-bid]') : null;
  return { bid: bidEl ? bidEl.dataset.bid : '', off: s.anchorOffset, near: (el?.textContent || '').slice(0, 12) };
});
await openMemo('尾随甲');
const kids = await page.evaluate(() => [...document.querySelector('.editor-body').children].length);
console.log('children', kids);
// 1) 点尾随段（最后一个子元素）→ ArrowUp
const lastPt = await page.evaluate(() => {
  const el = document.querySelector('.editor-body').lastElementChild;
  const r = el.getBoundingClientRect();
  return { x: r.x + 16, y: r.y + r.height / 2 };
});
await page.mouse.click(lastPt.x, lastPt.y);
await page.waitForTimeout(400);
console.log('in trail', JSON.stringify(await selInfo()));
await page.keyboard.press('ArrowUp');
await page.waitForTimeout(500);
console.log('after ArrowUp', JSON.stringify(await selInfo()));
// 2) 点首段 → End → ArrowDown 两次
const firstPt = await page.evaluate(() => {
  const el = document.querySelector('[data-bid="ta1"]');
  const r = el.getBoundingClientRect();
  return { x: r.x + 30, y: r.y + r.height / 2 };
});
await page.mouse.click(firstPt.x, firstPt.y);
await page.waitForTimeout(400);
console.log('after click ta1', JSON.stringify(await selInfo()), 'pt', JSON.stringify(firstPt));
await page.keyboard.press('End');
await page.keyboard.press('ArrowDown');
await page.waitForTimeout(500);
console.log('after ArrowDown x1', JSON.stringify(await selInfo()));
await page.keyboard.press('ArrowDown');
await page.waitForTimeout(500);
console.log('after ArrowDown x2', JSON.stringify(await selInfo()));
await browser.close();
