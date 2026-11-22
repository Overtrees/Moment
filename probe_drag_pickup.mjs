// 探针（Rust）：块排序「iOS 桌面式长按拾起」验收——
// ① 无拖柄元素（挂载/悬停）② 触屏长按拾起跟指误差
// ③ 兄弟 FLIP 链位移与 --motion-reorder 曲线 ⑤ pointer-
// cancel 取消复位 ⑥ 桌面分流（文本快拖选词/hold 拾起、
// 原子块 6px 拾起）⑦ 边缘静止自动滚动。Chromium 口径。
import { chromium } from 'playwright-core';
const url = process.argv[2] || 'http://localhost:8214/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

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
const noHandleEl = (page) => page.evaluate(() => document.querySelector('.blk-drag-handle') === null);
const liftedBid = (page) => page.evaluate(() => {
  const el = document.querySelector('.mn-lifted');
  if (!el) return null;
  return el.getAttribute('data-wrapbid') || el.getAttribute('data-bid')
    || el.querySelector('[data-bid]')?.getAttribute('data-bid') || '(lifted)';
});
const diagText = (page) => page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || ''));

// ---------- 桌面 ----------
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
await importZip(page, 'fixtures/twocol-mix.zip');
await openMemo(page, '双栏混排');
const m0 = await readMemo(page, '双栏混排');

// ① 挂载后 + 悬停后无拖柄元素
ok('① 挂载后无拖柄元素', await noHandleEl(page));
const hov = await unitRect(page, 'tc02');
await page.mouse.move(hov.cx, hov.cy);
await page.waitForTimeout(400);
ok('① 悬停后无拖柄元素', await noHandleEl(page));

// ⑥a 文本块快拖 = 选词，不拾起
await scrollUnitIntoView(page, 'tc02');
const t2 = await unitRect(page, 'tc02');
await page.mouse.move(t2.x + 6, t2.cy);
await page.mouse.down();
for (let i = 1; i <= 4; i++) {
  await page.mouse.move(t2.x + 6 + i * 14, t2.cy);
  await page.waitForTimeout(25);
}
// 编辑器的拖选是桥内虚拟选区（CSS Highlight mn-xsel 呈现，
// 端点存桥内 xsel），原生 Selection 不承载拖选——按产品
// 的真实选区表示量：高亮区间文本长度（无 Highlight API
// 时回退原生选区长度）。
const selLen = await page.evaluate(() => {
  try {
    const hl = window.CSS && CSS.highlights && CSS.highlights.get('mn-xsel');
    if (hl && hl.size) { let n = 0; for (const r of hl) n += r.toString().length; return n; }
  } catch (_) {}
  return window.getSelection()?.toString().length || 0;
});
ok('⑥ 文本块快拖不拾起', (await liftedBid(page)) === null);
ok('⑥ 文本块快拖产生选区', selLen > 0, 'selLen=' + selLen);
await page.mouse.up();
await page.waitForTimeout(300);

// ⑥b 文本块 hold 280ms 拾起，松手原地落位、顺序不变
await scrollUnitIntoView(page, 'tc03');
const t3 = await unitRect(page, 'tc03');
await page.mouse.move(t3.cx, t3.cy);
await page.mouse.down();
await page.waitForTimeout(430);
ok('⑥ 文本块 hold 拾起', (await liftedBid(page)) === 'tc03');
await page.mouse.up();
await page.waitForTimeout(900);
ok('⑥ hold 松手后无残留拾起态', (await liftedBid(page)) === null);
const mHold = await readMemo(page, '双栏混排');
ok('⑥ hold 原地落位顺序不变', eq(mHold.ids, m0.ids));

// ⑥c 原子块移动 ≥6px 拾起
await scrollUnitIntoView(page, 'tc01');
const t1 = await unitRect(page, 'tc01');
await page.mouse.move(t1.cx, t1.cy);
await page.mouse.down();
await page.mouse.move(t1.cx + 4, t1.cy + 4);
await page.waitForTimeout(60);
const earlyLift = await liftedBid(page);
await page.mouse.move(t1.cx + 10, t1.cy + 10);
await page.waitForTimeout(120);
ok('⑥ 原子块 6px 内不拾起、越阈拾起', earlyLift === null && (await liftedBid(page)) === 'tc01',
  `early=${earlyLift}`);
