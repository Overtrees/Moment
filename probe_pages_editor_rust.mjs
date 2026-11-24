// 编辑页外壳审计探针（Rust 版 8100）：fabs/标题坞/•••菜单/导出面板/
// BgSheet/附件入口/头像/图片页/图文面板/链接表单。只读审计，不改应用。
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const BASE = 'http://localhost:8100/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
// 1x1 PNG + 文本附件
fs.writeFileSync('/tmp/avatar_test.png', Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64'));
fs.writeFileSync('/tmp/att_test.txt', 'hello attachment\n');

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const R = (name, val) => console.log(name + ' :: ' + (typeof val === 'string' ? val : JSON.stringify(val)));
// 坐标点按开备忘：现行列表打开走真实指针手势链，合成 el.click() 不触发（与在册探针同口径）；
// 等卡片在场并待进场动画落定后量坐标，避免量到动画中间位。
const tapMemo = async (title) => {
  await page.waitForFunction((t) => [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].some((e) => e.textContent.includes(t)), title, { timeout: 10000 }).catch(() => {});
  const pt = await page.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes(t));
    if (!el) return null;
    el.scrollIntoView({ block: 'center' });
    return true;
  }, title);
  if (!pt) return;
  await page.waitForTimeout(450);
  const pt2 = await page.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes(t));
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, title);
  if (pt2) await page.touchscreen.tap(pt2.x, pt2.y);
};

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });

// 导入 real_backup
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('#file-import', { state: 'detached', timeout: 8000 }).catch(() => {});
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item:not(.set-row), .img-card', { timeout: 10000 });

// 打开「冬日」（图片卡）
await tapMemo('冬日');
await page.waitForSelector('#editor-root', { timeout: 10000 });
await page.waitForTimeout(900);

// ---- fabs + dock 度量 ----
R('FABS_DOCK', await page.evaluate(() => {
  const g = (sel) => { const el = document.querySelector(sel); if (!el) return null; const r = el.getBoundingClientRect(); const cs = getComputedStyle(el); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), fs: cs.fontSize }; };
  const meta = document.querySelector('.editor-title-meta');
  const titleEl = document.querySelector('.editor-title-input, #editor-title-text');
  return {
    fabL: g('.editor-fab.left'), fabR: g('.editor-fab.right'),
    dock: g('.editor-title-dock'), avatar: g('.editor-avatar-button'),
    capsule: g('.editor-title-capsule'),
    titleText: titleEl ? titleEl.textContent : null,
    titleFs: titleEl ? getComputedStyle(titleEl).fontSize : null,
    meta: meta ? { text: meta.textContent, disp: getComputedStyle(meta).display } : null,
    avatarHasImg: !!document.querySelector('.editor-avatar-button img'),
    avatarHasDino: !!document.querySelector('.editor-avatar-button svg'),
  };
}));

// ---- 头像换图 ----
await page.setInputFiles('#file-avatar', '/tmp/avatar_test.png');
await page.waitForTimeout(900);
R('AVATAR_AFTER_SET', await page.evaluate(() => !!document.querySelector('.editor-avatar-button img')));
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
await tapMemo('冬日');
await page.waitForSelector('#editor-root', { timeout: 10000 });
await page.waitForTimeout(700);
R('AVATAR_PERSIST_AFTER_REOPEN', await page.evaluate(() => !!document.querySelector('.editor-avatar-button img')));

