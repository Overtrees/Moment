// 探针（Rust）：块拖拽排序验收——桌面拖柄拖动（栏内/跨栏）、
// 双栏 layout 锚分界块数保持、撤销/重做回退、落盘重开一致、
// 触摸长按起拖（原子块）与触摸拖柄（文本块）。Chromium 口径。
// 基线 = 打开后 DOM 全序（尾随段物化产生的新块在内，属既有
// 语义）；期望序由数组搬移计算，不写死夹具原序。
import { chromium } from 'playwright-core';
const url = process.argv[2] || 'http://localhost:8214/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const moved = (arr, bid, afterBid) => {
  const a = arr.slice();
  const from = a.indexOf(bid);
  a.splice(from, 1);
  const to = a.indexOf(afterBid);
  a.splice(to + 1, 0, bid);
  return a;
};

async function importZip(page, zip) {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 }).catch(() => {});
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
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
  if (!pt) throw new Error('card not found: ' + title);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1500);
}
const readMemo = (page, title) => page.evaluate(async (t) => {
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('mynote-web', 1);
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const raw = await new Promise((res, rej) => {
    const rq = db.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
    rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error);
  });
  const data = JSON.parse(raw);
  const memos = Array.isArray(data) ? data : data.memos;
  const m = (memos || []).find((x) => x.title === t);
  return m ? { ids: m.doc.map((b) => b.id), layout: m.layout || null } : null;
}, title);
const domUnits = (page) => page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const out = { left: [], right: [], all: [] };
  const bidsOf = (el) => {
    const multi = el.getAttribute('data-bids');
    if (multi) return multi.split(',').filter(Boolean);
    const own = el.getAttribute('data-bid') || el.getAttribute('data-wrapbid');
    if (own) return [own];
    const inner = el.querySelector('[data-bid]');
    return inner ? [inner.getAttribute('data-bid')] : null;
  };
  const collect = (parent, arr) => {
    for (const child of parent.children) {
      if (child.classList?.contains('editor-column')) continue;
      const b = bidsOf(child);
      if (b) { arr.push(...b); out.all.push(...b); }
    }
  };
  const cols = body.querySelectorAll('.editor-column');
  if (cols.length === 2) { collect(cols[0], out.left); collect(cols[1], out.right); }
  else collect(body, out.left);
  return out;
});
const unitEl = (page, bid) => page.evaluateHandle((b) => {
  const body = document.querySelector('.editor-body');
  const units = [];
  const walk = (parent) => {
    for (const child of parent.children) {
      if (child.classList?.contains('editor-column')) { walk(child); continue; }
      units.push(child);
    }
  };
  walk(body);
  return units.find((u) => {
    const multi = u.getAttribute('data-bids');
    if (multi) return multi.split(',').includes(b);
    const own = u.getAttribute('data-bid') || u.getAttribute('data-wrapbid');
    if (own) return own === b;
    return u.querySelector('[data-bid]')?.getAttribute('data-bid') === b;
  }) || null;
}, bid);
const unitRect = async (page, bid) => {
  const h = await unitEl(page, bid);
  if (!h) return null;
  return h.evaluate((el) => {
    const r = el.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height, cx: r.x + r.width / 2, cy: r.y + r.height / 2, bottom: r.bottom, top: r.top };
  });
};
const scrollUnitIntoView = async (page, bid) => {
  const h = await unitEl(page, bid);
  if (h) await h.evaluate((el) => el.scrollIntoView({ block: 'center' }));
  await page.waitForTimeout(350);
};
const handleInfo = (page) => page.evaluate(() => {
  const h = document.querySelector('.blk-drag-handle');
  if (!h) return null;
  const r = h.getBoundingClientRect();
  return { display: getComputedStyle(h).display, x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
async function mouseDrag(page, fromBid, toBid, toHalf /* 'top'|'bottom' */) {
  await scrollUnitIntoView(page, toBid);
  await scrollUnitIntoView(page, fromBid);
  const from = await unitRect(page, fromBid);
  if (!from) return false;
  await page.mouse.move(from.cx, from.cy);
  await page.waitForTimeout(250);
  const h = await handleInfo(page);
  if (!h || h.display === 'none') { L('handle not visible for', fromBid, JSON.stringify(h)); return false; }
  const to = await unitRect(page, toBid);
  const targetY = toHalf === 'top' ? to.top + 3 : to.bottom - 3;
  await page.mouse.move(h.x, h.y);
  await page.mouse.down();
  const steps = 14;
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(h.x + (to.cx - h.x) * (i / steps), h.y + (targetY - h.y) * (i / steps));
    await page.waitForTimeout(30);
  }
  await page.mouse.up();
  await page.waitForTimeout(700);
  return true;
}

// ---------- 桌面：双栏拖动 ----------
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
await importZip(page, 'fixtures/twocol-mix.zip');
await openMemo(page, '双栏混排');
const dom0 = await domUnits(page);
const order0 = dom0.all;
ok('初始 DOM 全序含 tc01..tc15 相对序', eq(order0.filter((x) => x.startsWith('tc')), ['tc01', 'tc02', 'tc03', 'tc04', 'tc05', 'tc06', 'tc07', 'tc08', 'tc09', 'tc10', 'tc11', 'tc12', 'tc13', 'tc14', 'tc15']), order0.join(','));
ok('初始左栏 = 全序前 5 块', eq(dom0.left, order0.slice(0, 5)), dom0.left.join(','));

// 拖 A：tc02 拖到 tc04 之后（栏内）
const expA = moved(order0, 'tc02', 'tc04');
ok('拖A 执行', await mouseDrag(page, 'tc02', 'tc04', 'bottom'));
const mA = await readMemo(page, '双栏混排');
ok('拖A 后落盘序', eq(mA.ids, expA), mA.ids.join(','));
const diagA = await page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || ''));
ok('Diag 有 move block tc02', diagA.includes('move block tc02'));

