// 审计探针：原版斜杠菜单基准行为（只读审计用）
import { chromium } from 'playwright-core';
const url = 'http://localhost:8103/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const L = (...a) => console.log(...a);
const readMemos = () => page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('memos_app_v2') || '[]'); } catch { return null; }
});
async function newMemo() {
  await page.click('.list-item:has(.new-card-title) .item-title-text');
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(700);
  await page.click('.editor-body [data-blockid]').catch(() => {});
  await page.waitForTimeout(200);
}
async function backToList() {
  await page.click('.editor-fab.left').catch(async () => {
    await page.evaluate(() => document.querySelector('.editor-fab.left')?.click());
  });
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(500);
}
async function myDoc(marker) {
  await page.waitForTimeout(1300); // 等自动保存
  const memos = await readMemos();
  if (!memos) return null;
  const m = memos.filter((x) => JSON.stringify(x.doc).includes(marker)).pop() || memos[memos.length - 1];
  return m?.doc;
}
const PANEL = '#mynote-slash-listbox';
async function openSlashOrig(filter) {
  await page.keyboard.type('/');
  await page.waitForSelector(PANEL, { timeout: 6000 });
  await page.waitForTimeout(300);
  if (filter) { await page.keyboard.type(filter); await page.waitForTimeout(400); }
}
async function panelInfo() {
  return page.evaluate((P) => {
    const p = document.querySelector(P);
    if (!p) return null;
    const r = p.getBoundingClientRect();
    const cs = getComputedStyle(p);
    return {
      rect: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
      z: cs.zIndex, maxH: cs.maxHeight, radius: cs.borderRadius,
      heads: [...p.querySelectorAll('.slash-section-heading')].map((e) => e.textContent),
      rows: [...p.querySelectorAll('[data-slash-command]')].map((e) => ({
        id: e.dataset.slashId, title: e.querySelector('.slash-row-title-text')?.textContent,
        mark: !!e.querySelector('.slash-match'),
        pillInTitle: !!e.querySelector('.slash-row-title .slash-recent-pill'),
        pillAny: !!e.querySelector('.slash-recent-pill'),
        h: Math.round(e.getBoundingClientRect().height),
      })),
      emptyText: p.querySelector('.slash-empty-state')?.innerText || '',
    };
  }, PANEL);
}
async function clickRow(id) {
  await page.evaluate(([P, i]) => document.querySelector(`${P} [data-slash-id="${i}"]`)?.click(), [PANEL, id]);
  await page.waitForTimeout(200);
}
async function setText(text) {
  await page.evaluate((t) => {
    const body = document.querySelector('.editor-body');
    body.focus();
    const blk = body.querySelector('[data-blockid]');
    if (blk) {
      const r = document.createRange(); r.selectNodeContents(blk); r.collapse(false);
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
    }
    document.execCommand('insertText', false, t);
  }, text);
  await page.waitForTimeout(300);
}
async function caretToBlockStart() {
  await page.evaluate(() => {
    const blk = document.querySelector('.editor-body [data-blockid]');
    if (!blk) return;
    const r = document.createRange(); r.selectNodeContents(blk); r.collapse(true);
    const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  });
  await page.waitForTimeout(150);
}

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
await newMemo();
L('EDITOR open, blockids:', await page.evaluate(() => document.querySelectorAll('.editor-body [data-blockid]').length));

// O1 面板度量 + O7 块中触发（先打 abc 再 /）
await setText('abc');
await openSlashOrig();
let info = await panelInfo();
const caret = await page.evaluate(() => {
  const s = getSelection(); const r = s.getRangeAt(0).getBoundingClientRect();
  const blk = document.querySelector('.editor-body [data-blockid]'); const br = blk.getBoundingClientRect();
  return { caretBottom: Math.round(r.bottom), blockBottom: Math.round(br.bottom), panelTop: null };
});
L('O7 mid-text panel?', !!info, 'O1', JSON.stringify(info && { rect: info.rect, z: info.z, maxH: info.maxH, radius: info.radius, heads: info.heads, n: info.rows.length, rowH: info.rows[0]?.h }), 'caretBottom=', caret.caretBottom, 'blockBottom=', caret.blockBottom);

