import { chromium } from 'playwright-core';
import fs from 'node:fs';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
// 导入带附件的 ZIP
const fcPromise = page.waitForEvent('filechooser');
await page.mouse.click(365, 42); // 导入按钮
const fc = await fcPromise;
await fc.setFiles('/tmp/opfs-test.zip');
await page.waitForTimeout(3000);
await page.screenshot({ path: '/tmp/opfs-imported.png' });
// 重载页面（验证 OPFS 持久）
await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
// 导出并检查附件仍在
const dlPromise = page.waitForEvent('download', { timeout: 15000 });
await page.mouse.click(400, 42); // 导出按钮
const dl = await dlPromise;
await dl.saveAs('/tmp/opfs-export.zip');
console.log('EXPORTED size:', fs.statSync('/tmp/opfs-export.zip').size);
await browser.close();
