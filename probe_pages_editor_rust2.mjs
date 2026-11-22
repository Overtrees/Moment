// 编辑页外壳审计探针 2（Rust）：长标题截断/滚动态/链接表单/图文面板/媒体入口。
import { chromium } from 'playwright-core';

const BASE = 'http://localhost:8100/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR ::', String(e).slice(0, 160)));
const R = (name, val) => console.log(name + ' :: ' + (typeof val === 'string' ? val : JSON.stringify(val)));

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', process.env.HOME + '/workspace/Mynote/fixtures/allblocks.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });

// 打开全块渲染测试（长内容，含图文卡）
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes('全块渲染测试'));
  if (el) el.click();
});
await page.waitForSelector('#editor-root', { timeout: 10000 });
await page.waitForTimeout(900);

// ---- 长标题：改成 12 字 ----
R('TITLE_EL', await page.evaluate(() => {
  const t = document.querySelector('.editor-title-input, #editor-title-text');
  return t ? { cls: t.className, id: t.id, text: t.textContent, ce: t.getAttribute('contenteditable') } : null;
}));
await page.evaluate(() => {
  const t = document.querySelector('.editor-title-input, #editor-title-text');
  if (t) { t.focus(); document.execCommand('selectAll', false, null); }
});
await page.keyboard.type('一二三四五六七八九十甲乙');
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('.editor-title-input, #editor-title-text')?.blur());
await page.waitForTimeout(500);
R('LONG_TITLE', await page.evaluate(() => {
  const t = document.querySelector('.editor-title-input, #editor-title-text');
  const cap = document.querySelector('.editor-title-capsule');
  const cr = cap?.getBoundingClientRect();
  return { text: t?.textContent || null, fs: t ? getComputedStyle(t).fontSize : null, capW: cr ? Math.round(cr.width) : null, capCls: cap?.className || '' };
}));
// 恢复标题
await page.evaluate(() => {
  const t = document.querySelector('.editor-title-input, #editor-title-text');
  if (t) { t.focus(); document.execCommand('selectAll', false, null); }
});
await page.keyboard.type('全块渲染测试');
await page.evaluate(() => document.querySelector('.editor-title-input, #editor-title-text')?.blur());
await page.waitForTimeout(400);

// ---- 滚动态 ----
await page.evaluate(() => window.scrollTo(0, 500));
await page.waitForTimeout(800);
R('SCROLLED', await page.evaluate(() => {
  const dock = document.querySelector('.editor-title-dock');
  const meta = document.querySelector('.editor-title-meta');
  return {
    scrollY: window.scrollY,
    dockCls: dock?.className || '',
    dockDir: dock ? getComputedStyle(dock).flexDirection : null,
    metaDisp: meta ? getComputedStyle(meta).display : 'absent',
    avatarW: (() => { const r = document.querySelector('.editor-avatar-button')?.getBoundingClientRect(); return r ? Math.round(r.width) : null; })(),
  };
}));
await page.evaluate(() => window.scrollTo(0, 0));
await page.waitForTimeout(600);
R('UNSCROLLED_META_BACK', await page.evaluate(() => {
  const meta = document.querySelector('.editor-title-meta');
  return { dockCls: document.querySelector('.editor-title-dock')?.className || '', metaDisp: meta ? getComputedStyle(meta).display : 'absent' };
}));

// ---- 图文面板：点图文卡文本 ----
R('ITC_PRESENT', await page.evaluate(() => ({
  itc: !!document.querySelector('.img-text-card .itc-text'),
  itr: !!document.querySelector('.img-text-row .itr-text'),
  itcText: document.querySelector('.img-text-card .itc-text')?.textContent?.slice(0, 30) || '',
})));
await page.evaluate(() => {
  const el = document.querySelector('.img-text-card .itc-text') || document.querySelector('.img-text-row .itr-text');
  if (el) { const r = el.getBoundingClientRect(); el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, clientX: r.x + 20, clientY: r.y + 10 })); el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, clientX: r.x + 20, clientY: r.y + 10 })); el.click(); }
});
await page.waitForTimeout(800);
R('TEXT_SHEET', await page.evaluate(() => {
  const s = document.querySelector('.image-text-sheet');
  if (!s) return { open: false };
  return {
    open: true,
    title: s.querySelector('h2')?.textContent || '',
    content: s.querySelector('.image-text-sheet-content')?.textContent?.slice(0, 40) || '',
    action: s.querySelector('.image-text-sheet-action')?.textContent || '',
  };
}));
// 进编辑态
await page.evaluate(() => document.querySelector('.image-text-sheet-action')?.click());
await page.waitForTimeout(500);
R('TEXT_SHEET_EDIT', await page.evaluate(() => {
  const ta = document.querySelector('textarea.image-text-sheet-editor');
  return {
    hasTextarea: !!ta,
    placeholder: ta?.getAttribute('placeholder') || '',
    action: document.querySelector('.image-text-sheet-action')?.textContent || '',
  };
}));
// 点动作（完成）→ Rust 应保存并关闭
await page.evaluate(() => document.querySelector('.image-text-sheet-action')?.click());
await page.waitForTimeout(600);
R('TEXT_SHEET_AFTER_DONE', await page.evaluate(() => ({ sheetGone: !document.querySelector('.image-text-sheet') })));
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });

// ---- 链接表单：新备忘 → / → 链接 ----
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('新建'));
  if (el) el.click();
});
await page.waitForSelector('#editor-root', { timeout: 10000 });
await page.waitForTimeout(600);
R('FILE_MEDIA', await page.evaluate(() => {
  const i = document.querySelector('#file-media');
  return i ? { accept: i.getAttribute('accept'), multiple: i.multiple } : null;
}));
await page.evaluate(() => document.querySelector('#editor-root [data-bid]')?.focus());
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 6000 });
await page.waitForTimeout(400);
await page.evaluate(() => {
  const row = [...document.querySelectorAll('#slash-panel button')].find((b) => b.textContent.includes('链接'));
  if (row) row.click();
});
await page.waitForTimeout(700);
R('LINK_FORM', await page.evaluate(() => {
  const f = document.querySelector('.slash-link-form');
  if (!f) return { open: false, panelText: document.querySelector('#slash-panel')?.innerText?.replace(/\n/g, '|') || '' };
  return {
    open: true,
    title: f.querySelector('.slash-link-title')?.textContent || '',
    ph: f.querySelector('.slash-link-input')?.getAttribute('placeholder') || '',
    btns: [...f.querySelectorAll('button')].map((b) => b.textContent),
    errVisible: !!f.querySelector('.slash-link-error'),
  };
}));
// 空提交 → 错误
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.slash-link-form button')].find((x) => x.className.includes('submit')) || document.querySelector('.slash-link-submit');
  if (b) b.click();
});
await page.waitForTimeout(500);
R('LINK_FORM_INVALID', await page.evaluate(() => ({
  err: document.querySelector('.slash-link-error')?.textContent || '',
  formStillOpen: !!document.querySelector('.slash-link-form'),
})));
// 取消
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.slash-link-form button')].find((x) => !x.className.includes('submit'));
  if (b) b.click();
});
await page.waitForTimeout(500);
R('LINK_FORM_CANCEL', await page.evaluate(() => ({
  formGone: !document.querySelector('.slash-link-form'),
  panelGone: !document.querySelector('#slash-panel'),
})));
await browser.close();
console.log('DONE');