await page.mouse.move(t1.cx, t1.cy);
await page.mouse.up();
await page.waitForTimeout(900);
const mAtom = await readMemo(page, '双栏混排');
ok('⑥ 原子块回原地落位顺序不变', eq(mAtom.ids, m0.ids));

// ③ 兄弟 FLIP 链：tc02（文本）hold 拾起后压向 tc03 下半，
// tc03 应上移一个 tc02 槽位（dy = tc02.top - tc03.top），
// 过渡时长/曲线 = --motion-reorder。
await scrollUnitIntoView(page, 'tc02');
const r2 = await unitRect(page, 'tc02');
const r3 = await unitRect(page, 'tc03');
await page.mouse.move(r2.cx, r2.cy);
await page.mouse.down();
await page.waitForTimeout(430);
ok('③ 前置：tc02 已拾起', (await liftedBid(page)) === 'tc02');
await page.mouse.move(r3.cx, r3.bottom - 3, { steps: 10 });
await page.waitForTimeout(500);
const flip = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const units = [];
  const walk = (parent) => {
    for (const child of parent.children) {
      if (child.classList?.contains('editor-column')) { walk(child); continue; }
      units.push(child);
    }
  };
  walk(body);
  const el = units.find((u) => (u.getAttribute('data-bid') || u.querySelector('[data-bid]')?.getAttribute('data-bid')) === 'tc03');
  if (!el) return null;
  const cs = getComputedStyle(el);
  const mtx = new DOMMatrixReadOnly(cs.transform);
  return {
    ty: mtx.m42,
    dur: cs.transitionDuration,
    tf: cs.transitionTimingFunction,
    token: getComputedStyle(document.documentElement).getPropertyValue('--motion-reorder').trim(),
  };
});
const expDy = r2.top - r3.top;
ok('③ 兄弟位移 = 期望链（≤1px）', !!flip && Math.abs(flip.ty - expDy) <= 1,
  flip ? `ty=${flip.ty.toFixed(1)} exp=${expDy.toFixed(1)}` : 'no el');
ok('③ 让位过渡 = --motion-reorder（0.26s + 曲线）', !!flip && flip.dur.split(',').includes('0.26s')
  && flip.tf.includes('cubic-bezier(0.22, 0.61, 0.36, 1)') && flip.token.includes('260ms'),
  flip ? `dur=${flip.dur} tf=${flip.tf} token=${flip.token}` : 'no el');
// 指回原位：兄弟复位
await page.mouse.move(r2.cx, r2.cy, { steps: 8 });
await page.waitForTimeout(500);
const flipBack = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.editor-body [data-bid]')].find((u) => u.getAttribute('data-bid') === 'tc03');
  if (!el) return null;
  const cs = getComputedStyle(el);
  return cs.transform === 'none' ? 0 : new DOMMatrixReadOnly(cs.transform).m42;
});
ok('③ 指回原位兄弟复位', flipBack !== null && Math.abs(flipBack) <= 1, 'ty=' + flipBack);
await page.mouse.up();
await page.waitForTimeout(900);
const mFlip = await readMemo(page, '双栏混排');
ok('③ 复位落位顺序不变', eq(mFlip.ids, m0.ids));
await ctx.close();

// ---------- 触屏 ----------
const ctx2 = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const p2 = await ctx2.newPage();
p2.on('pageerror', (e) => console.log('PAGEERROR(m)', String(e).slice(0, 200)));
await importZip(p2, 'fixtures/twocol-mix.zip');
await openMemo(p2, '双栏混排');
const mm0 = await readMemo(p2, '双栏混排');
const cdp = await ctx2.newCDPSession(p2);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});

