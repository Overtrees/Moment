import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round6';
import { mkdirSync } from 'fs';
mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
page.on('console', m => { if (m.type() === 'error') console.log('PAGE-ERR:', m.text().slice(0, 200)); });
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 300)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(9000);
await page.screenshot({ path: OUT + '/01-list.png' });
console.log('list shot done');
// 打开第一篇笔记（音乐笔记在 ~815 处为最近在听的歌；先点 320 处的装修踩坑清单）
await page.touchscreen.tap(210, 320);
await page.waitForTimeout(3500);
await page.screenshot({ path: OUT + '/02-editor.png' });
console.log('editor shot done');
// 读诊断日志
const diag = await page.evaluate(() => { try { return (localStorage.getItem('mynote_diag_v1') || '').slice(-1500); } catch (e) { return 'ERR ' + e; } });
console.log('DIAG-TAIL:', diag);
await browser.close();
