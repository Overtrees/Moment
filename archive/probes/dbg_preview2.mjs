import { chromium } from 'playwright-core';
import fs from 'node:fs';
const browser = await chromium.launch({ executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell', args: ['--no-sandbox'] });
async function origPreview(zipPath) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto('http://localhost:8097/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(2000);
  const b64 = fs.readFileSync(zipPath).toString('base64');
  await page.evaluate(async (b64) => {
    const bin = atob(b64); const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const unzipped = await window.MynoteZip.checkedZip(bytes);
    const backup = JSON.parse(fflate.strFromU8(unzipped['memos.json']));
    const db = await window.MynoteIdb.getDB();
    await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
    try { localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos)); } catch (e) {}
  }, b64);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2000);
  const txt = await page.evaluate(() => [...document.querySelectorAll('.list-item, .img-card')].map(e => e.textContent));
  await ctx.close();
  return txt;
}
async function rustPreview(zipPath) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  await page.goto('http://localhost:8096/', { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zipPath);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  const txt = await page.evaluate(() => [...document.querySelectorAll('.list-item, .img-card')].map(e => e.textContent));
  await ctx.close();
  return txt;
}
for (const zip of ['/tmp/preview_strip.zip', process.env.HOME + '/workspace/Mynote/fixtures/allblocks.zip']) {
  const o = await origPreview(zip);
  const r = await rustPreview(zip);
  console.log('ZIP', zip.split('/').pop(), 'orig cards:', o.length, 'rust cards:', r.length);
  const cut = (t) => { const a = t.indexOf('[!NOTE]'); const b = t.indexOf('普通段落'); const k = a >= 0 ? a : b; return k >= 0 ? t.slice(k) : t; };
  const os = new Set(o.map(cut)), rs = new Set(r.map(cut));
  let same = true;
  for (const t of os) if (!rs.has(t)) { same = false; console.log('ONLY ORIG:', JSON.stringify(t)); }
  for (const t of rs) if (!os.has(t)) { same = false; console.log('ONLY RUST:', JSON.stringify(t)); }
  console.log(same ? 'PREVIEWS IDENTICAL' : 'PREVIEWS DIFFER');
}
await browser.close();
