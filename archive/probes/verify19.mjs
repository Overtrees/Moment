// 启动冒烟：新构建必须真正进到列表，不能死在加载屏
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(14000);
const state = await page.evaluate(() => {
  const splash = document.getElementById('app-loading');
  const splashVisible = !!splash && splash.offsetParent !== null && getComputedStyle(splash).display !== 'none';
  return {
    splashVisible,
    bodyChildren: [...document.body.children].map(e => e.tagName + (e.id ? '#' + e.id : '')),
    diag: (() => { try { return (localStorage.getItem('mynote_diag_v1') || '').slice(0, 600); } catch { return 'n/a'; } })(),
  };
});
console.log(JSON.stringify(state, null, 1));
console.log('pageerrors:', errors.slice(0, 3));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/48-boot-smoke.png' });
await browser.close();
