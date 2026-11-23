// 验证 env 桥通道：带 #fakeinsets 打开本地 spike，
// 宿主页注入假安全区 (59,0,34,0)，面板应显示 env top=59 bottom=34，
// 且生效值随之变为 59/34（胶囊下移、底部标记增高 → 总高变化）。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:8097/#fakeinsets', { waitUntil: 'load' });
await page.waitForTimeout(16000);
const state = await page.evaluate(() => {
  const flt = document.querySelector('flt-scene-host, flutter-view');
  return {
    scrollH: document.documentElement.scrollHeight,
    hasView: !!document.querySelector('flutter-view'),
  };
});
console.log('state:', JSON.stringify(state));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/66-spike-fakeinsets.png' });
console.log('pageerrors:', JSON.stringify(errors));
await browser.close();
