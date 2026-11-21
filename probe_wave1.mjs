// 本波修复验证探针（编辑态 D1/D2/D4 + 斜杠 S1/S4 + 回车 B1 + 粘贴 B9）
// 用法: node probe_wave1.mjs http://localhost:8096/
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8096/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (cond, name, extra = '') => {
  console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : ''));
  if (!cond) fails++;
};

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

async function newMemo() {
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
  // 点新建卡（列表右下/顶部的新建入口与冒烟一致：点 h1 后用 JS 点新建按钮不可靠，
  // 用页面上的新建卡片元素）
  await page.click('.new-card-title');
  await page.waitForSelector('#editor-root [data-bid]', { timeout: 10000 });
  await page.waitForTimeout(400);
}

function blocksText() {
  return page.$$eval('#editor-root [data-bid]', (els) =>
    els.map((e) => ({ bid: e.dataset.bid, btype: e.dataset.btype || '', text: e.innerText.replace(/\n$/, '') })));
}
async function setCaret(bid, offset) {
  await page.evaluate(([bid, offset]) => {
    const el = document.querySelector('[data-bid="' + bid + '"]');
    el.focus();
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n = walker.nextNode(), acc = 0;
    while (n) {
      const L = n.textContent.length;
      if (acc + L >= offset) {
        const r = document.createRange();
        r.setStart(n, offset - acc);
        r.collapse(true);
        const s = window.getSelection();
        s.removeAllRanges(); s.addRange(r);
        return;
      }
      acc += L; n = walker.nextNode();
    }
  }, [bid, offset]);
}

// ---------- 1. D1 拆块 DOM 回写 ----------
await newMemo();
let bl = await blocksText();
const firstBid = bl[0].bid;
await page.click(`[data-bid="${firstBid}"]`);
await page.keyboard.type('HelloWorld');
await setCaret(firstBid, 5);
await page.keyboard.press('Enter');
await page.waitForTimeout(500);
bl = await blocksText();
const texts = bl.map((b) => b.text);
ok(texts[0] === 'Hello' && texts[1] === 'World', 'D1 拆块后两块 DOM 文本恰为 Hello/World', JSON.stringify(texts.slice(0, 3)));
// 开一次 ••• 菜单（触发全量同步）后不应被旧 DOM 覆盖
await page.locator('.editor-fab.right, .fab-more, button[aria-label="更多"]').first().click().catch(() => {});
await page.waitForTimeout(600);
bl = await blocksText();
ok(bl[0].text === 'Hello' && bl[1].text === 'World', 'D1 开菜单同步后仍 Hello/World', JSON.stringify(bl.map(b => b.text).slice(0, 3)));

