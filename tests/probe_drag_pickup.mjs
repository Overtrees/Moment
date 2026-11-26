// 探针（Rust）：块排序「iOS 桌面式长按拾起」验收——
// ① 无拖柄元素（挂载/悬停）② 触屏长按拾起跟指误差
// ③ 兄弟 FLIP 链位移与 --motion-reorder 曲线 ⑤ pointer-
// cancel 取消复位 ⑥ 桌面分流（文本快拖选词/hold 拾起、
// 原子块 6px 拾起；覆盖卡拾起弹菜单、原地松手留存、
// Esc 关闭——卡片交互专项）⑦ 边缘静止自动滚动 ⑧ 拾起
// 定形（视觉面驱动动态适配，用户 2026-11-23 裁定，
// supersede b311293 盒级等距内收与 fab40b5 抓握点原点
// 等比缩放）：拾起框 = 块视觉面四边外扩 4px、框半径
// = 视觉面半径 + 4（同心嵌套），由单元 ::before 按桥
// 写入的 CSS 变量几何绘制；缩放以视觉面中心为原点、
// 双轴 scale=(面边长-8)/面边长（钳制 ≥0.9）；抓握点
// 局部比例不漂移（平移补偿）；无视觉面的文本块拾起
// 框半径归零。逐块型全矩阵断言见 probe_lift_surface
// （本探针 ⑧ 只守 tc01/tc05/tc07 三个代表块的新口径
// 不变量）。Chromium 口径。
import { chromium } from 'playwright-core';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
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
  const zipPath = path.isAbsolute(zip) ? zip : path.join(path.dirname(fileURLToPath(import.meta.url)), zip);
  await page.setInputFiles('#file-import', zipPath);
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
    const r = indexedDB.open('mynote-web');
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  // 组装读（IDB 分条合流适配，只换读取通道、断言不变）：
  // memos_json 在则直用；否则 backup_meta + memos_order +
  // memos 店组装回全量 JSON。
  const raw = await (async () => {
    const getKv = (k) => new Promise((res) => { const rq = db.transaction('kv', 'readonly').objectStore('kv').get(k); rq.onsuccess = () => res(rq.result); rq.onerror = () => res(undefined); });
    const legacy = await getKv('memos_json');
    if (legacy !== undefined) return legacy;
    const meta = await getKv('backup_meta');
    if (!meta) return undefined;
    const order = JSON.parse((await getKv('memos_order')) || '[]');
    const [vals, ks] = await Promise.all([
      new Promise((res) => { const rq = db.transaction('memos', 'readonly').objectStore('memos').getAll(); rq.onsuccess = () => res(rq.result || []); rq.onerror = () => res([]); }),
      new Promise((res) => { const rq = db.transaction('memos', 'readonly').objectStore('memos').getAllKeys(); rq.onsuccess = () => res(rq.result || []); rq.onerror = () => res([]); }),
    ]);
    const byId = new Map(ks.map((k, i) => [String(k), vals[i]]));
    const root = JSON.parse(meta);
    root.memos = order.map((id) => byId.get(String(id))).filter((v) => v !== undefined).map((v) => JSON.parse(v));
    return JSON.stringify(root);
  })();
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
const diagText = (page) => page.evaluate(() => (localStorage.getItem('moment_diag_v1') || ''));
// Diag 落盘为 1s 节流合并写（批10 T-F）：动作后固定短等再读
// localStorage 会落在节流窗内假红。正向断言改轮询等目标行
// 落盘（200ms 步进、上限约 6s）后仍按原判据断言。只改读取
// 时序，不放宽判据。
const waitDiag = async (page, pred, timeoutMs = 6000) => {
  const t0 = Date.now();
  let txt = await diagText(page);
  while (!pred(txt) && Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(200);
    txt = await diagText(page);
  }
  return txt;
};

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
const t3radius = await page.evaluate(() => {
  const el = document.querySelector('.mn-lifted');
  if (!el) return null;
  // 拾起框（::before）渲染半径：局部值 × 单元渲染缩放
  const cs = getComputedStyle(el, '::before');
  const kx = el.getBoundingClientRect().width / el.offsetWidth;
  return parseFloat(cs.borderTopLeftRadius) * kx;
});
ok('⑧ 文本块拾起框半径 = 4（面即单元、半径 0 同心外扩）', t3radius !== null && Math.abs(t3radius - 4) <= 1,
  'r=' + (t3radius !== null ? t3radius.toFixed(2) : 'null'));
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
// 卡片交互专项：tc01（音乐卡，覆盖面内）拾起即弹菜单；
// 本段指针回原点（相对拾起点位移 ≤10px）属原地松手，
// 菜单留存待点选——断言其留存并以 Esc 关闭，避免菜单
// 遮罩拦截后续段落的点按。
ok('⑥ 覆盖卡拾起弹菜单、原地松手留存', await page.evaluate(() => !!document.querySelector('.card-menu-panel')));
await page.keyboard.press('Escape');
await page.waitForTimeout(250);
ok('⑥ Esc 关菜单', await page.evaluate(() => !document.querySelector('.card-menu-panel')));
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
// ⑧ 视觉面/拾起框量测助手（与桥 resolveLiftSurface 同
// 规则复刻：标记并集 → 最大有面后代（排除应用铬件）→
// 单元自身；拾起框 ::before 几何按 computed 值 + 单元
// 渲染矩阵换算回视口坐标。与 probe_lift_surface 同量法。）
await p2.evaluate(() => {
  window.__cornersPx = (el) => {
    const cs = getComputedStyle(el);
    const parse = (v) => {
      const t = (v || '0px').trim().split(/\s+/);
      return [parseFloat(t[0]) || 0, parseFloat(t.length > 1 ? t[1] : t[0]) || 0];
    };
    return [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map(parse);
  };
  window.__surfResolve = (unit) => {
    const R = (el) => { const r = el.getBoundingClientRect();
      return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height }; };
    const marked = unit.querySelectorAll('[data-liftsurface]');
    if (marked.length) {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      marked.forEach((el) => { const r = R(el);
        x0 = Math.min(x0, r.left); y0 = Math.min(y0, r.top);
        x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom); });
      return { rect: { left: x0, top: y0, right: x1, bottom: y1, width: x1 - x0, height: y1 - y0 }, corners: window.__cornersPx(marked[0]), via: 'marked' };
    }
    const ur = unit.getBoundingClientRect();
    const uArea = ur.width * ur.height;
    let best = null, bestArea = 0;
    const consider = (el) => {
      if (el.closest('.blk-more, .card-menu-panel')) return;
      const cs = getComputedStyle(el);
      if (cs.display === 'inline') return;
      const bg = cs.backgroundColor;
      const bf = (cs.backdropFilter || cs.getPropertyValue('-webkit-backdrop-filter') || '').trim();
      const hasFace = (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent')
        || (bf !== '' && bf !== 'none') || el.tagName === 'IMG' || el.tagName === 'VIDEO';
      if (!hasFace) return;
      const corners = [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius];
      if (!corners.some((c) => (c || '').split(/\s+/).some((t) => parseFloat(t) > 0))) return;
      const r = el.getBoundingClientRect();
      const area = r.width * r.height;
      if (area < uArea * 0.15 || area <= bestArea) return;
      bestArea = area; best = el;
    };
    unit.querySelectorAll('*').forEach(consider);
    if (best) return { rect: R(best), corners: window.__cornersPx(best), via: 'heuristic' };
    return { rect: R(unit), corners: window.__cornersPx(unit), via: 'unit' };
  };
  window.__frameRect = (unit) => {
    const cs = getComputedStyle(unit, '::before');
    // ::before 定位相对内边距盒，须加回边框宽换算到边
    // 框盒坐标（理由见 probe_lift_surface 同名助手）。
    const fl = parseFloat(cs.left) + (unit.clientLeft || 0), ft = parseFloat(cs.top) + (unit.clientTop || 0);
    const fw = parseFloat(cs.width), fh = parseFloat(cs.height);
    if ([fl, ft, fw, fh].some((v) => Number.isNaN(v))) return null;
    const W = unit.offsetWidth, H = unit.offsetHeight;
    if (!W || !H) return null;
    const r = unit.getBoundingClientRect();
    const kx = r.width / W, ky = r.height / H;
    const parse = (v) => {
      const t = (v || '0px').trim().split(/\s+/);
      return [(parseFloat(t[0]) || 0) * kx, (parseFloat(t.length > 1 ? t[1] : t[0]) || 0) * ky];
    };
    return {
      left: r.left + fl * kx, top: r.top + ft * ky,
      right: r.left + (fl + fw) * kx, bottom: r.top + (ft + fh) * ky,
      radii: [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map(parse),
      kx, ky,
    };
  };
});
const mm0 = await readMemo(p2, '双栏混排');
const cdp = await ctx2.newCDPSession(p2);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});