// ---- 图片页：点正文图片（2026-11-24 浮层灯箱退役、改独立页面后改口径） ----
const imgCount = await page.evaluate(() => document.querySelectorAll('#editor-root .atomic[data-type="image"] img, #editor-root .editor-body img').length);
R('BODY_IMGS', imgCount);
if (imgCount > 0) {
  await page.evaluate(() => {
    const img = document.querySelector('#editor-root .atomic[data-type="image"] img') || document.querySelector('#editor-root .editor-body img');
    const r = img.getBoundingClientRect();
    img.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 }));
    img.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 }));
    img.click();
  });
  await page.waitForSelector('.img-page', { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(700);
  R('IMGPAGE', await page.evaluate(() => {
    const pg = document.querySelector('.img-page');
    if (!pg) return { open: false };
    const img = pg.querySelector('.img-page-img') || pg.querySelector('img');
    const r = img ? img.getBoundingClientRect() : null;
    return {
      open: true,
      title: pg.querySelector('.page-title')?.textContent.trim() || '',
      imgOk: !!img,
      nat: img ? img.naturalWidth + 'x' + img.naturalHeight : null,
      rendered: r ? Math.round(r.width) + 'x' + Math.round(r.height) : null,
      rootBg: getComputedStyle(document.documentElement).backgroundColor,
    };
  }));
  // 页内返回钮回编辑页
  await page.click('.img-page .editor-fab.left');
  await page.waitForSelector('.detail', { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(400);
  R('IMGPAGE_BACK_TO_EDITOR', await page.evaluate(() => !document.querySelector('.img-page') && !!document.querySelector('#editor-root')));
}

// ---- ••• 菜单 ----
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(400);
R('MENU', await page.evaluate(() => {
  const p = document.querySelector('.editor-menu-panel');
  const r = p.getBoundingClientRect();
  const items = [...p.querySelectorAll('.menu-item')].map((b) => ({
    text: b.innerText.replace(/\n/g, '|'),
    cls: b.className, disabled: b.disabled === true,
    op: getComputedStyle(b).opacity,
    chevron: !!b.querySelector('.menu-chevron'),
  }));
  return { w: Math.round(r.width), x: Math.round(r.x), y: Math.round(r.y), items };
}));

// scrim 关闭
await page.mouse.click(30, 700);
await page.waitForTimeout(400);
R('MENU_SCRIM_CLOSE', await page.evaluate(() => !document.querySelector('.editor-menu-panel')));

// ---- 撤销/重做：先制造一次编辑 ----
await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); if (el) el.focus(); });
await page.keyboard.type('Z');
await page.waitForTimeout(500);
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
R('MENU_UNDO_STATE', await page.evaluate(() => {
  const items = [...document.querySelectorAll('.editor-menu-panel .menu-item')];
  return items.map((b) => ({ t: b.innerText.split('\n')[0], disabled: b.disabled === true, cls: b.className }));
}));
// 点撤销
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('撤销'));
  if (b) b.click();
});
await page.waitForTimeout(600);
R('AFTER_UNDO', await page.evaluate(() => ({
  menuGone: !document.querySelector('.editor-menu-panel'),
  firstBlock: document.querySelector('#editor-root [data-bid]')?.textContent || '',
})));
// 重做应可用且恢复 Z
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('重做'));
  if (b) b.click();
});
await page.waitForTimeout(600);
R('AFTER_REDO_FIRSTBLOCK_HAS_Z', await page.evaluate(() =>
  (document.querySelector('#editor-root [data-bid]')?.textContent || '').includes('Z')));
// 撤销掉 Z 恢复原状
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('撤销'));
  if (b) b.click();
});
await page.waitForTimeout(500);

// ---- 双栏开关 ----
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('.twopane-row')?.click());
await page.waitForTimeout(400);
R('TWOPANE_ON', await page.evaluate(() => ({
  ls: localStorage.getItem('sj_editor_independent_scroll'),
  sw: document.querySelector('.twopane-row .switch')?.className || '',
  menuStillOpen: !!document.querySelector('.editor-menu-panel'),
})));
await page.evaluate(() => document.querySelector('.twopane-row')?.click());
await page.waitForTimeout(400);
R('TWOPANE_OFF', await page.evaluate(() => ({
  ls: localStorage.getItem('sj_editor_independent_scroll'),
  sw: document.querySelector('.twopane-row .switch')?.className || '',
})));
await page.mouse.click(30, 700);
await page.waitForTimeout(300);

// ---- 导出面板 ----
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('导出'));
  if (b) b.click();
});
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
await page.waitForTimeout(400);
R('EXPORT_PANEL', await page.evaluate(() => {
  const p = document.querySelector('.editor-export-panel');
  const r = p.getBoundingClientRect();
  const back = p.querySelector('.export-back');
  const br = back ? back.getBoundingClientRect() : null;
  return {
    w: Math.round(r.width), text: p.innerText.replace(/\n/g, '|'),
    backSize: br ? Math.round(br.width) + 'x' + Math.round(br.height) : null,
    choices: [...p.querySelectorAll('.editor-export-choice')].map((c) => c.innerText.replace(/\n/g, '|')),
  };
}));
// 返回菜单
await page.click('.editor-export-panel .export-back');
await page.waitForTimeout(400);
R('EXPORT_BACK_TO_MENU', await page.evaluate(() => !!document.querySelector('.editor-menu-panel') && !document.querySelector('.editor-export-panel')));
// 再次进导出 → MD 下载
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('导出'));
  if (b) b.click();
});
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
const dlMd = page.waitForEvent('download', { timeout: 10000 }).catch(() => null);
await page.evaluate(() => document.querySelectorAll('.editor-export-choice')[0]?.click());
const dMd = await dlMd;
R('EXPORT_MD_DOWNLOAD', dMd ? dMd.suggestedFilename() : 'NONE');
await page.waitForTimeout(600);
R('EXPORT_MD_AFTER', await page.evaluate(() => ({
  panelGone: !document.querySelector('.editor-export-panel'),
  toast: document.querySelector('.status-toast')?.innerText || '',
})));
// HTML 下载
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('导出'));
  if (b) b.click();
});
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
const dlHtml = page.waitForEvent('download', { timeout: 10000 }).catch(() => null);
await page.evaluate(() => document.querySelectorAll('.editor-export-choice')[1]?.click());
const dHtml = await dlHtml;
R('EXPORT_HTML_DOWNLOAD', dHtml ? dHtml.suggestedFilename() : 'NONE');
await page.waitForTimeout(500);
// PDF → 打印窗口（popup）
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('导出'));
  if (b) b.click();
});
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
const popupP = ctx.waitForEvent('page', { timeout: 6000 }).catch(() => null);
await page.evaluate(() => document.querySelectorAll('.editor-export-choice')[2]?.click());
const popup = await popupP;
R('EXPORT_PDF_POPUP', popup ? popup.url().slice(0, 30) : 'NONE');
if (popup) await popup.close().catch(() => {});
await page.waitForTimeout(400);
await page.evaluate(() => document.querySelector('.menu-scrim')?.dispatchEvent(new MouseEvent('click', { bubbles: true })));
await page.waitForTimeout(300);

