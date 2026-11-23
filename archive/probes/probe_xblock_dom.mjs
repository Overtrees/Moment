// 临时探针：Rust 编辑页块 DOM 结构
import { chromium } from 'playwright-core';
const url = 'http://localhost:8211/';
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
await page.setInputFiles('#file-import', 'fixtures/xblock.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 }).catch(() => {});
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
await page.waitForTimeout(400);
const pt = await page.evaluate(() => {
  const card = [...document.querySelectorAll('.list-item, .img-card')]
    .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === 'XB合并');
  if (!card) return null;
  const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
console.log('pt', JSON.stringify(pt));
await page.mouse.click(pt.x, pt.y);
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(900);
const dump = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const walk = (el, d) => [...el.children].map((c) => ({
    d, tag: c.tagName, cls: (c.className || '').slice(0, 30),
    bid: c.getAttribute('data-bid') || '', wrap: c.getAttribute('data-wrapbid') || '',
    ce: c.getAttribute('contenteditable'), text: (c.textContent || '').slice(0, 14),
    kids: d < 2 ? walk(c, d + 1) : [],
  }));
  return walk(body, 0);
});
console.log(JSON.stringify(dump, null, 1).slice(0, 3000));
await browser.close();
