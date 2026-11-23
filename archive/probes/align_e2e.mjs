import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
// 斜杠面板（SVG 图标）
await page.mouse.click(200, 385);
await page.waitForTimeout(2500);
await page.mouse.click(200, 560);
await page.waitForTimeout(500);
await page.keyboard.type('/');
await page.waitForTimeout(1000);
await page.screenshot({ path: '/tmp/align-slash.png' });
await page.keyboard.press('Escape');
await page.mouse.click(31, 33); // 返回 FAB
await page.waitForTimeout(1500);
// 导入图片测试备份：头像→设置→备份与恢复→从本地文件恢复
await page.touchscreen.tap(52, 52);
await page.waitForTimeout(1200);
await page.touchscreen.tap(210, 285);
await page.waitForTimeout(1200);
const fc = page.waitForEvent('filechooser', { timeout: 10000 });
await page.touchscreen.tap(210, 415); // 从本地文件恢复
await page.waitForTimeout(800);
await page.touchscreen.tap(305, 505); // 继续恢复（弹窗按钮位置待核）
const chooser = await fc;
await chooser.setFiles('/tmp/img-test.zip');
await page.waitForTimeout(2500);
await page.screenshot({ path: '/tmp/align-backup-after.png' });
await page.mouse.click(31, 33);
await page.waitForTimeout(800);
await page.mouse.click(31, 33);
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/align-list-after.png' });
await page.mouse.click(200, 300);
await page.waitForTimeout(2500);
await page.screenshot({ path: '/tmp/align-image.png' });
await browser.close();