// 拖 B：tc05（图片，左栏末）跨栏拖到 tc07 之后
const expB = moved(expA, 'tc05', 'tc07');
ok('拖B 执行', await mouseDrag(page, 'tc05', 'tc07', 'bottom'));
const mB = await readMemo(page, '双栏混排');
ok('拖B 后落盘序', eq(mB.ids, expB), mB.ids.join(','));
const domB = await domUnits(page);
ok('拖B 后 DOM 全序 == 落盘序', eq(domB.all, mB.ids), domB.all.join(','));

// 撤销回退拖 B（先点入文本块保证桥的撤销快捷键有焦点宿主）
const uPt = await unitRect(page, 'tc03');
await page.mouse.click(uPt.cx, uPt.cy);
await page.waitForTimeout(300);
await page.keyboard.press('Control+z');
await page.waitForTimeout(900);
const mU = await readMemo(page, '双栏混排');
ok('撤销后顺序回到拖A后', eq(mU.ids, expA), mU.ids.join(','));
// 重做恢复拖 B（后续布局断言以拖B后状态为基线）
await page.keyboard.press('Control+y');
await page.waitForTimeout(900);
const mR = await readMemo(page, '双栏混排');
ok('重做后顺序回到拖B后', eq(mR.ids, expB), mR.ids.join(','));

// 开启独立双栏（菜单开关，既有探针的 $eval 点法）→ 落锚；拖 C 跨栏后左栏块数保持
await page.$eval('.editor-fab.right', (e) => e.click());
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.$eval('.editor-column-mode-toggle', (e) => e.click());
await page.waitForTimeout(900);
const mT = await readMemo(page, '双栏混排');
ok('开双栏后 layout 锚存在', !!mT.layout, JSON.stringify(mT.layout).slice(0, 80));
const leftCount = mT.layout ? mT.layout.left.length : -1;
const domT = await domUnits(page);
ok('锚 left 与 DOM 左栏一致', mT.layout && eq(mT.layout.left, domT.left), (mT.layout?.left || []).join(',') + ' vs ' + domT.left.join(','));
// 关菜单再拖（第六批集成定罪）：双栏开关是 switch 行，点击后
// 菜单按设计保持打开、遮罩在场，此时拖拽无从命中块——探针须
// 先点遮罩关菜单（真实用户同理）。早期拼合树上菜单恰已关闭
// 故未暴露；最终树上为确定性失败，属探针步骤缺失、非应用缺陷
// （关菜单后拖 C 全链实测正常：指示线落 tc01 下、move block
// 6 -> 1、被拖块入左栏）。
await page.mouse.click(640, 760);
await page.waitForFunction(() => !document.querySelector('.editor-menu-panel'), null, { timeout: 5000 }).catch(() => {});
await page.waitForTimeout(300);
// 拖 C：右栏首块拖到左栏 tc01 之后
const rightFirst = domT.right[0];
ok('拖C 执行', await mouseDrag(page, rightFirst, 'tc01', 'bottom'));
const mC = await readMemo(page, '双栏混排');
ok('拖C 后 layout 左栏块数保持', mC.layout && mC.layout.left.length === leftCount, `left=${mC.layout?.left.length} want ${leftCount}`);
const domC = await domUnits(page);
ok('拖C 后 DOM 左栏 == layout.left', mC.layout && eq(domC.left, mC.layout.left), domC.left.join(','));
ok('拖C 后被拖块进了左栏', domC.left.includes(rightFirst));