// ② 长按原子块拾起 + 跟指误差（中心点采样 5 点；scale
// 关于中心对称，中心不受拾起缩放影响）
await scrollUnitIntoView(p2, 'tc01');
const a1 = await unitRect(p2, 'tc01');
const a1surf = await p2.evaluate(() => {
  const el = document.querySelector('[data-wrapbid="tc01"]');
  return el ? window.__surfResolve(el) : null;
});
const dir = a1.cy > 500 ? -1 : 1;
await touch('touchStart', a1.cx, a1.cy);
await p2.waitForTimeout(680);
ok('② 长按 480ms 后拾起', (await liftedBid(p2)) === 'tc01');
// ⑧ 拾起缩放（视觉面口径）：等弹簧落定后量 computed
// transform 的双轴缩放分量——scale 应为 (视觉面边长
// -2×4px)/面边长（极小边按轴钳制 ≥0.9）；拾起框
// （::before）↔ 视觉面渲染矩形的四边间隙应恒为 4px、
// 两两差 ≤1px（偏心抓握的补偿不变量在 ⑤b 双轴判定）。
await p2.waitForTimeout(450);
const liftGeom = await p2.evaluate(() => {
  const el = document.querySelector('[data-wrapbid="tc01"]');
  if (!el) return null;
  const cs = getComputedStyle(el);
  const m = new DOMMatrixReadOnly(cs.transform);
  return { sx: m.a, sy: m.d, post: window.__surfResolve(el), frame: window.__frameRect(el) };
});
ok('⑧ 拾起双轴 scale = 视觉面等距内收（4px/面边，钳制 ≥0.9）', !!liftGeom && !!a1surf
  && Math.abs(liftGeom.sx - Math.max((a1surf.rect.width - 8) / a1surf.rect.width, 0.9)) <= 0.01
  && Math.abs(liftGeom.sy - Math.max((a1surf.rect.height - 8) / a1surf.rect.height, 0.9)) <= 0.01,
  liftGeom && a1surf ? `sx=${liftGeom.sx.toFixed(3)} sy=${liftGeom.sy.toFixed(3)} exp=${Math.max((a1surf.rect.width - 8) / a1surf.rect.width, 0.9).toFixed(3)}/${Math.max((a1surf.rect.height - 8) / a1surf.rect.height, 0.9).toFixed(3)}` : 'no el');
