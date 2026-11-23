import { chromium } from 'playwright-core';
const url = 'http://localhost:8212/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(2500);
await page.evaluate(async () => {
  const resp = await fetch('fixtures/xblock.zip');
  const buf = await resp.arrayBuffer();
  const unzipped = await window.MynoteZip.checkedZip(new Uint8Array(buf));
  const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
});
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2000);
// 打开 XB原子丙（折叠组先展开）
const findPt = () => page.evaluate(() => {
  const cards = [...document.querySelectorAll('.list-item, .img-card')];
  const card = cards.find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === 'XB原子丙' && !e.querySelector('.expand-btn'));
  if (!card) return null;
  const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
let pt = null;
for (let i = 0; i < 5 && !pt; i++) {
  pt = await findPt();
  if (pt) break;
  const ex = await page.evaluate(() => {
    const b = document.querySelector('.expand-btn');
    if (!b) return null;
    b.scrollIntoView({ block: 'center' });
    const r = b.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  if (ex) { await page.mouse.click(ex.x, ex.y); await page.waitForTimeout(900); }
  else await page.waitForTimeout(500);
}
console.log('card pt', JSON.stringify(pt));
if (pt) {
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1800);
  const info = await page.evaluate(() => {
    const img = document.querySelector('[data-type="image"]');
    const host = document.querySelector('.editor-body');
    return {
      imgCE: img ? img.contentEditable : 'no img',
      imgIsCE: img ? img.isContentEditable : null,
      imgAttr: img ? img.getAttribute('contenteditable') : null,
      imgOuter: img ? img.outerHTML.slice(0, 160) : null,
      hostCE: host ? host.contentEditable : null,
      pCE: (() => { const p = host.querySelector('p[data-blockid]'); return p ? { ce: p.contentEditable, is: p.isContentEditable, attr: p.getAttribute('contenteditable') } : null; })(),
    };
  });
  console.log(JSON.stringify(info, null, 1));
}
await browser.close();
