import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8246/', { waitUntil: 'load' });
await page.waitForTimeout(2500);
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', '/tmp/hdrprobe/b2.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
async function openMemo(part) {
  await page.waitForFunction((t) => [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].some((e) => e.textContent.includes(t)), part, { timeout: 10000 });
  for (let i = 0; i < 3; i++) {
    await page.evaluate((t) => { const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes(t)); if (el) el.click(); }, part);
    try { await page.waitForSelector('.detail', { timeout: 3000 }); break; } catch (e) {}
  }
  await page.waitForTimeout(600);
}
async function st(label) {
  const s = await page.evaluate(() => {
    const av = document.querySelector('.editor-avatar-button'); const cap = document.querySelector('.editor-title-capsule');
    const r = (el) => { const b = el.getBoundingClientRect(); return { y: +b.y.toFixed(1), w: +b.width.toFixed(1), cy: +(b.y + b.height / 2).toFixed(1) }; };
    return { cls: document.querySelector('.editor-title-dock').className, y: window.scrollY, av: r(av), cap: r(cap) };
  });
  console.log(`[${label}] cls="${s.cls}" y=${s.y} row=${Math.abs(s.av.cy - s.cap.cy) < 4} capW=${s.cap.w} capY=${s.cap.y}`);
}
for (const [part, label] of [['八个字的标题在此', 't08'], ['十个字的标题正好十', 't09'], ['二十字长标题', 't23']]) {
  await openMemo(part);
  await st(label + ' top');
  await page.evaluate(() => window.scrollTo(0, 400));
  await page.waitForTimeout(500);
  await st(label + ' scrolled');
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.waitForTimeout(400);
}
await browser.close();
console.log('DONE');
