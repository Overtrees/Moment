import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 160)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
await page.touchscreen.tap(210, 320); // 装修踩坑清单
await page.waitForTimeout(3000);
await page.touchscreen.tap(220, 343); // 最后一个待办
await page.waitForTimeout(700);
await page.keyboard.press('Enter'); // 待办后插空段
await page.waitForTimeout(500);
await page.keyboard.type('正文[^a]与[^b]');
await page.keyboard.press('Enter');
await page.keyboard.type('[^b]: 乙定义');
await page.keyboard.press('Enter');
await page.keyboard.type('[^a]: 甲定义');
await page.waitForTimeout(800);
// 点回第一个待办 → 触发失焦渲染 + 重编号
await page.touchscreen.tap(220, 176);
await page.waitForTimeout(1500);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/13-footnote.png' });
// 点正文里的引用编号（正文段约在 y=395，编号在“正文”之后）
await page.touchscreen.tap(150, 395);
await page.waitForTimeout(1200);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/14-footnote-jump.png' });
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').map(e => String(e)).slice(-8); } catch { return ['?']; } });
console.log('DIAG:', JSON.stringify(diag, null, 0));
await browser.close();
