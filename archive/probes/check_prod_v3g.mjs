// 探针 3：建 3 条后走设置→备份导出 ZIP，读 memos.json 定性数据层。
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(14000);

for (const t of ['甲一', '乙二', '丙三']) {
  await page.touchscreen.tap(210, 233);
  await page.waitForTimeout(2500);
  await page.touchscreen.tap(210, 420);
  await page.waitForTimeout(600);
  await page.keyboard.insertText(t);
  await page.waitForTimeout(1000);
  await page.touchscreen.tap(39, 30);
  await page.waitForTimeout(2500);
}
// 头像 → 设置
await page.touchscreen.tap(52, 84);
await page.waitForTimeout(2000);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/91-prod-v3-settings.png' });
// 备份与恢复行
await page.touchscreen.tap(210, 322);
await page.waitForTimeout(2000);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/92-prod-v3-backup.png' });
// 导出备份行 + 等下载
const dlPromise = page.waitForEvent('download', { timeout: 20000 }).catch(() => null);
await page.touchscreen.tap(210, 322);
const dl = await dlPromise;
if (dl) {
  const p = '/tmp/prod_v3_export.zip';
  await dl.saveAs(p);
  console.log('downloaded:', p, fs.statSync(p).size);
} else {
  console.log('NO DOWNLOAD');
  await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/93-prod-v3-export-fail.png' });
}
await browser.close();
