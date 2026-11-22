// 滚动审计探针三：原版 L3 恢复 / E3 菜单滚动关 / E4 斜杠滚动跟随（重新播种 fixture）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const ORIG = 'http://localhost:8099/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 100)));
await page.goto(ORIG, { waitUntil: 'load' });
await page.waitForTimeout(2000);
const b64 = fs.readFileSync('/tmp/scroll_test.zip').toString('base64');
const r = await page.evaluate(async (b64s) => {
  const bin = atob(b64s);
  const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  const unzipped = await window.MynoteZip.checkedZip(arr);
  const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
  return 'ok';
}, b64);
console.log('seed', r);
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2500);
const scrollTo = async (y) => { await page.evaluate((v) => window.scrollTo(0, v), y); await page.waitForTimeout(350); };
const openLong = async () => {
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
    if (el) el.click();
  });
  await page.waitForTimeout(1300);
  return page.evaluate(() => !!document.querySelector('.editor-body'));
};
// L3
await scrollTo(99999);
const yList = await page.evaluate(() => window.scrollY);
console.log('ORIG L3 listY(max)', yList, 'opened', await openLong(), 'editorY', await page.evaluate(() => window.scrollY));
await page.click('.editor-fab.left');
await page.waitForTimeout(900);
console.log('ORIG L3 backY', await page.evaluate(() => window.scrollY), 'list?', await page.evaluate(() => !!document.querySelector('.list-item')));
// E3
console.log('reopened', await openLong());
await page.click('.editor-fab.right');
await page.waitForTimeout(600);
console.log('ORIG E3 menu open?', await page.evaluate(() => !!document.querySelector('.editor-menu-panel')));
await scrollTo(200);
console.log('ORIG E3 menu after scroll200?', await page.evaluate(() => !!document.querySelector('.editor-menu-panel')));
// E4
await scrollTo(0);
await page.evaluate(() => {
  const p = document.querySelector('.editor-body [data-type="paragraph"]') || document.querySelector('.editor-body');
  if (p) { p.focus(); const r = document.createRange(); r.selectNodeContents(p); r.collapse(false); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
});
await page.keyboard.type('/');
await page.waitForTimeout(800);
const sp1 = await page.evaluate(() => { const p = document.querySelector('.slash-panel'); return p ? Math.round(p.getBoundingClientRect().top) : -1; });
console.log('ORIG E4 slash top before', sp1);
await scrollTo(200);
const sp2 = await page.evaluate(() => { const p = document.querySelector('.slash-panel'); return p ? Math.round(p.getBoundingClientRect().top) : -1; });
console.log('ORIG E4 slash top after scroll200', sp2);
await browser.close();
console.log('PROBE3 DONE');