// ---- 附件入口 ----
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
const fcP = page.waitForEvent('filechooser', { timeout: 8000 }).catch(() => null);
await page.evaluate(() => {
  const l = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('附件'));
  if (l) l.click();
});
const fc = await fcP;
R('ATTACH_CHOOSER', fc ? { multiple: fc.isMultiple() } : 'NONE');
R('ATTACH_INPUT_ATTRS', await page.evaluate(() => {
  const i = document.querySelector('#file-attach');
  return i ? { accept: i.getAttribute('accept'), multiple: i.multiple } : null;
}));
if (fc) {
  await fc.setFiles('/tmp/att_test.txt');
  await page.waitForTimeout(1200);
}
R('ATTACH_AFTER', await page.evaluate(() => ({
  menuGone: !document.querySelector('.editor-menu-panel'),
  attRow: !!document.querySelector('#editor-root .attachment-file'),
  attText: document.querySelector('#editor-root .attachment-file')?.innerText?.replace(/\n/g, '|') || '',
})));
// 点附件行 → 打开（blob URL 新页或无反应）
const pop2P = ctx.waitForEvent('page', { timeout: 4000 }).catch(() => null);
await page.evaluate(() => {
  const el = document.querySelector('#editor-root .attachment-file');
  if (el) { const r = el.getBoundingClientRect(); el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 })); el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 })); el.click(); }
});
const pop2 = await pop2P;
R('ATTACH_OPEN_POPUP', pop2 ? pop2.url().slice(0, 30) : 'NONE');
if (pop2) await pop2.close().catch(() => {});

// ---- BgSheet ----
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('背景'));
  if (b) b.click();
});
await page.waitForSelector('.bg-sheet', { timeout: 8000 });
await page.waitForTimeout(500);
R('BGSHEET', await page.evaluate(() => {
  const dots = [...document.querySelectorAll('.bg-dot')];
  const first = dots[0]?.getBoundingClientRect(); const second = dots[1]?.getBoundingClientRect(); const fifth = dots[4]?.getBoundingClientRect();
  return {
    title: document.querySelector('.bg-title')?.textContent || '',
    sub: document.querySelector('.bg-sub')?.textContent || '',
    n: dots.length,
    dotSize: first ? Math.round(first.width) + 'x' + Math.round(first.height) : null,
    rowGapX: first && second ? Math.round(second.x - first.x) : null,
    secondRowDy: first && fifth ? Math.round(fifth.y - first.y) : null,
    colors: dots.map((d) => d.style.background || getComputedStyle(d).backgroundColor),
    removeVisible: !!document.querySelector('.bg-remove'),
  };
}));
// 选第 2 色
const dotColor = await page.evaluate(() => document.querySelectorAll('.bg-dot')[1]?.style.background || '');
await page.evaluate(() => document.querySelectorAll('.bg-dot')[1]?.click());
await page.waitForTimeout(600);
R('BG_AFTER_SELECT', await page.evaluate(() => ({
  sheetGone: !document.querySelector('.bg-sheet'),
  rootBg: document.querySelector('#editor-root')?.style.background || '',
  want: '',
})));
R('BG_DOT_COLOR_WAS', dotColor);
// 重开 → sel 标记 + 移除行 → 移除
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('背景'));
  if (b) b.click();
});
await page.waitForSelector('.bg-sheet', { timeout: 8000 });
await page.waitForTimeout(400);
R('BGSHEET_REOPEN', await page.evaluate(() => ({
  selIdx: [...document.querySelectorAll('.bg-dot')].findIndex((d) => d.className.includes('sel')),
  removeVisible: !!document.querySelector('.bg-remove'),
  removeText: document.querySelector('.bg-remove')?.innerText?.replace(/\n/g, '|') || '',
})));
await page.evaluate(() => document.querySelector('.bg-remove')?.click());
await page.waitForTimeout(600);
R('BG_AFTER_REMOVE', await page.evaluate(() => ({
  sheetGone: !document.querySelector('.bg-sheet'),
  rootBg: document.querySelector('#editor-root')?.style.background || '',
})));
// scrim 关 BgSheet
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel .menu-item')].find((x) => x.innerText.includes('背景'));
  if (b) b.click();
});
await page.waitForSelector('.bg-sheet', { timeout: 8000 });
await page.evaluate(() => document.querySelector('.sheet-scrim')?.dispatchEvent(new MouseEvent('click', { bubbles: true })));
await page.waitForTimeout(400);
R('BGSHEET_SCRIM_CLOSE', await page.evaluate(() => !document.querySelector('.bg-sheet')));

R('PAGE_ERRORS', errors);
await browser.close();
console.log('DONE');
