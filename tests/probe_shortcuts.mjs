// 专用探针：桌面快捷键（批 12 P-U6）。桌面视口逐键验证：
//  / 聚焦搜索（输入框挂载且获焦，输入后 Esc 走输入自身
//    收起路径）；n 新建（打开编辑器）；j/k 行焦点移行
//    （activeElement 逐行走）；Esc 子页返回（设置→列表、
//    速览→设置）；输入守卫（搜索框内打 n 只进查询词、不
//    新建）。Diag 逐键留痕。
// 用法：node probe_shortcuts.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);
await page.evaluate(() => { document.activeElement && document.activeElement.blur(); });

const diagHas = async (substr, tries = 20) => {
  for (let i = 0; i < tries; i++) {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); } catch (e) { return []; }
    });
    if (lines.some((l) => String(l).includes(substr))) return true;
    await page.waitForTimeout(400);
  }
  return false;
};
const focusLabel = () => page.evaluate(() => {
  const el = document.activeElement;
  return el ? (el.getAttribute('aria-label') || el.className || el.tagName) : 'none';
});

// / 聚焦搜索
await page.keyboard.press('/');
await page.waitForSelector('.glass-search-input', { timeout: 8000 });
await page.waitForTimeout(400);
ok('/ 打开搜索', true);
ok('/ 输入框获焦', (await focusLabel()).includes('glass-search-input'), await focusLabel());
ok('Diag 记 shortcut /', await diagHas('shortcut / -> focus search'));
// 输入守卫：框内打 n 只进查询
await page.keyboard.type('n');
await page.waitForTimeout(500);
ok('守卫：框内 n 不新建（编辑器未开）', (await page.locator('.editor-stage').count()) === 0);
ok('守卫：n 进了查询词', (await page.locator('.glass-search-input').inputValue()) === 'n');
// Esc（输入自身路径）收起
await page.keyboard.press('Escape');
await page.waitForTimeout(600);
ok('Esc 收起搜索（输入路径）', (await page.locator('.glass-search-input').count()) === 0);

// j/k 移行
await page.evaluate(() => { document.activeElement && document.activeElement.blur(); });
await page.keyboard.press('j');
await page.waitForTimeout(400);
const f1 = await focusLabel();
ok('j 焦点落首行（新建卡）', f1.includes('新建笔记'), f1);
await page.keyboard.press('j');
await page.waitForTimeout(400);
const f2 = await focusLabel();
ok('j 焦点移到下一行', !f2.includes('新建笔记') && f2.includes('按回车或空格打开'), f2);
await page.keyboard.press('k');
await page.waitForTimeout(400);
ok('k 焦点移回上一行', (await focusLabel()).includes('新建笔记'));
ok('Diag 记 shortcut j', await diagHas('shortcut j -> row focus'));

// n 新建
await page.keyboard.press('n');
await page.waitForSelector('.editor-stage', { timeout: 10000 });
await page.waitForTimeout(600);
ok('n 打开编辑器（新建）', true);
ok('Diag 记 shortcut n', await diagHas('shortcut n -> new memo'));
await page.click('.editor-fab.left');
await page.waitForTimeout(1000);
ok('返回列表', (await page.locator('.glass-search-trigger').count()) >= 1);

// Esc 子页返回
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.backup-card', { timeout: 10000 });
await page.waitForTimeout(600);
await page.locator('.set-row', { hasText: '手势速览' }).first().click();
await page.waitForTimeout(900);
ok('已进速览页', (await page.locator('.gesture-row').count()) === 5);
ok('速览页含快捷键说明行', (await page.locator('.settings-footer').innerText()).includes('桌面快捷键'));
await page.keyboard.press('Escape');
await page.waitForTimeout(900);
ok('Esc 速览→设置', (await page.locator('.set-row', { hasText: '手势速览' }).count()) === 1);
await page.keyboard.press('Escape');
await page.waitForTimeout(900);
ok('Esc 设置→列表', (await page.locator('.glass-search-trigger').count()) >= 1);
ok('Diag 记 shortcut esc', await diagHas('shortcut esc -> back'));

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
