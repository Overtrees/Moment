// 审计探针：原版 md 渲染基准（IDB 直注边缘 ZIP 后逐块转储）
import { chromium } from 'playwright-core';
const url = 'http://localhost:8103/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
const L = (...a) => console.log(...a);

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.waitForTimeout(1000);
// 直注备份（原版自身校验+原子恢复路径）
const seeded = await page.evaluate(async () => {
  const resp = await fetch('md_edge_probe.zip');
  const buf = await resp.arrayBuffer();
  const unzipped = await window.MynoteZip.checkedZip(new Uint8Array(buf));
  const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
  return backup.memos.length;
});
L('SEEDED', seeded);
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.waitForTimeout(800);
// 列表预览文本
const cardText = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('md边缘'));
  return el ? el.innerText.replace(/\s+/g, ' ').slice(0, 300) : 'not found';
});
L('ORIG-LIST-PREVIEW', cardText);
// 打开 md边缘
await page.click('.list-item:has-text("md边缘") .item-title-text');
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(1200);
const blocks = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  return [...body.children].map((el, i) => ({
    i, cls: el.className, tag: el.tagName,
    bid: el.dataset?.blockid || '',
    html: el.innerHTML.replace(/\s+/g, ' ').slice(0, 190),
  }));
});
for (const b of blocks) L('ORIG-MD', JSON.stringify(b));

// 点击第一个 md 预览（代码）→ 源码态 + 光标
const clickRes = await page.evaluate(() => {
  const prev = document.querySelector('.editor-body .md-preview');
  if (!prev) return 'no preview';
  const r = prev.getBoundingClientRect();
  return { x: r.x + 30, y: r.y + 12 };
});
if (typeof clickRes === 'object') {
  await page.mouse.click(clickRes.x, clickRes.y);
  await page.waitForTimeout(700);
  const st = await page.evaluate(() => {
    const s = getSelection();
    const blk = s.anchorNode?.parentElement?.closest?.('[data-blockid]');
    return {
      anchorBid: blk?.dataset?.blockid || '',
      anchorText: (s.anchorNode?.textContent || '').slice(0, 24),
      focusOffset: s.focusOffset,
      previewsLeft: document.querySelectorAll('.editor-body .md-preview').length,
    };
  });
  L('ORIG click-preview->source', JSON.stringify(st));
}
await page.keyboard.press('Escape').catch(() => {});

// 深色面板度量
const ctx2 = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'dark', acceptDownloads: true });
const p2 = await ctx2.newPage();
await p2.goto(url, { waitUntil: 'load' });
await p2.waitForSelector('.list-item', { timeout: 20000 });
await p2.click('.list-item:has(.new-card-title) .item-title-text');
await p2.waitForSelector('.editor-body', { timeout: 10000 });
await p2.waitForTimeout(700);
await p2.click('.editor-body [data-blockid]');
await p2.keyboard.type('/');
await p2.waitForSelector('#mynote-slash-listbox', { timeout: 6000 });
const dark = await p2.evaluate(() => {
  const p = document.querySelector('#mynote-slash-listbox');
  const cs = getComputedStyle(p);
  const row = p.querySelector('[data-slash-command]');
  return { panelBg: cs.backgroundColor, panelColor: cs.color, rowColor: getComputedStyle(row).color, backdrop: cs.backdropFilter };
});
L('ORIG-DARK', JSON.stringify(dark));
// 浅色代码块底色（回主上下文开 md边缘看 pre 计算样式）
await page.evaluate(() => window.scrollTo(0, 0));
const codeStyle = await page.evaluate(() => {
  const pre = document.querySelector('.editor-body .md-preview pre, .editor-body pre');
  if (!pre) return null;
  const cs = getComputedStyle(pre);
  return { bg: cs.backgroundColor, fontSize: cs.fontSize, radius: cs.borderRadius, border: cs.borderColor };
});
L('ORIG-CODE-STYLE', JSON.stringify(codeStyle));
await browser.close();
