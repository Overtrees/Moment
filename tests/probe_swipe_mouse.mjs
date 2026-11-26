// 专用探针：桌面鼠标左滑列表文本行（尾随 click 不得收起动作层）。
// 缺陷（批 12 分诊发现）：文本卡 onclick 原序先判开启态收起、
// 后判手势 moved——桌面鼠标拖拽左滑时 pointerup 已把 off 落定
// -168，尾随 click（鼠标路径无触摸的 click 抑制、必然派发）命中
// 收起分支，动作层刚开即收、删除/置顶钮 pointer-events 回 none
// 不可点。触摸路径无此问题（尾随 click 被抑制），故既有左滑
// 探针（probe_delete_undo）全走 CDP 触摸串、测不出本病；本探
// 针全程 page.mouse 真实鼠标序列守桌面口径：
//  ① 鼠标左滑 → 动作层保持开启（transform -168、两钮
//     pointer-events=auto）；
//  ② 点置顶钮 → 置顶态翻转（.pin-dot 出现/消失、Diag row
//     pin tap）、动作层随动作收起；再左滑点置顶 → 翻转回来；
//  ③ 鼠标左滑 → 点删除钮 → 软删 toast 出现、行消失；撤销恢复；
//  ④ 普通点按（无位移）点行 → 打开备忘进编辑器；返回列表；
//  ⑤ 左滑开启态下普通点按行 → 只收起动作层、不打开备忘
//     （开启态收起语义不回归）。
// 用法：node probe_swipe_mouse.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

// 桌面口径：宽视口、无触摸
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGE_ERROR', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(1200);

const diagHas = async (substr, tries = 16) => {
  for (let i = 0; i < tries; i++) {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); } catch (e) { return []; }
    });
    if (lines.some((l) => String(l).includes(substr))) return true;
    await page.waitForTimeout(400);
  }
  return false;
};

// 目标：首个非新建的文本行（.list-item），按标题重定位
const firstRow = page.locator('.swipe-wrapper:not(:has(.new-card-title))', { has: page.locator('.list-item') }).first();
const title = await firstRow.locator('.item-title-text').innerText();
L('目标文本行 =', title);
const row = () => page.locator('.swipe-wrapper:not(:has(.new-card-title))', { has: page.locator('.list-item') })
  .filter({ hasText: title }).first();
const card = () => row().locator('.list-item').first();
const txOf = async () => card().evaluate((el) => {
  const m = /matrix\(1, 0, 0, 1, (-?[\d.]+),/.exec(getComputedStyle(el).transform || '');
  return m ? parseFloat(m[1]) : null;
});

// 鼠标左滑：按下 → 步进左移 → 抬起（尾随 click 由浏览器派发）
const mouseSwipeLeft = async () => {
  const box = await card().boundingBox();
  const cy = box.y + box.height / 2;
  const sx = box.x + box.width - 40;
  await page.mouse.move(sx, cy);
  await page.mouse.down();
  for (let dx = -20; dx >= -170; dx -= 15) {
    await page.mouse.move(sx + dx, cy);
    await page.waitForTimeout(30);
  }
  await page.mouse.up();
  await page.waitForTimeout(700);
};
// 普通点按：同点按下抬起、无位移。落点取卡片在 wrapper
// 内的可见左部（开启态下卡片左移 168、几何中心已出
// wrapper，中心点会点空）
const mouseTap = async () => {
  const box = await card().boundingBox();
  const wbox = await row().boundingBox();
  await page.mouse.click(Math.max(box.x, wbox.x) + 40, box.y + box.height / 2);
  await page.waitForTimeout(700);
};

// ① 鼠标左滑 → 动作层保持
await mouseSwipeLeft();
ok('① 左滑后动作层保持开启（tx=-168）', (await txOf()) === -168, `tx=${await txOf()}`);
ok('① 删除钮可点（pointer-events=auto）',
   (await row().locator('.act-del').evaluate((el) => getComputedStyle(el).pointerEvents)) === 'auto');
ok('① 置顶钮可点（pointer-events=auto）',
   (await row().locator('.act-pin').evaluate((el) => getComputedStyle(el).pointerEvents)) === 'auto');

// ② 点置顶钮 → 置顶态翻转 + 收起；再滑再点 → 翻转回来
// （种子行初始置顶态不定，断言取「点击前后翻转」不预设方向）
const pinDots = async () => row().locator('.pin-dot').count();
const pinBefore = await pinDots();
await row().locator('.act-pin').click();
await page.waitForTimeout(800);
ok('② 点置顶钮后置顶态翻转', (await pinDots()) === (pinBefore === 1 ? 0 : 1),
   `before=${pinBefore} after=${await pinDots()}`);
ok('② Diag 记 row pin tap', await diagHas('row pin tap'));
ok('② 动作后动作层收起（tx=0）', (await txOf()) === 0, `tx=${await txOf()}`);
await mouseSwipeLeft();
ok('② 再左滑仍保持开启', (await txOf()) === -168, `tx=${await txOf()}`);
await row().locator('.act-pin').click();
await page.waitForTimeout(800);
ok('② 再点置顶钮翻转回初始态', (await pinDots()) === pinBefore,
   `before=${pinBefore} after=${await pinDots()}`);

// ③ 鼠标左滑 → 删除 → 撤销恢复
await mouseSwipeLeft();
ok('③ 左滑后动作层保持开启', (await txOf()) === -168, `tx=${await txOf()}`);
await row().locator('.act-del').click();
await page.waitForTimeout(800);
ok('③ 软删 toast 出现', (await page.locator('.backup-toast.has-action').count()) === 1);
ok('③ 删除后行消失', (await row().count()) === 0);
ok('③ Diag 记 row delete tap', await diagHas('row delete tap'));
await page.locator('.backup-toast.has-action .undo-toast-btn').click();
await page.waitForTimeout(800);
ok('③ 撤销后行恢复', (await row().count()) === 1);

// ④ 普通点按打开备忘
await mouseTap();
await page.waitForSelector('#editor-root', { timeout: 15000 });
ok('④ 普通点按打开备忘（编辑器在场）', true);
await page.click('.editor-fab.left');
await page.waitForSelector('.page-current .list-item', { timeout: 15000 });
await page.waitForTimeout(1200);
ok('④ 返回列表', (await row().count()) === 1);

// ⑤ 开启态普通点按只收起
await mouseSwipeLeft();
ok('⑤ 左滑后动作层保持开启', (await txOf()) === -168, `tx=${await txOf()}`);
await mouseTap();
ok('⑤ 开启态点按收起动作层（tx=0）', (await txOf()) === 0, `tx=${await txOf()}`);
ok('⑤ 未打开备忘（仍在列表）', (await page.locator('#editor-root').count()) === 0
   && (await row().count()) === 1);

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
