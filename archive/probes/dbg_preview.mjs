import { chromium } from 'playwright-core';
import fs from 'node:fs';
const browser = await chromium.launch({ executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell', args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8097/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(2200);
const b64 = fs.readFileSync('/tmp/preview_strip.zip').toString('base64');
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
await page.waitForTimeout(2200);
const prev = await page.evaluate(() => {
  const card = [...document.querySelectorAll('.list-item, .img-card')].find(e => e.textContent.includes('预览剥源测试'));
  if (!card) return 'CARD NOT FOUND';
  const p = card.querySelector('.item-preview, .img-card-preview, [class*=preview]');
  return p ? p.textContent : card.textContent;
});
console.log('ORIG PREVIEW:', prev);
await browser.close();
