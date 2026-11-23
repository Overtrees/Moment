import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
page.on('download', d => console.log('DOWNLOAD:', d.suggestedFilename()));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(330, 42); // 设置齿轮（搜索图标加入后位置：搜索295/设置330）
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/settings-v2.png' });
await page.mouse.click(200, 300); // 备份与恢复行（大致）
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/backup-page.png' });
await browser.close();
