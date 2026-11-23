import { chromium } from 'playwright-core';
import fs from 'node:fs';
const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8097/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(2500);
const b64 = fs.readFileSync('/tmp/allblocks.zip').toString('base64');
const res = await page.evaluate(async (b64) => {
  const out = {};
  try {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    out.zipInput = (() => { try { window.MynoteIdb.validateZipInput(bytes); return 'ok'; } catch (e) { return 'ERR ' + e.message; } })();
    const unzipped = await window.MynoteZip.checkedZip(bytes);
    out.unzippedKeys = Object.keys(unzipped);
    const backup = JSON.parse(fflate.strFromU8(unzipped['memos.json']));
    out.validate = (() => { try { window.MynoteIdb.validateBackupData(backup); return 'ok'; } catch (e) { return 'ERR ' + e.message; } })();
    const db = await window.MynoteIdb.getDB();
    try {
      const r = await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
      out.restore = JSON.stringify(r);
    } catch (e) {
      out.restore = 'ERR ' + e.message;
    }
  } catch (e) {
    out.fatal = e.message;
  }
  return out;
}, b64);
console.log(JSON.stringify(res, null, 1));
await browser.close();
