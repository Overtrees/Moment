// A 路线 spike 验证：元素嵌入 + body 滚动
// 1) body 可滚动（scrollHeight > innerHeight）
// 2) window.scrollTo 后 Flutter 悬浮胶囊跟随（截图）
// 3) 滚到底部：底部标记渲染完整（超高画布未裁切）
// 4) 编辑器页：shrinkWrap 渲染 + 文末段落可见
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const OUT = process.env.OUT || '/home/hatch/workspace/mynote-shots-round6';
mkdirSync(OUT, { recursive: true });
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

await page.goto('http://localhost:8097/', { waitUntil: 'load' });
await page.waitForTimeout(12000);

const dims = await page.evaluate(() => ({
  scrollH: document.documentElement.scrollHeight,
  bodyH: document.body.scrollHeight,
  innerH: window.innerHeight,
  hostH: document.getElementById('host')?.style.height,
  scrollY: window.scrollY,
}));
console.log('dims:', JSON.stringify(dims));
await page.screenshot({ path: `${OUT}/50-spike-top.png` });

await page.evaluate(() => window.scrollTo(0, 3000));
await page.waitForTimeout(800);
console.log('scrollY after scrollTo 3000:', await page.evaluate(() => window.scrollY));
await page.screenshot({ path: `${OUT}/51-spike-scrolled.png` });

await page.evaluate(() => window.scrollTo(0, 1e9));
await page.waitForTimeout(800);
console.log('scrollY at bottom:', await page.evaluate(() => window.scrollY));
await page.screenshot({ path: `${OUT}/52-spike-bottom.png` });

// 回顶部，切编辑器页（按钮位置先靠截图 50 定位：编辑器按钮约 (140, 300) 附近，
// 用触摸点按；若未切换，diag 里看 scrollY 变化与截图人工核对）
await page.evaluate(() => window.scrollTo(0, 0));
await page.waitForTimeout(600);
await page.touchscreen.tap(140, 300);
await page.waitForTimeout(1500);
await page.screenshot({ path: `${OUT}/53-spike-editor.png` });
const dims2 = await page.evaluate(() => ({
  scrollH: document.documentElement.scrollHeight,
  hostH: document.getElementById('host')?.style.height,
}));
console.log('editor dims:', JSON.stringify(dims2));
await page.evaluate(() => window.scrollTo(0, 1e9));
await page.waitForTimeout(800);
await page.screenshot({ path: `${OUT}/54-spike-editor-bottom.png` });

console.log('pageerrors:', JSON.stringify(errors));
await browser.close();
