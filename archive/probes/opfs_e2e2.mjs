import { chromium } from 'playwright-core';
import fs from 'node:fs';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(365, 42); // 导入
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/opfs-dialog.png' });
const fcPromise = page.waitForEvent('filechooser', { timeout: 15000 });
await page.mouse.click(305, 505); // 继续导入（对话框右按钮，位置待截图确认）
const fc = await fcPromise;
await fc.setFiles('/tmp/opfs-test.zip');
await page.waitForTimeout(3000);
await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
const dlPromise = page.waitForEvent('download', { timeout: 15000 });
await page.mouse.click(400, 42); // 导出
const dl = await dlPromise;
await dl.saveAs('/tmp/opfs-export.zip');
console.log('EXPORTED size:', fs.statSync('/tmp/opfs-export.zip').size);
await browser.close();
