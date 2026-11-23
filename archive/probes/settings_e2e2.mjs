import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(330, 42); // 设置齿轮
await page.waitForTimeout(1500);
await page.screenshot({ path: '/tmp/settings-page2.png' });
await page.mouse.click(200, 168); // 诊断日志行
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/diag-page2.png' });
console.log('PAGE_ERRORS:', errors.length);
await browser.close();
