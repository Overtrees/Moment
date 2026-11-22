// 审计探针：原版斜杠基准（第二轮，按 id 集识别新建备忘）
import { chromium } from 'playwright-core';
const url = 'http://localhost:8103/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
const L = (...a) => console.log(...a);
const readMemos = () => page.evaluate(() => { try { return JSON.parse(localStorage.getItem('memos_app_v2') || '[]'); } catch { return []; } });
const PANEL = '#mynote-slash-listbox';
async function newMemoTracked() {
  const before = new Set((await readMemos()).map((m) => String(m.id)));
  await page.click('.list-item:has(.new-card-title) .item-title-text');
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(700);
  await page.click('.editor-body [data-blockid]').catch(() => {});
  await page.waitForTimeout(200);
  return async () => {
    await page.waitForTimeout(1300);
    const memos = await readMemos();
    const mine = memos.find((m) => !before.has(String(m.id)));
    return mine?.doc;
  };
}
async function backToList() {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(500);
}
async function openSlashOrig(filter) {
  await page.keyboard.type('/');
  await page.waitForSelector(PANEL, { timeout: 6000 });
  await page.waitForTimeout(300);
  if (filter) { await page.keyboard.type(filter); await page.waitForTimeout(400); }
}
async function clickRow(id) {
  await page.evaluate(([P, i]) => document.querySelector(`${P} [data-slash-id="${i}"]`)?.click(), [PANEL, id]);
  await page.waitForTimeout(300);
}

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });

// O2 todo（空块 /db 应用）
let getDoc = await newMemoTracked();
await openSlashOrig('db');
await clickRow('todo');
await page.waitForTimeout(500);
L('O2 todo doc=', JSON.stringify(await getDoc()));
await backToList();

// O4 image（空块 /tp 应用）
getDoc = await newMemoTracked();
await openSlashOrig('tp');
await clickRow('image');
await page.waitForTimeout(500);
L('O4 image doc=', JSON.stringify(await getDoc()));
L('O4 editor DOM=', await page.evaluate(() => document.querySelector('.editor-body')?.innerHTML.slice(0, 220)));
await backToList();

// O4b gallery
getDoc = await newMemoTracked();
await openSlashOrig('hl');
await clickRow('gallery');
await page.waitForTimeout(500);
L('O4b gallery doc=', JSON.stringify(await getDoc()));
await backToList();

// O5 musicCard
getDoc = await newMemoTracked();
await openSlashOrig('yykp');
await clickRow('musicCard');
await page.waitForTimeout(500);
L('O5 music doc=', JSON.stringify(await getDoc()));
L('O5 music DOM=', await page.evaluate(() => {
  const el = document.querySelector('[data-music-url="pending"]');
  return el ? { text: el.textContent, focused: document.activeElement === el || el.contains(document.activeElement) } : null;
}));
await backToList();

// O6a bold 无选区 /jc 回车
getDoc = await newMemoTracked();
await openSlashOrig('jc');
await page.keyboard.press('Enter');
await page.waitForTimeout(500);
L('O6a bold doc=', JSON.stringify(await getDoc()));
L('O6a DOM=', await page.evaluate(() => document.querySelector('.editor-body [data-blockid]')?.innerHTML));
await backToList();

// O6c italic 无选区点击
getDoc = await newMemoTracked();
await openSlashOrig('xt');
await clickRow('italic');
await page.waitForTimeout(500);
L('O6c italic doc=', JSON.stringify(await getDoc()));
await backToList();

// O6d code 无选区
getDoc = await newMemoTracked();
await openSlashOrig('dm');
await clickRow('code');
await page.waitForTimeout(500);
L('O6d code doc=', JSON.stringify(await getDoc()));
await backToList();

// O15 divider 形状 + 尾随段
getDoc = await newMemoTracked();
await openSlashOrig('fgx');
await clickRow('divider');
await page.waitForTimeout(500);
L('O15 divider doc=', JSON.stringify(await getDoc()));
await backToList();

// O16 heading 带正文（正文 + 块首 /bt1）
getDoc = await newMemoTracked();
await page.evaluate(() => {
  const blk = document.querySelector('.editor-body [data-blockid]');
  const r = document.createRange(); r.selectNodeContents(blk); r.collapse(false);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  document.execCommand('insertText', false, '正文内容');
});
await page.waitForTimeout(300);
await page.evaluate(() => {
  const blk = document.querySelector('.editor-body [data-blockid]');
  const r = document.createRange(); r.selectNodeContents(blk); r.collapse(true);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
});
await openSlashOrig('bt1');
await clickRow('heading');
await page.waitForTimeout(500);
L('O16 heading doc=', JSON.stringify(await getDoc()));
await browser.close();
