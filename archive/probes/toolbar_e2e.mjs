import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 200);
await page.waitForTimeout(3000);
await page.mouse.click(60, 118); // 第一段行首附近
await page.waitForTimeout(500);
await page.keyboard.down('Shift');
for (let i = 0; i < 3; i++) await page.keyboard.press('ArrowRight');
await page.keyboard.up('Shift');
await page.waitForTimeout(600);
await page.screenshot({ path: '/tmp/toolbar-shown.png' });
console.log('PAGE_ERRORS:', errors.length);
await browser.close();