// O8 搜索
for (const q of ['图', 'unordered', 'code_block', 'fgx']) {
  await page.keyboard.press('Backspace').catch(() => {});
  await page.evaluate(() => { const s = getSelection(); if (s.rangeCount) s.collapseToEnd(); });
  // 清空查询：删掉已输入的查询字符（简单法：Esc 后重打）
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  await page.evaluate(() => {
    const blk = document.querySelector('.editor-body [data-blockid]');
    if (blk) { blk.focus(); const r = document.createRange(); r.selectNodeContents(blk); const s = getSelection(); s.removeAllRanges(); s.addRange(r); document.execCommand('delete', false, null); }
  });
  await page.waitForTimeout(200);
  await openSlashOrig(q);
  const pi = await panelInfo();
  L('O8 SEARCH', q, '->', pi ? pi.rows.map((r) => r.title).join('|') : 'NOPANEL', pi?.emptyText ? 'EMPTY:' + pi.emptyText.replace(/\n/g, ' ') : '', 'mark=', pi?.rows[0]?.mark);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(250);
}

// O2 /db 应用 → todo 文本
await page.evaluate(() => {
  const blk = document.querySelector('.editor-body [data-blockid]');
  if (blk) { blk.focus(); const r = document.createRange(); r.selectNodeContents(blk); const s = getSelection(); s.removeAllRanges(); s.addRange(r); document.execCommand('delete', false, null); }
});
await openSlashOrig('db');
await clickRow('todo');
await page.waitForTimeout(600);
L('O2 todo doc=', JSON.stringify(await myDoc('')));

// O3 图文卡（带正文）
await backToList(); await newMemo();
await setText('正文内容');
await caretToBlockStart();
await openSlashOrig('twkp');
await clickRow('imgTextCard');
await page.waitForTimeout(600);
L('O3 imgTextCard doc=', JSON.stringify(await myDoc('点击输入文字')));

// O4 图片
await backToList(); await newMemo();
await openSlashOrig('tp');
await clickRow('image');
await page.waitForTimeout(600);
L('O4 image doc=', JSON.stringify(await myDoc('')));

// O5 音乐卡
await backToList(); await newMemo();
await openSlashOrig('yykp');
await clickRow('musicCard');
await page.waitForTimeout(600);
L('O5 musicCard doc=', JSON.stringify(await myDoc('')));
L('O5 activeEl=', await page.evaluate(() => document.activeElement?.dataset?.blockid ? 'block' : document.activeElement?.className || document.activeElement?.tagName));

// O6a 行内加粗（无选区，/jc 回车）
await backToList(); await newMemo();
await openSlashOrig('jc');
await page.keyboard.press('Enter');
await page.waitForTimeout(600);
L('O6a bold-collapsed doc=', JSON.stringify(await myDoc('')));
// O6b 行内加粗（先 / 开面板，再选中正文词，点击加粗）
await backToList(); await newMemo();
await setText('目标词组在这里');
await caretToBlockStart();
await openSlashOrig();
await page.evaluate(() => {
  const blk = document.querySelector('.editor-body [data-blockid]');
  const tn = [...blk.childNodes].find((n) => n.nodeType === 3 && n.textContent.includes('词组')) || blk.firstChild;
  const base = tn.textContent.indexOf('词组');
  const r = document.createRange(); r.setStart(tn, base); r.setEnd(tn, base + 2);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.waitForTimeout(400);
await clickRow('bold');
await page.waitForTimeout(600);
L('O6b bold-selection doc=', JSON.stringify(await myDoc('词组')));

// O9 链接表单
await backToList(); await newMemo();
await openSlashOrig('lj');
await clickRow('link');
await page.waitForTimeout(500);
const lf = await page.evaluate((P) => {
  const p = document.querySelector(P);
  const input = p?.querySelector('.slash-link-input');
  return p ? {
    title: p.querySelector('.slash-link-title')?.textContent,
    placeholder: input?.getAttribute('placeholder'), value: input?.value,
    focused: document.activeElement === input,
    btns: [...p.querySelectorAll('.slash-link-actions button')].map((b) => b.textContent),
  } : null;
}, PANEL);
L('O9 linkform', JSON.stringify(lf));
await page.evaluate((P) => document.querySelector(`${P} .slash-link-cancel`)?.click(), PANEL);
await page.waitForTimeout(400);
const afterCancel = await panelInfo();
L('O9 cancel -> panel list back?', !!afterCancel && afterCancel.rows.length > 0, 'rows=', afterCancel?.rows.length);

// O10 Esc / 点外
await page.keyboard.press('Escape');
await page.waitForTimeout(300);
await openSlashOrig();
await page.mouse.click(350, 720);
await page.waitForTimeout(500);
L('O10 outclick panel?', await page.evaluate((P) => !!document.querySelector(P), PANEL));

// O13 代码块含 ```
await backToList(); await newMemo();
await setText('a```b');
await caretToBlockStart();
await openSlashOrig('dmk');
await clickRow('codeBlock');
await page.waitForTimeout(600);
L('O13 codefence doc=', JSON.stringify(await myDoc('```')));

L('ERRORS', JSON.stringify(errors.slice(0, 4)));
await browser.close();
