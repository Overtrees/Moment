// 标题落点映射探针（WebKit）：导入夹具（7 字非截断 / 15 字截断标题），
// 对标题胶囊横向多个 x 落点逐个 tap，记录每次聚焦后的光标 offset；
// 截断标题另测首击插入是否生效。
// 用法: node probe_title_tapmap.mjs <rust|orig>
import { webkit } from 'playwright-core';
const { WK_ENV } = await import('/home/hatch/.tmp/wk_env.mjs');

const app = process.argv[2] || 'rust';
const TITLE_SEL = app === 'rust' ? '#editor-title-text' : '.editor-title-input';
const browser = await webkit.launch({ headless: false, env: { ...WK_ENV, DISPLAY: ':99' } });
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
    return { tag, active: document.activeElement === el, text: el.textContent, off, node, capR: cr ? [Math.round(cr.x), Math.round(cr.width)] : null, elR: [Math.round(er.x), Math.round(er.width)] };
  }, [TITLE_SEL, tag]);
  console.log('CARET', JSON.stringify(s));
  return s;
}
async function blurTap() { await page.touchscreen.tap(200, 420); await page.waitForTimeout(450); }
async function tapAt(frac, label) {
  const box = await page.evaluate((SEL) => {
    const el0 = document.querySelector(SEL); const cap = el0.closest('.editor-title-capsule') || el0.parentElement.parentElement;
    const r = cap.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height };
  }, TITLE_SEL);
  const x = box.x + box.w * frac, y = box.y + box.h / 2;
  await page.touchscreen.tap(x, y);
  await page.waitForTimeout(400);
  return caretState(label || ('tap@' + frac));
}

if (app === 'rust') {
  await page.goto('http://localhost:8131/', { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  // 进设置 → 备份与恢复 → 导入夹具
  await page.evaluate(() => { const h = document.querySelector('h1.page-title'); if (h) h.dispatchEvent(new MouseEvent('click', { bubbles: true })); });
  await page.waitForTimeout(600);
  await page.getByText('备份与恢复', { exact: false }).first().click();
  console.log("AT BACKUP PAGE"); await page.waitForSelector("#file-import", { state: "attached", timeout: 8000 }); console.log("FILE IMPORT READY");
  await page.setInputFiles('#file-import', '/home/hatch/.tmp/fixture_titles.zip');
  await page.waitForTimeout(400);
  const confirmBtn = page.locator('.backup-modal .backup-btn.primary');
  if (await confirmBtn.count()) await confirmBtn.first().click();
  await page.waitForTimeout(1200);
  // 回列表
  await page.locator('.editor-fab.left').first().click().catch(() => {});
  await page.waitForTimeout(500);
  await page.locator('.editor-fab.left').first().click().catch(() => {});
  await page.waitForTimeout(800);
  console.log('LIST', await page.evaluate(() => document.body.innerText.slice(0, 200)));
} else {
  await page.goto('http://localhost:8132/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(1500);
}

// ---------- 非截断（7 字 / 种子 6 字） ----------
if (app === 'rust') {
  await page.getByText('标题测试一二三', { exact: true }).first().click();
} else {
  await page.getByText('周末看展记录', { exact: true }).first().click();
}
await page.waitForSelector(TITLE_SEL, { timeout: 10000 });
await page.waitForTimeout(600);
console.log('--- non-truncated tap map (fractions of capsule width) ---');
for (const f of [0.12, 0.3, 0.5, 0.7, 0.88]) {
  await tapAt(f);
  await blurTap();
}

// ---------- 截断（15 字） ----------
if (app === 'rust') {
  await page.evaluate(() => { const b = document.querySelector('.editor-fab.left'); if (b) b.click(); });
  await page.waitForTimeout(700);
  await page.getByText('这是一个超过十字的长标题啊', { exact: false }).first().click().catch(async () => {
    await page.getByText('这是一个超过十…', { exact: false }).first().click();
  });
  await page.waitForSelector(TITLE_SEL, { timeout: 10000 });
  await page.waitForTimeout(600);
  console.log('--- truncated: first tap + insert test ---');
  await tapAt(0.5, 'trunc-tap1');
  await page.keyboard.press('Q');
  await page.waitForTimeout(300);
  await caretState('trunc-after-type-Q');
  await blurTap();
  await tapAt(0.5, 'trunc-tap2');
  await page.keyboard.press('W');
  await page.waitForTimeout(300);
  await caretState('trunc-after-type-W');
}
await browser.close();
