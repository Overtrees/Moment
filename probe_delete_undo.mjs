// 专用探针：列表删除软删 + 撤销窗口（批 12 U3）。
// 删除 = 打 deletedAt 标记（落盘）+ 8 秒撤销窗口：
//  ① 左滑删除一篇 → 行消失、撤销 toast 出现（文案 + 撤销
//     按钮）、Diag 记 (swipe, undo window)；
//  ② 点撤销 → 行恢复、Diag 记 undone；
//  ③ 再删 → 等窗口过期（>8s）：toast 消失、Diag 记
//     (undo window expired)；重载后该篇仍不存在（真删落盘）；
//  ④ 窗口内重载（杀进程等价）：删另一篇后立即重载 → 行仍
//     隐藏、toast 再水化恢复、Diag 记 rehydrated；点撤销
//     可恢复。
// 用法：node probe_delete_undo.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
const cdp = await ctx.newCDPSession(page);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(1000);

const diagHas = async (substr, tries = 24) => {
  for (let i = 0; i < tries; i++) {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
    });
    if (lines.some((l) => String(l).includes(substr))) return true;
    await page.waitForTimeout(500);
  }
  return false;
};
const rowByTitle = (title) => page.locator('.swipe-wrapper', { hasText: title });
// 左滑走 CDP 真实触摸串（pointer→touch→兼容回声全程）：
// 合成鼠标拖拽的尾随 click 会把刚打开的动作层收起（鼠标
// 无 touchmove preventDefault 等价物），不代表触摸口径。
const swipeDelete = async (title) => {
  const row = rowByTitle(title).first();
  const card = row.locator('.list-item, .img-card').first();
  const box = await card.boundingBox();
  const cy = box.y + box.height / 2;
  const sx = box.x + box.width - 40;
  await touch('touchStart', sx, cy);
  for (let dx = -20; dx >= -150; dx -= 15) {
    await touch('touchMove', sx + dx, cy);
    await page.waitForTimeout(30);
  }
  await touch('touchEnd', sx - 150, cy);
  await page.waitForTimeout(500);
  await row.locator('.act-del').click();
  await page.waitForTimeout(600);
};

// ① 删除 → toast
await swipeDelete('装修踩坑清单');
ok('① 删除后行消失', (await rowByTitle('装修踩坑清单').count()) === 0);
const toast = page.locator('.backup-toast.has-action');
ok('① 撤销 toast 出现', (await toast.count()) === 1);
ok('① toast 文案', (await toast.innerText()).includes('备忘已删除'));
ok('① Diag 记软删', await diagHas('(swipe, undo window)'));

// ② 撤销恢复
await toast.locator('.undo-toast-btn').click();
await page.waitForTimeout(600);
ok('② 撤销后行恢复', (await rowByTitle('装修踩坑清单').count()) === 1);
ok('② toast 消失', (await page.locator('.backup-toast.has-action').count()) === 0);
ok('② Diag 记 undone', await diagHas('undone'));

// ③ 再删 → 窗口过期真删
await swipeDelete('装修踩坑清单');
ok('③ 再删后行消失', (await rowByTitle('装修踩坑清单').count()) === 0);
ok('③ Diag 记过期真删', await diagHas('(undo window expired)', 30));
await page.waitForTimeout(500);
ok('③ 过期后 toast 消失', (await page.locator('.backup-toast.has-action').count()) === 0);
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(1000);
ok('③ 重载后仍不存在（真删落盘）', (await rowByTitle('装修踩坑清单').count()) === 0);

// ④ 窗口内重载再水化
await swipeDelete('周末看展记录');
ok('④ 删除后行消失', (await rowByTitle('周末看展记录').count()) === 0);
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(1200);
ok('④ 重载后行仍隐藏', (await rowByTitle('周末看展记录').count()) === 0);
ok('④ toast 再水化', (await page.locator('.backup-toast.has-action').count()) === 1);
ok('④ Diag 记 rehydrated', await diagHas('rehydrated'));
await page.locator('.backup-toast.has-action .undo-toast-btn').click();
await page.waitForTimeout(600);
ok('④ 再水化后撤销恢复', (await rowByTitle('周末看展记录').count()) === 1);

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
