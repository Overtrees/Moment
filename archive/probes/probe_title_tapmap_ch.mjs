// 标题落点映射探针（Chromium 版）：导入夹具（含「标题测试一二三」7 字
// 非截断备忘），对胶囊横向多个 x 落点、纵向取胶囊中心逐个 tap，记录
// 每次聚焦后的光标 offset 与命中元素；截断标题另测两会话插入落点。
// 与 probe_title_tapmap.mjs（WebKit 版）同剧本，引擎换 Chromium。
// 用法: node probe_title_tapmap_ch.mjs <rust|orig>
import { chromium } from 'playwright-core';

const app = process.argv[2] || 'rust';
const TITLE_SEL = app === 'rust' ? '#editor-title-text' : '.editor-title-input';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 160)));

async function caretState(tag) {
  const s = await page.evaluate(([SEL, tag]) => {
    const el = document.querySelector(SEL);
    const sel = window.getSelection();
    let off = -999, node = 'none';
    if (sel.rangeCount) {
      const r = sel.getRangeAt(0);
      if (r.startContainer === el) { off = r.startOffset; node = 'EL'; }
      else if (el.contains(r.startContainer)) { off = r.startOffset; node = '#text'; }
    }
    const cap = el.closest('.editor-title-capsule') || el.parentElement.parentElement;
    const cr = cap ? cap.getBoundingClientRect() : null;
    const er = el.getBoundingClientRect();
    return { tag, active: document.activeElement === el, text: el.textContent, off, node, capR: cr ? [Math.round(cr.x), Math.round(cr.y), Math.round(cr.width), Math.round(cr.height)] : null, elR: [Math.round(er.x), Math.round(er.y), Math.round(er.width), Math.round(er.height)] };
  }, [TITLE_SEL, tag]);
  console.log('CARET', JSON.stringify(s));
  return s;
}
async function blurTap() { await page.touchscreen.tap(200, 420); await page.waitForTimeout(450); }
async function tapAt(frac, yMode, label) {
  const box = await page.evaluate((SEL) => {
    const el0 = document.querySelector(SEL); const cap = el0.closest('.editor-title-capsule') || el0.parentElement.parentElement;
    const r = cap.getBoundingClientRect();
    const er = el0.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height, elY: er.y, elH: er.height };
  }, TITLE_SEL);
  const x = box.x + box.w * frac;
  const y = yMode === 'text' ? box.elY + box.elH / 2 : box.y + box.h / 2;
  // 命中元素预告（elementFromPoint 在 tap 前的静态布局上）
  const hit = await page.evaluate(([hx, hy]) => {
    const n = document.elementFromPoint(hx, hy);
    return n ? (n.tagName.toLowerCase() + (n.id ? '#' + n.id : '') + '.' + String(n.className || '').split(' ').join('.')) : 'null';
  }, [x, y]);
  await page.touchscreen.tap(x, y);
  await page.waitForTimeout(400);
  const s = await caretState(label || ('tap@' + frac + '/' + yMode));
  console.log('  hit:', hit);
  return s;
}

if (app === 'rust') {
  await page.goto('http://localhost:8131/', { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate(() => { const h = document.querySelector('h1.page-title'); if (h) h.dispatchEvent(new MouseEvent('click', { bubbles: true })); });
  await page.waitForTimeout(600);
  await page.getByText('备份与恢复', { exact: false }).first().click();
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/home/hatch/.tmp/fixture_titles.zip');
  await page.waitForTimeout(400);
  const confirmBtn = page.locator('.backup-modal .backup-btn.primary');
  if (await confirmBtn.count()) await confirmBtn.first().click();
  await page.waitForTimeout(1200);
  await page.locator('.editor-fab.left').first().click().catch(() => {});
  await page.waitForTimeout(500);
  await page.locator('.editor-fab.left').first().click().catch(() => {});
  await page.waitForTimeout(800);
  await page.getByText('标题测试一二三', { exact: true }).first().click();
} else {
  await page.goto('http://localhost:8132/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  await page.getByText('周末看展记录', { exact: true }).first().click();
}
await page.waitForSelector(TITLE_SEL, { timeout: 10000 });
await page.waitForTimeout(600);

console.log('--- tap map: y = capsule center ---');
for (const f of [0.12, 0.3, 0.5, 0.7, 0.88]) {
  await tapAt(f, 'cap');
  await blurTap();
}
console.log('--- tap map: y = text center ---');
for (const f of [0.12, 0.3, 0.5, 0.7, 0.88]) {
  await tapAt(f, 'text');
  await blurTap();
}

// ---------- 两会话插入落点（胶囊中心 tap） ----------
console.log('--- two sessions, capsule-center tap, type one char each ---');
await tapAt(0.5, 'cap', 'sess1');
await page.keyboard.press('Q');
await page.waitForTimeout(300);
await caretState('sess1-after-Q');
await blurTap();
await tapAt(0.5, 'cap', 'sess2');
await page.keyboard.press('W');
await page.waitForTimeout(300);
await caretState('sess2-after-W');
await browser.close();
