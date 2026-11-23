// 生产 v3 长内容验证：新建长文（编辑器列高/平移/坞收缩/文末相等），
// 再建多条笔记让列表超一屏（列表同步/页眉收缩/底相等）。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(14000);

const state = () => page.evaluate(() => ({
  y: window.scrollY,
  spacer: document.getElementById('spacer')?.style.height || '',
  scrollH: document.documentElement.scrollHeight,
  innerH: window.innerHeight,
}));

// 1) 新建笔记 → 长文
await page.touchscreen.tap(210, 233);
await page.waitForTimeout(2500);
await page.touchscreen.tap(210, 420);
await page.waitForTimeout(800);
const lines = Array.from({ length: 150 }, (_, i) => `第 ${i + 1} 段 这是用于验证长文档滚动的填充文字。`).join('\n');
await page.keyboard.insertText(lines);
await page.waitForTimeout(4000);
console.log('LONG EDITOR:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/76-prod-v3-longed-top.png' });

await page.evaluate(() => window.scrollTo(0, 1500));
await page.waitForTimeout(900);
console.log('LONG EDITOR SCROLLED:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/77-prod-v3-longed-scrolled.png' });

await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(900);
const eb = await state();
console.log('LONG EDITOR BOTTOM:', JSON.stringify(eb), 'maxMatch:', eb.y === eb.scrollH - eb.innerH);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/78-prod-v3-longed-bottom.png' });

// 2) 返回列表，再建 13 条短笔记
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(2500);
for (let i = 0; i < 13; i++) {
  await page.touchscreen.tap(210, 233);
  await page.waitForTimeout(1600);
  await page.touchscreen.tap(210, 420);
  await page.waitForTimeout(500);
  await page.keyboard.insertText(`条目 ${i + 1} 填充列表高度`);
  await page.waitForTimeout(700);
  await page.touchscreen.tap(39, 30);
  await page.waitForTimeout(1600);
}
console.log('LONG LIST:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/79-prod-v3-longlist-top.png' });

await page.evaluate(() => window.scrollTo(0, 500));
await page.waitForTimeout(900);
console.log('LONG LIST SCROLLED:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/80-prod-v3-longlist-scrolled.png' });

await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(900);
const lb = await state();
console.log('LONG LIST BOTTOM:', JSON.stringify(lb), 'maxMatch:', lb.y === lb.scrollH - lb.innerH);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/81-prod-v3-longlist-bottom.png' });

const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1'));
console.log('DIAG tail:', (diag || '').slice(-400));
console.log('pageerrors:', JSON.stringify(errors));
await browser.close();
