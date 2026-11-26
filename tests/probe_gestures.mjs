// 专用探针：手势可发现性（批 12 P-U1）。
//  ① 种子「使用指南」备忘在列表可见，打开后正文含左滑/
//     长按/斜杠/双栏各节标题；
//  ② 编辑器首次提示：首次打开编辑器时 .gesture-hint 在场，
//     点「知道了」消失 + localStorage 标记落盘 + Diag 记
//     dismissed；再次打开编辑器不再出现；
//  ③ 设置页手势速览入口：设置页有「手势速览」行，点入
//     速览页含 5 行手势说明，返回回设置页。
// 用法：node probe_gestures.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);

const diagHas = async (substr, tries = 20) => {
  for (let i = 0; i < tries; i++) {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
    });
    if (lines.some((l) => String(l).includes(substr))) return true;
    await page.waitForTimeout(500);
  }
  return false;
};

// ① 使用指南种子
const guideRow = page.locator('.swipe-wrapper', { hasText: '使用指南' });
ok('① 使用指南在列表可见', (await guideRow.count()) >= 1);
await guideRow.first().locator('.item-title-text').click();
await page.waitForSelector('.editor-stage', { timeout: 10000 });
await page.waitForTimeout(1000);
const bodyText = await page.locator('.detail').innerText();
for (const sec of ['左滑一行', '长按拖拽排序', '斜杠插入', '双栏', '搜索与备份']) {
  ok(`① 指南含「${sec}」节`, bodyText.includes(sec));
}
ok('① 指南含可试手势的待办行', bodyText.includes('试一试：长按这行'));

// ② 编辑器首次提示（首次打开编辑器即本次）
const hint = page.locator('.gesture-hint');
ok('② 首次提示在场', (await hint.count()) === 1);
ok('② 提示文案含长按与斜杠', (await hint.innerText()).includes('长按块可拖拽排序'));
await hint.locator('button').click();
await page.waitForTimeout(500);
ok('② 点知道后消失', (await page.locator('.gesture-hint').count()) === 0);
ok('② 一次性标记落盘', await page.evaluate(() => localStorage.getItem('mynote_hint_editor_v1') === '1'));
ok('② Diag 记 dismissed', await diagHas('editor gesture hint dismissed'));
await page.click('.editor-fab.left');
await page.waitForTimeout(1000);
await page.locator('.swipe-wrapper', { hasText: '周末看展记录' }).first().locator('.item-title-text').click();
await page.waitForSelector('.editor-stage', { timeout: 10000 });
await page.waitForTimeout(800);
ok('② 再次打开不再提示', (await page.locator('.gesture-hint').count()) === 0);
await page.click('.editor-fab.left');
await page.waitForTimeout(1000);

// ③ 设置页手势速览
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.backup-card', { timeout: 10000 });
await page.waitForTimeout(600);
const grow = page.locator('.set-row', { hasText: '手势速览' });
ok('③ 设置页有手势速览行', (await grow.count()) === 1);
await grow.first().click();
await page.waitForTimeout(900);
ok('③ 速览页 5 行', (await page.locator('.gesture-row').count()) === 5);
const gtext = await page.locator('.backup-card').innerText();
for (const n of ['左滑列表行', '长按拖拽', '斜杠命令', '双栏编辑', '快速搜索']) {
  ok(`③ 速览含「${n}」`, gtext.includes(n));
}
ok('③ Diag 记 gestures enter', await diagHas('gestures enter slideIn'));
await page.click('.editor-fab.left');
await page.waitForTimeout(900);
ok('③ 返回回设置页', (await page.locator('.set-row', { hasText: '手势速览' }).count()) === 1);

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
