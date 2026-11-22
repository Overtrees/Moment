// 原版侧实测：仅打标题的新备忘关闭后是否保留（规格验证）
// 用法: node probe_orig_close.mjs <origBase>
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8097/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
await page.goto(base + 'Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(3500);
const probe = await page.evaluate(() => ({
  items: [...document.querySelectorAll('.list-item')].map((e) => e.innerText.slice(0, 30).replace(/\n/g, '|')),
  hasTitleInput: !!document.querySelector('.editor-title-input'),
}));
console.log('list items:', JSON.stringify(probe.items.slice(0, 4)));
// 点新建笔记卡（列表首行）
const newCard = page.locator('.list-item', { hasText: '新建笔记' }).first();
await newCard.click();
await page.waitForTimeout(1500);
const inEditor = await page.evaluate(() => ({
  titleInput: !!document.querySelector('.editor-title-input'),
  body: !!document.querySelector('.editor-body'),
  fabs: [...document.querySelectorAll('.editor-fab')].length,
}));
console.log('editor state:', JSON.stringify(inEditor));
if (inEditor.titleInput || inEditor.body) {
  // 点标题输入并打字
  const t = page.locator('.editor-title-input').first();
  await t.click();
  await page.waitForTimeout(300);
  await page.keyboard.type('原版仅标题备忘');
  await page.waitForTimeout(800);
  const tv = await page.evaluate(() => document.querySelector('.editor-title-input')?.innerText || '');
  console.log('title after typing:', JSON.stringify(tv));
  // 返回（左上角返回钮）
  await page.click('.editor-fab.left');
  await page.waitForTimeout(1800);
  const after = await page.evaluate(() =>
    [...document.querySelectorAll('.list-item')].map((e) => e.innerText.slice(0, 30).replace(/\n/g, '|')));
  console.log('list after close:', JSON.stringify(after.slice(0, 5)));
  console.log('VERDICT kept:', after.some((s) => s.includes('原版仅标题备忘')) ? 'KEPT' : 'NOT FOUND');
}
await browser.close();
