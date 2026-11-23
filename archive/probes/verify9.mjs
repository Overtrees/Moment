import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 160)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
// 打开「装修踩坑清单」
await page.touchscreen.tap(210, 320);
await page.waitForTimeout(3000);
// 点第一个待办文本末尾进入编辑（待办也是 TextNode，还原/渲染同路径）
await page.touchscreen.tap(360, 176);
await page.waitForTimeout(800);
await page.keyboard.type(' 前**加粗**后');
await page.waitForTimeout(900);
// 点到另一个待办 → 触发失焦渲染
await page.touchscreen.tap(300, 232);
await page.waitForTimeout(1200);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/11-md-render.png' });
// 再点回已渲染的加粗处 → 还原源码
await page.touchscreen.tap(330, 176);
await page.waitForTimeout(1200);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/12-md-restore.png' });
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').map(e => String(e)).slice(-10); } catch { return ['?']; } });
console.log('DIAG:', JSON.stringify(diag, null, 0));
await browser.close();