const gaps1 = liftGeom && liftGeom.frame ? [
  liftGeom.post.rect.left - liftGeom.frame.left, liftGeom.frame.right - liftGeom.post.rect.right,
  liftGeom.post.rect.top - liftGeom.frame.top, liftGeom.frame.bottom - liftGeom.post.rect.bottom,
] : null;
ok('⑧ 宽卡拾起框↔视觉面四边间隙 = 4px（两两差 ≤1px）', !!gaps1
  && Math.max(...gaps1) - Math.min(...gaps1) <= 1
  && gaps1.every((g) => g >= 3 && g <= 5),
  gaps1 ? 'gaps=' + gaps1.map((g) => g.toFixed(2)).join('/') + ` surf=${liftGeom.post.rect.width.toFixed(0)}x${liftGeom.post.rect.height.toFixed(0)}` : 'no el');
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
const diag2 = await waitDiag(p2, (t) => t.includes('drag pickup') && t.includes('drag drop'));
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
await p2.waitForTimeout(350);
// ⑧ 图片块定形（视觉面口径）：拾起框（::before）半径
// = 图片渲染半径 + 4（同心嵌套，四角双轴 ≤1px）；框
// ↔ 图片渲染矩形四边间隙 = 4px、两两差 ≤1px。
const imgGeom = await p2.evaluate(() => {
  const el = document.querySelector('.mn-lifted');
  if (!el) return null;
  return { post: window.__surfResolve(el), frame: window.__frameRect(el) };
});
let imgRadMax = null;
if (imgGeom && imgGeom.frame) {
  const ds = [];
  for (let i = 0; i < 4; i++) {
    ds.push(Math.abs(imgGeom.frame.radii[i][0] - (imgGeom.post.corners[i][0] * imgGeom.frame.kx + 4)));
    ds.push(Math.abs(imgGeom.frame.radii[i][1] - (imgGeom.post.corners[i][1] * imgGeom.frame.ky + 4)));
  }
  imgRadMax = Math.max(...ds);
}
ok('⑧ 图片块拾起框半径 = 图片半径 + 4（同心嵌套）', imgRadMax !== null && imgRadMax <= 1,
  imgRadMax !== null ? 'Δmax=' + imgRadMax.toFixed(2) : 'no el');