// 落盘重开一致
await page.click('.editor-fab.left');
await page.waitForTimeout(1200);
await openMemo(page, '双栏混排');
const mRe = await readMemo(page, '双栏混排');
ok('重开顺序一致', eq(mRe.ids, mC.ids), mRe.ids.join(','));
await ctx.close();

// ---------- 触摸：长按原子块 + 拖柄拖文本 ----------
const ctx2 = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const p2 = await ctx2.newPage();
p2.on('pageerror', (e) => console.log('PAGEERROR(m)', String(e).slice(0, 200)));
await importZip(p2, 'fixtures/twocol-mix.zip');
await openMemo(p2, '双栏混排');
const cdp = await ctx2.newCDPSession(p2);
const touchDrag = async (x0, y0, x1, y1, holdMs) => {
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0, id: 1 }] });
  await p2.waitForTimeout(holdMs);
  const steps = 12;
  for (let i = 1; i <= steps; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x0 + (x1 - x0) * (i / steps), y: y0 + (y1 - y0) * (i / steps), id: 1 }] });
    await p2.waitForTimeout(40);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await p2.waitForTimeout(700);
};
// 文本块：点按聚焦 → 拖柄出现 → 触摸拖柄拖 tc02 到 tc03 之后
await scrollUnitIntoView(p2, 'tc02');
const t2 = await unitRect(p2, 'tc02');
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: t2.cx, y: t2.cy, id: 1 }] });
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await p2.waitForTimeout(800);
await scrollUnitIntoView(p2, 'tc03');
const h2 = await handleInfo(p2);
ok('触摸聚焦后拖柄出现', !!h2 && h2.display !== 'none', JSON.stringify(h2));
const t3 = await unitRect(p2, 'tc03');
if (h2) await touchDrag(h2.x, h2.y, t3.cx, t3.bottom - 3, 60);
const mm1 = await readMemo(p2, '双栏混排');
ok('触摸拖柄拖文本后顺序', eq(mm1.ids.filter((x) => x.startsWith('tc')).slice(0, 4), ['tc01', 'tc03', 'tc02', 'tc04']), mm1.ids.join(','));
// 原子块：长按音乐卡 tc01 → 起拖（.mn-dragging）→ 短距离拖到 tc02 之后
await scrollUnitIntoView(p2, 'tc01');
const t1 = await unitRect(p2, 'tc01');
const t2b = await unitRect(p2, 'tc02');
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: t1.cx, y: t1.cy, id: 1 }] });
await p2.waitForTimeout(750);
const draggingCls = await p2.evaluate(() => document.querySelector('.mn-dragging')?.getAttribute('data-wrapbid') || document.querySelector('.mn-dragging')?.getAttribute('data-bid') || null);
ok('长按后进入拖动态', draggingCls === 'tc01', String(draggingCls));
for (let i = 1; i <= 12; i++) {
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: t1.cx + (t2b.cx - t1.cx) * (i / 12), y: t1.cy + (t2b.bottom - 3 - t1.cy) * (i / 12), id: 1 }] });
  await p2.waitForTimeout(40);
}
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await p2.waitForTimeout(800);
const mm2 = await readMemo(p2, '双栏混排');
ok('长按拖音乐卡后顺序', eq(mm2.ids.filter((x) => x.startsWith('tc')).slice(0, 5), ['tc03', 'tc02', 'tc01', 'tc04', 'tc05']), mm2.ids.join(','));
await ctx2.close();

await browser.close();
L(fails === 0 ? 'DRAG SORT ALL PASS' : `DRAG SORT ${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
