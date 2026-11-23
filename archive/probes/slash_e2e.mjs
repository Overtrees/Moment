import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 200); // 打开第一条备忘
await page.waitForTimeout(3000);
await page.mouse.click(150, 200); // 点进正文段落
await page.waitForTimeout(600);
await page.keyboard.type('/yy', { delay: 120 });
await page.waitForTimeout(900);
await page.screenshot({ path: '/tmp/slash-panel.png' });
await page.mouse.click(200, 864); // 面板第二行：音乐卡片
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/slash-after.png' });
console.log('PAGE_ERRORS:', errors.length, errors.slice(0, 2).join(' | '));
await browser.close();
