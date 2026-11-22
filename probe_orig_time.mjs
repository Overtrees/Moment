import { chromium } from 'playwright-core';
import fs from 'node:fs';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8101/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(2500);
const b64 = fs.readFileSync(process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip').toString('base64');
await page.evaluate(async (b64) => {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  const unzipped = await window.MynoteZip.checkedZip(bytes);
  const backup = JSON.parse(fflate.strFromU8(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  try { localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos)); } catch (e) {}
}, b64);
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2500);
console.log('LS_AFTER_RESTORE', await page.evaluate(() => {
  const arr = JSON.parse(localStorage.getItem('memos_app_v2') || '[]');
  return arr.map((m) => m.title + '@' + m.updatedAt).join(' ; ');
}));
console.log('LIST_TEXT', await page.evaluate(() => document.body.innerText.slice(0, 300).replace(/\n/g, '|')));
await page.click('text=冬日');
await page.waitForTimeout(1800);
console.log('META', await page.evaluate(() => document.querySelector('.editor-title-meta')?.textContent || ''));
console.log('LS_AFTER_OPEN', await page.evaluate(() => {
  const arr = JSON.parse(localStorage.getItem('memos_app_v2') || '[]');
  return arr.map((m) => m.title + '@' + m.updatedAt).join(' ; ');
}));
await browser.close();
