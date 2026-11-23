// 补充探针：重进不跳栏（flow/独立）、斜杠面板右缘钳制
import { chromium } from 'playwright-core';
const URL = 'http://localhost:8931/';
const ZIP = '/tmp/fx/combined.zip';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
for (const k of ['http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'all_proxy', 'ALL_PROXY']) delete process.env[k];
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);

async function importZip(page) {
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', ZIP);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.waitForTimeout(400);
}
async function openMemo(page, title) {
  const pt = await page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt);
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, title);
  if (!pt) throw new Error('card not found');
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1500);
}
const assign = (page) => page.evaluate(() => {
  const out = [];
  document.querySelectorAll('.editor-body > .editor-column').forEach((c) => {
    const side = c.getAttribute('data-editor-column');
    [...c.children].forEach((u) => out.push(`${u.getAttribute('data-bid') || u.getAttribute('data-bids') || u.className.split(' ')[1] || '?'}@${side}`));
  });
  return { mode: document.querySelector('.editor-body').className, map: out.join(',') };
});
async function backToList(page) {
  const pt = await page.evaluate(() => {
    const f = [...document.querySelectorAll('.editor-fab')].find((b) => b.className.includes('left'));
    const r = f.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.waitForTimeout(500);
}

// ---- 1440: flow 重进 + 独立重进 ----
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, hasTouch: true });
  const page = await ctx.newPage();
  await importZip(page);
  await openMemo(page, '双栏混排');
  const A = await assign(page);
  await backToList(page);
  await openMemo(page, '双栏混排');
  const B = await assign(page);
  L('FLOW reentry stable:', A.map === B.map, '| mode:', B.mode);
  if (A.map !== B.map) { L(' A:', A.map); L(' B:', B.map); }
  // 开独立双栏
  const fab = await page.evaluate(() => {
    const f = [...document.querySelectorAll('.editor-fab')].find((b) => b.className.includes('right'));
    const r = f.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  await page.mouse.click(fab.x, fab.y);
  await page.waitForSelector('.editor-menu-panel', { timeout: 5000 });
  await page.waitForTimeout(400);
  const tg = await page.evaluate(() => {
    const t = document.querySelector('.editor-column-mode-toggle');
    const r = t.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  await page.mouse.click(tg.x, tg.y);
  await page.waitForTimeout(800);
  const C = await assign(page);
  L('INDEP mode:', C.mode, '| same assignment as flow:', C.map === A.map);
  await page.mouse.click(120, 420); // 关菜单残留遮罩（若有）
  await page.waitForTimeout(300);
  await backToList(page);
  await openMemo(page, '双栏混排');
  const D = await assign(page);
  L('INDEP reentry stable:', C.map === D.map, '| mode after reentry:', D.mode);
  if (C.map !== D.map) { L(' C:', C.map); L(' D:', D.map); }
  await ctx.close();
}

// ---- 斜杠右缘钳制 @1024 与 @1920 ----
for (const w of [1024, 1920]) {
  const ctx = await browser.newContext({ viewport: { width: w, height: 800 }, hasTouch: true });
  const page = await ctx.newPage();
  await importZip(page);
  await openMemo(page, '双栏混排');
  const pt = await page.evaluate(() => {
    const cols = document.querySelectorAll('.editor-body > .editor-column');
    const scope = cols[1];
    const u = [...scope.children].find((c) => (c.className || '').includes('blk-p'));
    const ed = u.querySelector('.ed-line') || u;
    ed.scrollIntoView({ block: 'center' });
    const r = ed.getBoundingClientRect();
    return { x: r.right - 6, y: r.bottom - 10 };
  });
  await page.mouse.click(pt.x, pt.y);
  await page.keyboard.type('/');
  await page.waitForSelector('#slash-panel', { timeout: 5000 }).catch(() => null);
  await page.waitForTimeout(400);
  const s = await page.evaluate(() => {
    const p = document.getElementById('slash-panel');
    if (!p) return null;
    const r = p.getBoundingClientRect();
    const sel = window.getSelection();
    let caret = null;
    if (sel && sel.rangeCount) { const cr = sel.getRangeAt(0).getBoundingClientRect(); caret = { x: cr.x, b: cr.bottom }; }
    return { left: r.x, right: r.right, top: r.y, w: r.width, caret };
  });
  L(`SLASH clamp @${w}:`, JSON.stringify(s), '| right margin:', s ? (w - s.right).toFixed(1) : '-');
  await ctx.close();
}
await browser.close();
L('MINI DONE');
