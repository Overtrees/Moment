// 审计探针 2：Rust 斜杠——过滤残渣/中途触发/行内选区点击/类型间转换/高块锚点
import { chromium } from 'playwright-core';
const url = 'http://localhost:8102/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const L = (...a) => console.log(...a);
const readMemos = () => page.evaluate(() => new Promise((res) => {
  const req = indexedDB.open('mynote-web', 1);
  req.onsuccess = () => {
    const g = req.result.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
    g.onsuccess = () => { try { res(JSON.parse(g.result).memos); } catch { res(null); } };
    g.onerror = () => res(null);
  };
  req.onerror = () => res(null);
}));
async function newMemo() {
  await page.evaluate(() => [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('新建'))?.click());
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(500);
}
async function backToList() {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
  await page.waitForTimeout(300);
}
const firstBlock = () => page.evaluate(() => document.querySelector('#editor-root [data-bid]')?.focus());
async function setBlockText(text, caretEnd = true) {
  await page.evaluate((t) => {
    const el = document.querySelector('#editor-root [data-bid]');
    el.focus();
    document.execCommand('selectAll', false, null);
    document.execCommand('insertText', false, t);
  }, text);
  await page.waitForTimeout(250);
}

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });

// R1: 纯过滤应用（Enter 路径）——块内只有 /db
await newMemo();
await firstBlock();
await page.keyboard.type('/db');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.waitForTimeout(300);
await page.keyboard.press('Enter');
await page.waitForTimeout(600);
let memos = await readMemos();
L('R1 todo-after-/db doc=', JSON.stringify(memos[memos.length - 1].doc));
// R1b: 点击路径，带正文：正文 + 块首 /yy 应用引用
await backToList(); await newMemo();
await setBlockText('正文内容');
await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const r = document.createRange(); r.setStart(el.firstChild, 0); r.collapse(true);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.keyboard.type('/yy');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="quote"]')?.click());
await page.waitForTimeout(600);
memos = await readMemos();
L('R1b quote doc=', JSON.stringify(memos[memos.length - 1].doc));

// R2: 块中触发（确定性光标在 abc 末尾）
await backToList(); await newMemo();
await setBlockText('abc');
await page.keyboard.type('/');
await page.waitForTimeout(700);
L('R2 mid-text panel?', await page.evaluate(() => !!document.querySelector('#slash-panel')));

// R3: 面板开着时选中正文词，再点击行内命令
await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const r = document.createRange(); r.setStart(el.firstChild, 0); r.collapse(true);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.keyboard.press('Backspace'); // 删掉刚打的 /（若有）
await setBlockText('目标词组在这里');
await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const r = document.createRange(); r.setStart(el.firstChild, 0); r.collapse(true);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.waitForTimeout(300);
// 选中「词组」(offset 3..5 → 文本 目标词组在这里: 0目1标2词3组4在...) 选 2..4 = 词组
await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const tn = [...el.childNodes].find((n) => n.nodeType === 3 && n.textContent.includes('词组'));
  const base = tn.textContent.indexOf('词组');
  const r = document.createRange(); r.setStart(tn, base); r.setEnd(tn, base + 2);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="bold"]')?.click());
await page.waitForTimeout(600);
L('R3 bold-click DOM=', await page.evaluate(() => document.querySelector('#editor-root [data-bid]')?.innerHTML));
// 再来代码行内（词组应还存在）
await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  el.focus();
  const r = document.createRange(); r.setStart(el.firstChild, 0); r.collapse(true);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.waitForTimeout(300);
await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const tn = [...el.childNodes].find((n) => n.nodeType === 3 && n.textContent.includes('词组'));
  if (!tn) return;
  const base = tn.textContent.indexOf('词组');
  const r = document.createRange(); r.setStart(tn, base); r.setEnd(tn, base + 2);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="code"]')?.click());
await page.waitForTimeout(600);
L('R3 code-click DOM=', await page.evaluate(() => document.querySelector('#editor-root [data-bid]')?.innerHTML));
memos = await readMemos();
L('R3 doc=', JSON.stringify(memos[memos.length - 1].doc));

// R4: 类型间转换稳定性（标题→分割线、待办→引用、引用→标题）
async function convertFlow(setupFilter, setupAct, thenFilter, thenAct, label) {
  await backToList(); await newMemo();
  await firstBlock();
  await page.keyboard.type('转换文本');
  await page.waitForTimeout(200);
  await page.evaluate(() => {
    const el = document.querySelector('#editor-root [data-bid]');
    const r = document.createRange(); r.setStart(el.firstChild, 0); r.collapse(true);
    const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  });
  await page.keyboard.type('/' + setupFilter);
  await page.waitForSelector('#slash-panel', { timeout: 5000 });
  await page.waitForTimeout(250);
  await page.evaluate((a) => document.querySelector(`#slash-panel .slash-row[data-act="${a}"]`)?.click(), setupAct);
  await page.waitForTimeout(600);
  // 在新块里块首打 /
  await page.evaluate(() => {
    const el = document.querySelector('#editor-root [data-bid]');
    if (!el) return;
    el.focus();
    const tn = [...el.childNodes].find((n) => n.nodeType === 3);
    if (tn) { const r = document.createRange(); r.setStart(tn, 0); r.collapse(true); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
  });
  await page.keyboard.type('/' + thenFilter);
  await page.waitForSelector('#slash-panel', { timeout: 5000 });
  await page.waitForTimeout(250);
  await page.evaluate((a) => document.querySelector(`#slash-panel .slash-row[data-act="${a}"]`)?.click(), thenAct);
  await page.waitForTimeout(600);
  const ms = await readMemos();
  L('R4', label, 'doc=', JSON.stringify(ms[ms.length - 1].doc), 'errors=', errors.length);
}
await convertFlow('bt1', 'heading1', 'fgx', 'divider', 'heading->divider');
await convertFlow('db', 'todo', 'yy', 'quote', 'todo->quote');
await convertFlow('yy', 'quote', 'bt2', 'heading2', 'quote->heading2');

// R5: 高块锚点（10 行段落，光标在第一行行首打 /）
await backToList(); await newMemo();
await setBlockText('第一行\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行\n第八行\n第九行\n第十行');
await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const tn = [...el.childNodes].find((n) => n.nodeType === 3);
  const r = document.createRange(); r.setStart(tn, 0); r.collapse(true);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.waitForTimeout(300);
const r5 = await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const p = document.querySelector('#slash-panel');
  const br = el.getBoundingClientRect(); const pr = p.getBoundingClientRect();
  const sel = getSelection(); const cr = sel.getRangeAt(0).getBoundingClientRect();
  return { blockTop: Math.round(br.top), blockBottom: Math.round(br.bottom), panelTop: Math.round(pr.top), caretTop: Math.round(cr.top), caretBottom: Math.round(cr.bottom) };
});
L('R5 anchor', JSON.stringify(r5));

L('ERRORS', JSON.stringify(errors));
await browser.close();
