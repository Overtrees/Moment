// 滚动审计探针四：双栏独立滚动（宽屏 1280×800），Rust 与原版
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

// ---------- Rust ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR RUST', String(e).slice(0, 100)));
  await page.goto('http://localhost:8098/', { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/tmp/scroll_test.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
    if (el) el.click();
  });
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(600);
  // 开双栏：••• 菜单 → .twopane-row
  await page.evaluate(() => document.querySelector('.editor-fab.right')?.click());
  await page.waitForTimeout(500);
  await page.evaluate(() => { const row = [...document.querySelectorAll('.twopane-row')][0]; if (row) row.click(); });
  await page.waitForTimeout(900);
  console.log('RUST menu still open?', await page.evaluate(() => !!document.querySelector('.menu-scrim')));
  await page.evaluate(() => document.querySelector('.menu-scrim')?.click());
  await page.waitForTimeout(400);
  const t1 = await page.evaluate(() => {
    const cs = document.querySelectorAll('.editor-body.is-independent-scroll .editor-column');
    if (cs.length !== 2) return { n: cs.length };
    cs[0].scrollTop = 200;
    return { n: 2, l: cs[0].scrollTop, r: cs[1].scrollTop, winY: window.scrollY, lsh: cs[0].scrollHeight, lch: cs[0].clientHeight };
  });
  await page.waitForTimeout(300);
  const t1b = await page.evaluate(() => {
    const cs = document.querySelectorAll('.editor-body.is-independent-scroll .editor-column');
    return { l: cs[0].scrollTop, r: cs[1].scrollTop, winY: window.scrollY };
  });
  console.log('RUST T1 cols', JSON.stringify(t1), 'after300ms', JSON.stringify(t1b));
  // 切篇：回列表开另一篇再回长文，列滚动应归零
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
    if (el) el.click();
  });
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(700);
  const t2 = await page.evaluate(() => {
    const cs = document.querySelectorAll('.editor-body.is-independent-scroll .editor-column');
    return cs.length === 2 ? { l: cs[0].scrollTop, r: cs[1].scrollTop } : { n: cs.length };
  });
  console.log('RUST T2 after memo switch', JSON.stringify(t2));
  await ctx.close();
}

// ---------- 原版 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR ORIG', String(e).slice(0, 100)));
  await page.goto('http://localhost:8099/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(2000);
  const b64 = fs.readFileSync('/tmp/scroll_test.zip').toString('base64');
  await page.evaluate(async (b64s) => {
    const bin = atob(b64s);
    const arr = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    const unzipped = await window.MynoteZip.checkedZip(arr);
    const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
    const db = await window.MynoteIdb.getDB();
    await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
    localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
  }, b64);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
    if (el) el.click();
  });
  await page.waitForTimeout(1300);
  console.log('ORIG editor?', await page.evaluate(() => !!document.querySelector('.editor-body')));
  await page.click('.editor-fab.right');
  await page.waitForTimeout(600);
  const tog = await page.evaluate(() => {
    const t = document.querySelector('.editor-column-mode-toggle');
    if (t) { t.click(); return 'clicked'; }
    return 'nf';
  });
  await page.waitForTimeout(900);
  console.log('ORIG toggle', tog);
  const t1 = await page.evaluate(() => {
    const cs = document.querySelectorAll('.editor-body.is-independent-scroll .editor-column');
    if (cs.length !== 2) return { n: cs.length, bodyCls: document.querySelector('.editor-body')?.className };
    cs[0].scrollTop = 200;
    return { n: 2, l: cs[0].scrollTop, r: cs[1].scrollTop, winY: window.scrollY, lsh: cs[0].scrollHeight, lch: cs[0].clientHeight };
  });
  await page.waitForTimeout(300);
  const t1b = await page.evaluate(() => {
    const cs = document.querySelectorAll('.editor-body.is-independent-scroll .editor-column');
    return cs.length === 2 ? { l: cs[0].scrollTop, r: cs[1].scrollTop, winY: window.scrollY } : { n: cs.length };
  });
  console.log('ORIG T1 cols', JSON.stringify(t1), 'after300ms', JSON.stringify(t1b));
  await ctx.close();
}
await browser.close();
console.log('PROBE4 DONE');
