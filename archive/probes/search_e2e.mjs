import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(295, 42); // 搜索图标
await page.waitForTimeout(1000);
await page.keyboard.type('莫奈', { delay: 120 });
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/search-result.png' });
await page.keyboard.press('Control+a');
await page.keyboard.type('spotify', { delay: 100 });
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/search-result2.png' });
await browser.close();
