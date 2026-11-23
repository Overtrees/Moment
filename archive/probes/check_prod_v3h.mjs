// 探针 4：建 3 条 → 导出并确认 → 读 memos.json；再回列表等 6 秒截图，
// 并滚列表看今天组到底有几张卡。
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
await page.waitForTimeout(3000);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/94-prod-v3-list-after-wait.png' });
const st = await page.evaluate(() => ({
  spacer: document.getElementById('spacer')?.style.height || '',
  scrollH: document.documentElement.scrollHeight,
}));
console.log('LIST STATE:', JSON.stringify(st));

await page.touchscreen.tap(52, 84);
await page.waitForTimeout(2000);
await page.touchscreen.tap(210, 322);
await page.waitForTimeout(2000);
await page.touchscreen.tap(210, 322);
await page.waitForTimeout(1500);
const dlPromise = page.waitForEvent('download', { timeout: 25000 }).catch(() => null);
await page.touchscreen.tap(210, 455);
const dl = await dlPromise;
if (dl) {
  await dl.saveAs('/tmp/prod_v3_export.zip');
  console.log('downloaded:', fs.statSync('/tmp/prod_v3_export.zip').size);
} else {
  console.log('NO DOWNLOAD');
  await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/95-prod-v3-export-fail2.png' });
}
await browser.close();
