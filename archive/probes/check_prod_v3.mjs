// 生产 v3 验证：列表 body 同步（滚动+页眉收缩+底相等）、编辑器
// shrinkWrap 平移（滚动+坞收缩+文末）、返回后占位高恢复。
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
  hostH: document.getElementById('host')?.getBoundingClientRect().height,
}));
console.log('LIST TOP:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/69-prod-v3-list-top.png' });

await page.evaluate(() => window.scrollTo(0, 500));
await page.waitForTimeout(800);
console.log('LIST SCROLLED 500:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/70-prod-v3-list-scrolled.png' });

await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(800);
const bot = await state();
console.log('LIST BOTTOM:', JSON.stringify(bot), 'maxMatch:', bot.y === bot.scrollH - bot.innerH);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/71-prod-v3-list-bottom.png' });

// 回顶并点开第一张卡（演示数据）
await page.evaluate(() => window.scrollTo(0, 0));
await page.waitForTimeout(600);
await page.touchscreen.tap(210, 345);
await page.waitForTimeout(3500);
console.log('EDITOR TOP:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/72-prod-v3-editor-top.png' });

await page.evaluate(() => window.scrollTo(0, 1200));
await page.waitForTimeout(800);
console.log('EDITOR SCROLLED 1200:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/73-prod-v3-editor-scrolled.png' });

await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(800);
const ebot = await state();
console.log('EDITOR BOTTOM:', JSON.stringify(ebot), 'maxMatch:', ebot.y === ebot.scrollH - ebot.innerH);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/74-prod-v3-editor-bottom.png' });

// 返回列表：占位高应恢复为列表行程
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(2500);
console.log('BACK TO LIST:', JSON.stringify(await state()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/75-prod-v3-back-list.png' });

const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1'));
console.log('DIAG tail:', (diag || '').slice(-600));
console.log('pageerrors:', JSON.stringify(errors));
await browser.close();
