import { chromium } from 'playwright-core';
import fs from 'node:fs';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 200);
await page.waitForTimeout(2500);
await page.mouse.click(352, 42); // 导出图标
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/export-sheet2.png' });
const dl1 = page.waitForEvent('download', { timeout: 15000 });
await page.mouse.click(200, 695); // Markdown 行
const d1 = await dl1;
await d1.saveAs('/tmp/export-test.md');
console.log('MD name:', d1.suggestedFilename(), 'size:', fs.statSync('/tmp/export-test.md').size);
await page.mouse.click(352, 42);
await page.waitForTimeout(1000);
const dl2 = page.waitForEvent('download', { timeout: 15000 });
await page.mouse.click(200, 767); // HTML 行
const d2 = await dl2;
await d2.saveAs('/tmp/export-test.html');
console.log('HTML name:', d2.suggestedFilename(), 'size:', fs.statSync('/tmp/export-test.html').size);
await browser.close();