// ② 长按原子块拾起 + 跟指误差（中心点采样 5 点；scale
// 关于中心对称，中心不受拾起缩放影响）
await scrollUnitIntoView(p2, 'tc01');
const a1 = await unitRect(p2, 'tc01');
const dir = a1.cy > 500 ? -1 : 1;
await touch('touchStart', a1.cx, a1.cy);
await p2.waitForTimeout(680);
ok('② 长按 480ms 后拾起', (await liftedBid(p2)) === 'tc01');
let followMax = 0;
for (let i = 1; i <= 5; i++) {
  const px = a1.cx + i * 8;
  const py = a1.cy + dir * i * 20;
  await touch('touchMove', px, py);
  await p2.waitForTimeout(170);
  const rr = await unitRect(p2, 'tc01');
  const ex = a1.cx + (px - a1.cx);
  const ey = a1.cy + (py - a1.cy);
  followMax = Math.max(followMax, Math.abs(rr.cx - ex), Math.abs(rr.cy - ey));
}
ok('② 浮块跟指误差 ≤2px（5 点）', followMax <= 2, 'max=' + followMax.toFixed(2));
await touch('touchEnd');
await p2.waitForTimeout(900);
const diag2 = await diagText(p2);
ok('② Diag 有 drag pickup / drop', diag2.includes('drag pickup') && diag2.includes('drag drop'));
const mmA = await readMemo(p2, '双栏混排');
ok('② 原地落位顺序不变', eq(mmA.ids, mm0.ids));

// ⑤ pointercancel 取消：拾起 tc05（图片）后取消 → 复
// 位、transform 清零、顺序不变、无 moveBlock（Diag 核）
await scrollUnitIntoView(p2, 'tc05');
const a5 = await unitRect(p2, 'tc05');
await touch('touchStart', a5.cx, a5.cy);
await p2.waitForTimeout(680);
ok('⑤ 前置：tc05 已拾起', (await liftedBid(p2)) === 'tc05');
await touch('touchMove', a5.cx, a5.cy + 46);
await p2.waitForTimeout(200);
await touch('touchCancel');
await p2.waitForTimeout(600);
const cancelState = await p2.evaluate(() => {
  const el = document.querySelector('[data-wrapbid="tc05"]');
  return {
    lifted: !!document.querySelector('.mn-lifted'),
    transform: el ? el.style.transform : '?',
    translate: el ? el.style.translate : '?',
  };
});
ok('⑤ 取消后无拾起态、transform 清零', !cancelState.lifted && cancelState.transform === '' && cancelState.translate === '',
  JSON.stringify(cancelState));
const mmC = await readMemo(p2, '双栏混排');
ok('⑤ 取消后顺序不变', eq(mmC.ids, mm0.ids));
const diagAfter = await diagText(p2);
ok('⑤ Diag 有 drag cancel', diagAfter.includes('drag cancel'));

// ⑦ 边缘静止自动滚动：拖 tc02（先点 tc03 移光标再长
// 按 tc02），指停视口底缘带内 600ms 不发 move，窗口
// 滚动量应 >0（rAF 循环驱动）。
const tap3 = await unitRect(p2, 'tc03');
await touch('touchStart', tap3.cx, tap3.cy);
await touch('touchEnd');
await p2.waitForTimeout(500);
await scrollUnitIntoView(p2, 'tc02');
const b2 = await unitRect(p2, 'tc02');
await touch('touchStart', b2.cx, b2.cy);
await p2.waitForTimeout(680);
ok('⑦ 前置：tc02 已拾起', (await liftedBid(p2)) === 'tc02');
await touch('touchMove', b2.cx, 830);
await p2.waitForTimeout(150);
const sy0 = await p2.evaluate(() => window.scrollY);
await p2.waitForTimeout(600);
const sy1 = await p2.evaluate(() => window.scrollY);
ok('⑦ 指停底缘 600ms 自动滚动 >0', sy1 - sy0 > 0, `scrollY ${sy0} -> ${sy1}`);
await touch('touchCancel');
await p2.waitForTimeout(500);
await ctx2.close();

await browser.close();
L(fails === 0 ? 'DRAG PICKUP ALL PASS' : `DRAG PICKUP ${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
