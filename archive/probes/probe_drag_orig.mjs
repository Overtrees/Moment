// 活体定性（原版）：块是否可拖拽排序——draggable 属性、拖柄元素、dragstart 派发反应。
import { chromium } from 'playwright-core';
const url = 'http://localhost:8213/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(2500);
const seeded = await page.evaluate(async () => {
  const resp = await fetch('fixtures/twocol-mix.zip');
  const buf = await resp.arrayBuffer();
  const unzipped = await window.MynoteZip.checkedZip(new Uint8Array(buf));
  const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
  return backup.memos.length;
});
console.log('SEEDED', seeded);
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2000);
// 打开备忘（点标题文字，真实鼠标）
const pt = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item .item-title-text, .img-card .img-card-title-text')]
    .find((e) => e.textContent.trim() === '双栏混排');
  if (!el) return null;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
console.log('CARDPT', JSON.stringify(pt));
if (pt) await page.mouse.click(pt.x, pt.y);
await page.waitForSelector('.editor-body', { timeout: 10000 }).catch(() => console.log('NO EDITOR'));
await page.waitForTimeout(2000);
const info = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  if (!body) return { noEditor: true, html: document.body.innerHTML.slice(0, 300) };
  const blocks = [...body.querySelectorAll('[data-blockid]')];
  return {
    blockCount: blocks.length,
    draggableTrue: blocks.filter((b) => b.draggable).length,
    anyDraggable: document.querySelectorAll('[draggable="true"]').length,
    blockClass: blocks.filter((b) => b.classList.contains('block')).length,
    handles: document.querySelectorAll('[class*="handle" i], [class*="grip" i], [data-drag]').length,
    sample: blocks.slice(0, 3).map((b) => ({ tag: b.tagName, cls: (b.className || '').slice(0, 40), draggable: b.draggable })),
  };
});
console.log('DRAGINFO', JSON.stringify(info, null, 1));
// 派发 dragstart 看是否有 .dragging 类反应（处理函数是否接线）
const reacted = await page.evaluate(() => {
  const b = document.querySelector('.editor-body [data-blockid]');
  if (!b) return 'noblock';
  const dt = new DataTransfer();
  b.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
  return { cls: b.className, hasDragging: b.classList.contains('dragging') };
});
console.log('DRAGSTART_DISPATCH', JSON.stringify(reacted));
await browser.close();
