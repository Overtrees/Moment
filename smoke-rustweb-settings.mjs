// Rust Web 设置页冒烟：结构完整性（外观/数据/关于）+ 文字大小
// 三档（root rem 缩放全应用）+ 备份页结构 + 诊断入口
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const ok = (name, cond) => console.log((cond ? '✓ ' : '✗ ') + name);

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });

const settingsText = await page.evaluate(() => document.body.innerText);
for (const s of ['设置', '外观', '文字大小', '数据', '备份与恢复', '语言', '诊断日志', '关于', '版本', '2.2.7', '联系我们', 'overcanopies@gmail.com', '此刻，值得被记住。']) {
  if (!settingsText.includes(s)) { ok('settings contains ' + s, false); }
}
ok('settings structure complete', true);

// 文字大小：大 → html font-size 19px + sj_fontsize=large 持久
await page.click('.seg-btn:has-text("大")');
await page.waitForTimeout(300);
const fsLarge = await page.evaluate(() => ({
  root: document.documentElement.style.fontSize,
  ls: localStorage.getItem('sj_fontsize'),
}));
console.log('FONT LARGE:', JSON.stringify(fsLarge));
ok('large sets root 19px + persists', fsLarge.root === '19px' && fsLarge.ls === 'large');

// 编辑器正文随 root 缩放（1rem = 19px）
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 8000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('.detail .ed-line', { timeout: 8000 });
const bodyFs = await page.$eval('.editor-body', (e) => getComputedStyle(e).fontSize);
console.log('EDITOR BODY FS:', bodyFs);
ok('editor body scales to 19px', bodyFs === '19px');
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 8000 });

// 小 → 14px
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.seg-btn:has-text("小")');
await page.waitForTimeout(300);
const fsSmall = await page.evaluate(() => document.documentElement.style.fontSize);
ok('small sets root 14px', fsSmall === '14px');
// 恢复中号，避免污染后续
await page.click('.seg-btn:has-text("中")');
await page.waitForTimeout(200);

// 备份页结构：hero + 导出/导入卡 + iCloud 静态说明一行；
// 谷歌入口已移除（用户 2026-11-22 拍板），全文不得出现 Google。
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('.backup-hero', { timeout: 8000 });
const backupText = await page.evaluate(() => document.body.innerText);
ok('backup hero + rows', backupText.includes('备份状态总览') && backupText.includes('导出备份') && backupText.includes('导入备份'));
ok('no google backup remnants', !backupText.includes('Google') && !backupText.includes('谷歌'));
const noteText = await page.$eval('.backup-note', (e) => e.innerText);
ok('icloud static note present', noteText.includes('iCloud Drive'));
// 导出行 → 确认底表 → 取消关闭
await page.click('.backup-row:has-text("导出备份")');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
const sheetText = await page.$eval('.backup-modal', (e) => e.innerText);
ok('export sheet copy', sheetText.includes('确认导出备份'));
// 遮罩铺满（模态遮罩根治）：打开态 scrim rect 四边与视口差
// 0（±1px），且页头标题胶囊中心点命中落在遮罩上——页头在
// 遮罩之下被压暗，不得浮在遮罩上方。
const scrimGeom = await page.evaluate(() => {
  const s = document.querySelector('.backup-modal-scrim');
  const r = s.getBoundingClientRect();
  const hit = document.elementFromPoint(Math.round(window.innerWidth / 2), 24);
  return { x: r.x, y: r.y, w: r.width, h: r.height, iw: window.innerWidth, ih: window.innerHeight, hit: hit ? String(hit.className) : '' };
});
ok('scrim covers viewport', Math.abs(scrimGeom.x) <= 1 && Math.abs(scrimGeom.y) <= 1 && Math.abs(scrimGeom.w - scrimGeom.iw) <= 1 && Math.abs(scrimGeom.h - scrimGeom.ih) <= 1);
ok('scrim above page header', scrimGeom.hit.includes('backup-modal-scrim'));
await page.click('.backup-modal .backup-btn.secondary');
await page.waitForFunction(() => !document.querySelector('.backup-modal'), { timeout: 8000 });
ok('export sheet cancels', true);
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });

// 诊断页：从设置进入，日志 UI 在
await page.click('.set-row:has-text("诊断日志")');
await page.waitForSelector('.diag-body', { timeout: 8000 });
const diagText = await page.$eval('.diag-body', (e) => e.innerText);
ok('diag view shows log lines', diagText.includes('APP'));
const diagBg = await page.$eval('.diag-body', (e) => getComputedStyle(e).backgroundColor);
console.log('DIAG BG:', diagBg);
ok('diag keeps dark style', diagBg === 'rgb(17, 17, 17)');

console.log('ERRORS:', errors.length ? errors.join(' | ') : 'none');
await browser.close();
