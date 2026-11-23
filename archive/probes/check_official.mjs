// 官方方案迁移后抽查：新外壳标记、内部滚动签名、打开编辑器输入、返回列表
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const url = process.argv[2] || 'http://localhost:8095/';
const shotDir = process.env.HOME + '/workspace/mynote-shots-official';
import { mkdirSync } from 'fs';
mkdirSync(shotDir, { recursive: true });
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(13000);
const boot = await page.evaluate(() => ({
  splash: !!document.getElementById('app-loading'),
  flutterView: !!document.querySelector('flutter-view'),
  hasHost: !!document.getElementById('host'),
  hasRoot: !!document.getElementById('root'),
  viewportMeta: document.querySelector('meta[name="viewport"]')?.content || '',
  docScrollH: document.documentElement.scrollHeight,
  innerH: window.innerHeight,
  winScrollY: window.scrollY,
}));
console.log('boot:', JSON.stringify(boot));
await page.screenshot({ path: shotDir + '/01-list.png' });
// 点第一张备忘卡（置顶卡中心）打开编辑器
await page.touchscreen.tap(210, 350);
await page.waitForTimeout(3000);
await page.screenshot({ path: shotDir + '/02-after-tap.png' });
const afterTap = await page.evaluate(() => ({ y: window.scrollY, docScrollH: document.documentElement.scrollHeight }));
console.log('afterTap:', JSON.stringify(afterTap));
// 若进了编辑器，点正文区并输入
await page.touchscreen.tap(210, 320);
await page.waitForTimeout(800);
await page.keyboard.type('official migration check 123');
await page.waitForTimeout(1200);
await page.screenshot({ path: shotDir + '/03-typed.png' });
// 返回（左上角返回键区域）
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(2500);
await page.screenshot({ path: shotDir + '/04-back.png' });
const diag = await page.evaluate(() => { try { return localStorage.getItem('mynote_diag_v1') || ''; } catch { return 'n/a'; } });
console.log('diag has session start:', diag.includes('session start'));
console.log('diag has scroll model official:', diag.includes('scroll model: official'));
console.log('pageerrors:', JSON.stringify(errors.slice(0, 5)));
await browser.close();