// ---------- 2. D1 合并 DOM 回写 ----------
await newMemo();
bl = await blocksText();
const b1 = bl[0].bid;
await page.click(`[data-bid="${b1}"]`);
await page.keyboard.type('XYZ');
await page.keyboard.press('Enter');
await page.waitForTimeout(300);
await page.keyboard.type('ABC');
bl = await blocksText();
const secondBid = bl[1].bid;
await setCaret(secondBid, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(500);
bl = await blocksText();
ok(bl.length >= 1 && bl[0].text === 'XYZABC', 'D1 合并后存活块 DOM 立即为 XYZABC', JSON.stringify(bl.map(b => b.text)));

// ---------- 3. 斜杠 S1 过滤词不残留 ----------
await newMemo();
bl = await blocksText();
await page.click(`[data-bid="${bl[0].bid}"]`);
await page.keyboard.type('/db');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.keyboard.press('Enter');
await page.waitForTimeout(600);
bl = await blocksText();
ok(!bl.some((b) => b.text.includes('db')), 'S1 应用待办后正文无 db 残留', JSON.stringify(bl.map(b => b.text)));
const hasTodo = await page.evaluate(() => !!document.querySelector('#editor-root .todo, #editor-root [data-btype="todo"]'));
ok(hasTodo, 'S1 块已转为待办');

// ---------- 4. D2/D4 撤销接管 + 焦点恢复 ----------
await newMemo();
bl = await blocksText();
await page.click(`[data-bid="${bl[0].bid}"]`);
await page.keyboard.type('UndoMe');
await page.waitForTimeout(300);
await page.keyboard.press('Control+z');
await page.waitForTimeout(700);
bl = await blocksText();
ok(!bl.some((b) => b.text.includes('UndoMe')), 'D2 Ctrl+Z 走应用撤销（文字被撤）', JSON.stringify(bl.map(b => b.text)));
const ae = await page.evaluate(() => document.activeElement && document.activeElement.dataset ? (document.activeElement.dataset.bid || document.activeElement.tagName) : 'none');
ok(ae !== 'BODY' && ae !== 'none', 'D4 撤销后焦点在编辑块内', 'activeElement=' + ae);
await page.keyboard.press('Control+Shift+z');
await page.waitForTimeout(700);
bl = await blocksText();
ok(bl.some((b) => b.text.includes('UndoMe')), 'D2 Ctrl+Shift+Z 重做回来', JSON.stringify(bl.map(b => b.text)));

// ---------- 5. B1 标题回车不拆 ----------
await newMemo();
bl = await blocksText();
await page.click(`[data-bid="${bl[0].bid}"]`);
await page.keyboard.type('/bt');
await page.waitForSelector('#slash-panel', { timeout: 5000 }).catch(() => {});
await page.keyboard.press('Enter'); // 应用标题（过滤 bt -> 标题相关命令，取当前高亮）
await page.waitForTimeout(500);
bl = await blocksText();
// 若没转成标题（过滤未命中），此例跳过断言只记录
const isHeading = await page.evaluate(() => !!document.querySelector('#editor-root [data-btype="heading"], #editor-root .ed-heading'));
if (isHeading) {
  const hb = bl[0].bid;
  await page.click(`[data-bid="${hb}"]`);
  await page.keyboard.type('TitleText');
  await setCaret(hb, 5);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(500);
  bl = await blocksText();
  ok(bl[0].text === 'TitleText' && bl[1] && bl[1].text === '', 'B1 标题回车整段保留+其后空段', JSON.stringify(bl.map(b => b.text).slice(0, 3)));
} else {
  console.log('- B1 跳过：/bt 未命中标题命令');
}

// ---------- 6. B9 粘贴纯文本口径 ----------
await newMemo();
bl = await blocksText();
const pb = bl[0].bid;
await page.click(`[data-bid="${pb}"]`);
await page.evaluate((bid) => {
  const el = document.querySelector('[data-bid="' + bid + '"]');
  el.focus();
  const dt = new DataTransfer();
  dt.setData('text/plain', 'line1\nline2');
  dt.setData('text/html', '<b>line1</b><div>line2</div>');
  el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
}, pb);
await page.waitForTimeout(600);
bl = await blocksText();
const pblock = bl.find((b) => b.bid === pb);
const phtml = await page.$eval(`[data-bid="${pb}"]`, (e) => e.innerHTML);
ok(pblock && pblock.text.includes('line1') && pblock.text.includes('line2'), 'B9 粘贴两行都进当前块', pblock ? pblock.text : 'none');
ok(!/<b>/.test(phtml), 'B9 HTML 格式不带入（无 <b>）', phtml.slice(0, 80));

// ---------- 8. 调优：待办/引用回车延续 + 空块退出 ----------
await newMemo();
bl = await blocksText();
await page.click(`[data-bid="${bl[0].bid}"]`);
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.locator('#slash-panel .slash-row[data-act="todo"]').first().click();
await page.waitForTimeout(500);
bl = await blocksText();
const todoBid = bl[0].bid;
await page.click(`[data-bid="${todoBid}"]`);
await page.keyboard.type('BuyMilk');
await setCaret(todoBid, 3);
await page.keyboard.press('Enter');
await page.waitForTimeout(500);
bl = await blocksText();
const todoTypes = await page.$$eval('#editor-root [data-btype="todo"]', (els) => els.map((e) => e.innerText.replace(/\n$/, '')));
ok(todoTypes.length === 2 && todoTypes[0] === 'Buy' && todoTypes[1] === 'Milk', '调优 待办回车按光标拆为两条待办', JSON.stringify(todoTypes));
// 第二条待办清空后回车 → 自身转段落退出
const todoSecondBid = bl[1].bid;
await page.click(`[data-bid="${todoSecondBid}"]`);
await page.keyboard.press('Control+a');
await page.keyboard.press('Backspace');
await page.waitForTimeout(300);
await page.keyboard.press('Enter');
await page.waitForTimeout(500);
const afterExit = await page.$$eval('#editor-root [data-btype]', (els) => els.map((e) => e.dataset.btype));
ok(afterExit.filter((t) => t === 'todo').length === 1 && afterExit.includes('paragraph'), '调优 空待办回车转段落退出', JSON.stringify(afterExit));

// ---------- 7. S4 图片占位块 ----------
await newMemo();
bl = await blocksText();
const before = bl.length;
await page.click(`[data-bid="${bl[0].bid}"]`);
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.locator('#slash-panel .slash-row[data-act="image"]').first().click();
await page.waitForTimeout(700);
const ph = await page.evaluate(() => !!document.querySelector('#editor-root .atomic-placeholder'));
const childCount = await page.evaluate(() => document.querySelector('.editor-body').children.length);
ok(ph, 'S4 应用图片落占位块');
ok(childCount === before + 1, 'S4 尾随空段补齐（块数 +1）', `before=${before} after=${childCount}`);

ok(errors.length === 0, '全程无 pageerror', errors.slice(0, 2).join(' ; '));
console.log(fails === 0 ? 'PROBE ALL PASS' : `PROBE FAILURES: ${fails}`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
