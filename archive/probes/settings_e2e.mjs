import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 200); // 进编辑器产生日志
await page.waitForTimeout(2500);
await page.mouse.click(24, 42); // 返回列表
await page.waitForTimeout(1500);
await page.mouse.click(268, 42); // 设置齿轮（导入/导出左边新增）
await page.waitForTimeout(1500);
await page.screenshot({ path: '/tmp/settings-page.png' });
await page.mouse.click(200, 150); // 诊断日志行
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/diag-page.png' });
console.log('PAGE_ERRORS:', errors.length, errors.slice(0,1).join(''));
await browser.close();