const gaps5 = imgGeom && imgGeom.frame ? [
  imgGeom.post.rect.left - imgGeom.frame.left, imgGeom.frame.right - imgGeom.post.rect.right,
  imgGeom.post.rect.top - imgGeom.frame.top, imgGeom.frame.bottom - imgGeom.post.rect.bottom,
] : null;
ok('⑧ 图片块拾起框↔视觉面四边间隙 = 4px（两两差 ≤1px）', !!gaps5
  && Math.max(...gaps5) - Math.min(...gaps5) <= 1
  && gaps5.every((g) => g >= 3 && g <= 5),
  gaps5 ? 'gaps=' + gaps5.map((g) => g.toFixed(2)).join('/') : 'no el');
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
const diagAfter = await waitDiag(p2, (t) => t.includes('drag cancel'));
ok('⑤ Diag 有 drag cancel', diagAfter.includes('drag cancel'));

// ⑤b 抓握点平移补偿（视觉面口径）：偏心抓握（30%/
// 35%）拾起落定后，抓握点在浮块内的局部比例与原位一
// 致——以视觉面中心缩放产生的位移已由 translate 补
// 偿承担（补偿对任意参考系同立：被抓点在仿射下不动），
// 缩放归面心、跟随归平移的解耦在此双轴判定。
await scrollUnitIntoView(p2, 'tc05');
const a5b = await unitRect(p2, 'tc05');
const g5x = a5b.x + a5b.w * 0.3;
const g5y = a5b.y + a5b.h * 0.35;
await touch('touchStart', g5x, g5y);
await p2.waitForTimeout(680 + 450);
const frac5 = await p2.evaluate(([gx, gy]) => {
  const el = document.querySelector('.mn-lifted');
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { fx: (gx - r.left) / r.width, fy: (gy - r.top) / r.height };
}, [g5x, g5y]);
ok('⑧ 偏心抓握点局部比例不漂移（双轴，补偿成立）', !!frac5
  && Math.abs(frac5.fx - 0.3) <= 0.02 && Math.abs(frac5.fy - 0.35) <= 0.02,
  frac5 ? `frac=${frac5.fx.toFixed(3)},${frac5.fy.toFixed(3)} exp=0.300,0.350` : 'no el');
await touch('touchCancel');
await p2.waitForTimeout(600);

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

// ⑧ 定形（卡片）：tc07 链接卡长按拾起，拾起框半径 =
// 卡面渲染半径 + 4（同心嵌套），不套统一外形。
await scrollUnitIntoView(p2, 'tc07');
const a7 = await unitRect(p2, 'tc07');
await touch('touchStart', a7.cx, a7.cy);
await p2.waitForTimeout(680);
ok('⑧ 前置：tc07 已拾起', (await liftedBid(p2)) === 'tc07');
await p2.waitForTimeout(350);
const cardGeom = await p2.evaluate(() => {
  const el = document.querySelector('.mn-lifted');
  if (!el) return null;
  return { post: window.__surfResolve(el), frame: window.__frameRect(el) };
});
let cardRadMax = null;
if (cardGeom && cardGeom.frame) {
  const ds = [];
  for (let i = 0; i < 4; i++) {
    ds.push(Math.abs(cardGeom.frame.radii[i][0] - (cardGeom.post.corners[i][0] * cardGeom.frame.kx + 4)));
    ds.push(Math.abs(cardGeom.frame.radii[i][1] - (cardGeom.post.corners[i][1] * cardGeom.frame.ky + 4)));
  }
  cardRadMax = Math.max(...ds);
}
ok('⑧ 卡片块拾起框半径 = 卡面半径 + 4（同心嵌套）', cardRadMax !== null && cardRadMax <= 1,
  cardRadMax !== null ? 'Δmax=' + cardRadMax.toFixed(2) : 'no el');
await touch('touchCancel');
await p2.waitForTimeout(600);
ok('⑧ 卡片取消后无残留拾起态', (await liftedBid(p2)) === null);
await ctx2.close();

await browser.close();
L(fails === 0 ? 'DRAG PICKUP ALL PASS' : `DRAG PICKUP ${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
