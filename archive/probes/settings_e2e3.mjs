import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 260); // 打开第二条备忘（产生 EDITOR 日志）
await page.waitForTimeout(2500);
await page.mouse.click(24, 42);
await page.waitForTimeout(1200);
await page.mouse.click(330, 42); // 设置
await page.waitForTimeout(1200);
await page.mouse.click(200, 140); // 诊断日志行中心
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/diag-page3.png' });
await browser.close();
