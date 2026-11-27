// 探针（批 3 blocks.rs 项）：C-28 引用式链接/原始 HTML/
// 缩进代码、C-21 Callout 未知类型标题、C-23 失焦 guards、
// C-27 公式错误态包裹、D-17 图库几何（2 列/366/radius22/
// 内层无叠加边距/空态双格）、C-11/C-12 link-card div 化与
// 点击委托、C-14 图文卡占位盒与几何对齐（160px/卡高/
// radius/选中轮廓跟随）、C-15 混排占位 div + SVG 图标、C-10 附件
// 图 alt、C-03 标题缺省级 2 与 h5 不钳、C-04 quote
// blockquote>div、C-05 todo aria、MD-C10 围栏跨块合并。
// C-02（BlockView 空段 <br>）无实机渲染面（编辑器段落走
// EditableDiv），按构造验证，不在本探针内断言。
// 探针纪律（防竞速，2026-11-27 triage 定案）：凡断言涉及
// 线上异步补拉（hydrate）的卡面状态，必须先拦截外部元数据
// 源使状态确定化——link-card 打开时向线上元数据 Worker 补
// 拉、约 0.4s 即可翻 ready，把 err 态断言建在活网返回值上
// 必然与补拉竞速（网络越快越红）。本探针在建 context 后即
// 全程拦截 mynote.overtrees.workers.dev（见下方 ctx.route），
// err 态经「resolve -> error」确定落定；全探针无其他断言依
// 赖该 Worker（夹具无 musicCard、其余段不触发卡片解析）。
// Chromium 口径。用法：node probe_batch3.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const approx = (a, b, tol) => Math.abs(a - b) <= tol;

const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xFFFFFFFF; for (const b of buf) c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zipStore(files) {
  const enc = new TextEncoder(); const chunks = []; const central = []; let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name); const data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
    const crc = crc32(data); const size = data.length;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
    lh.setUint32(14, crc, true); lh.setUint32(18, size, true); lh.setUint32(22, size, true); lh.setUint16(26, name.length, true);
    chunks.push(Buffer.from(lh.buffer), Buffer.from(name), Buffer.from(data));
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, 0x0800, true);
    ch.setUint32(16, crc, true); ch.setUint32(20, size, true); ch.setUint32(24, size, true); ch.setUint16(28, name.length, true); ch.setUint32(42, offset, true);
    central.push(Buffer.from(ch.buffer), Buffer.from(name)); offset += 30 + name.length + size;
  }
  const cdSize = central.reduce((a, c) => a + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}

const ts = new Date().toISOString();
const para = (id, text) => ({ id, type: 'paragraph', children: [{ text }] });
const memo = (id, title, doc) => ({ id, title, pinned: false, createdAt: ts, updatedAt: ts, doc });
const PNG1_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const png1 = Buffer.from(PNG1_B64, 'base64');
const DATA_PNG = 'data:image/png;base64,' + PNG1_B64;
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    memo('b3-md', '批3MD', [
      para('m-html', '**粗** 前 <b>粗</b> 与 <u>下划</u> 及 <span>普通</span> 尾'),
      para('m-js', '**粗** 危 <a href="javascript:alert(1)">点我</a> 险'),
      para('m-script', '**粗** x <script>alert(1)</script> y'),
      para('m-ref', '**粗** [点此][ex] 与 [Example] 链\n\n[ex]: https://example.com\n\n[example]: https://example.org'),
      para('m-indent', '    let a = 1;\n    let b = 2;'),
      para('m-callout', '> [!FOO]\n> 正文内容'),
      para('m-matherr', '前 $\\frac{1}$ 后'),
      para('m-mathok', '前 $x^2$ 后'),
    ]),
    memo('b3-guard', '批3Guards', [
      para('g1', '> a'),
      para('g2', '> 引用文字'),
      para('g3', '锚点段'),
    ]),
    memo('b3-gal', '批3图库', [
      { id: 'gal-full', type: 'gallery', attrs: { items: [{ url: DATA_PNG }, { url: DATA_PNG }, { url: DATA_PNG }, { url: DATA_PNG }] }, children: [] },
      { id: 'gal-empty', type: 'gallery', attrs: { items: [] }, children: [] },
    ]),
    memo('b3-link', '批3链接卡', [
      { id: 'lc-ready', type: 'link-card', url: 'https://example.com/page', meta: { title: '示例标题', source: 'Example' }, children: [{ text: '' }] },
      { id: 'lc-err', type: 'link-card', url: 'example.com/path', meta: null, children: [{ text: '' }] },
      { id: 'lc-load', type: 'link-card', url: 'https://example.com', status: 'loading', meta: null, children: [{ text: '' }] },
      { id: 'lc-blocked', type: 'link-card', url: 'javascript:alert(1)', meta: { title: '危险卡' }, children: [{ text: '' }] },
    ]),
    memo('b3-cards', '批3图文卡', [
      { id: 'c-itc', type: 'imgTextCard', attrs: { fileId: '' }, children: [{ text: '点击输入文字' }] },
      { id: 'c-itr', type: 'imageTextRow', attrs: { fileId: '' }, children: [{ text: '点击输入说明文字' }] },
      { id: 'c-att', type: 'attachment', fileId: 'att1', status: 'done', image: true, children: [{ text: '' }] },
      { id: 'c-h2', type: 'heading', children: [{ text: '缺省标题' }] },
      { id: 'c-h5', type: 'heading', attrs: { level: 5 }, children: [{ text: '五级标题' }] },
      { id: 'c-q', type: 'quote', children: [{ text: '引用文' }] },
      { id: 'c-todo1', type: 'todo', attrs: { checked: true }, children: [{ text: '待办事项一' }] },
      { id: 'c-todo2', type: 'todo', attrs: { checked: false }, children: [{ text: '待办事项二' }] },
    ]),
    memo('b3-fence', '批3围栏', [
      para('f1', '```rust'),
      para('f2', 'fn main() {}'),
      para('f3', '```'),
      para('f4', '后续段落'),
    ]),
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { att1: { name: '截图.png' } } }) },
  { name: 'attachments/att1', data: png1 },
]);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
// 元数据 Worker 全程拦截（文件头「探针纪律」）：须在打开
// b3-link 之前生效，使 lc-err/lc-load 的补拉确定失败、err
// 态落定，C-11/C-12 断言口径不变（仍断 err 呈现与标题回退）。
await ctx.route('**://mynote.overtrees.workers.dev/**', (r) => r.abort());
await ctx.addInitScript(() => {
  window.__opened = [];
  window.open = (u) => { window.__opened.push(String(u)); return null; };
});
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'batch3.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });

async function openMemo(id) {
  await page.goto(base + '?open=' + id, { waitUntil: 'load' });
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(800);
}
const inBlock = (bid, fn) => page.evaluate(([b, f]) => {
  const hit = document.querySelector('.md-hit[data-bids="' + b + '"]') || document.querySelector('[data-wrapbid="' + b + '"]') || document.querySelector('[data-bid="' + b + '"]');
  if (!hit) return null;
  return (new Function('el', 'return (' + f + ')(el)'))(hit);
}, [bid, fn.toString()]);
async function clickBlockPt(bid, fy = 0.5) {
  const pt = await page.evaluate(([b, f]) => {
    const el = document.querySelector('[data-bid="' + b + '"]') || document.querySelector('[data-wrapbid="' + b + '"]');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height * f };
  }, [bid, fy]);
  if (pt) await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(350);
}

// ---------- A. C-28 / C-21 / C-27 预览面 ----------
await openMemo('b3-md');
{
  const html = await inBlock('m-html', (el) => {
    const pv = el.querySelector('.md-preview') || el;
    return {
      strong: pv.querySelectorAll('strong').length,
      u: pv.querySelector('u') ? pv.querySelector('u').textContent : null,
      text: pv.textContent,
    };
  });
  ok('C-28 HTML <b> 映射 strong', html && html.strong >= 2, JSON.stringify(html));
  ok('C-28 HTML <u> 映射 u 元素', html && html.u === '下划');
  ok('C-28 HTML <span> 剥标签留文本', html && html.text.includes('普通') && !html.text.includes('<span>'));
  const js = await inBlock('m-js', (el) => {
    const pv = el.querySelector('.md-preview') || el;
    return { anchors: pv.querySelectorAll('a').length, text: pv.textContent };
  });
  ok('C-28 危险 href 降级不可点（无 a 元素）', js && js.anchors === 0 && js.text.includes('点我'), JSON.stringify(js));
  const sc = await inBlock('m-script', (el) => (el.querySelector('.md-preview') || el).textContent);
  ok('C-28 <script> 连内容丢弃', sc && !sc.includes('alert') && sc.includes('x') && sc.includes('y'), sc);
  const ref = await inBlock('m-ref', (el) => {
    const pv = el.querySelector('.md-preview') || el;
    const as = [...pv.querySelectorAll('a')].map((a) => [a.getAttribute('href'), a.textContent]);
    return { as, text: pv.textContent };
  });
  ok('C-28 引用式链接 [text][ref] 解析', ref && ref.as.some(([h, t]) => h === 'https://example.com' && t === '点此'), JSON.stringify(ref));
  ok('C-28 快捷引用 [label] 解析', ref && ref.as.some(([h, t]) => h === 'https://example.org' && t === 'Example'));
  ok('C-28 定义行不渲染', ref && !ref.text.includes('[ex]:'));
  const ind = await inBlock('m-indent', (el) => {
    const pv = el.querySelector('.md-preview') || el;
    const pre = pv.querySelector('pre');
    return { pre: pre ? pre.textContent : null, li: pv.querySelectorAll('li').length };
  });
  ok('C-28 缩进代码块成 pre', ind && ind.pre && ind.pre.includes('let a = 1;') && ind.pre.includes('let b = 2;') && ind.li === 0, JSON.stringify(ind));
  const co = await inBlock('m-callout', (el) => {
    const t = (el.querySelector('.md-preview') || el).querySelector('.callout-title');
    return t ? t.textContent : null;
  });
  ok('C-21 未知 Callout 标题回退类型原文', co === 'FOO', co);
  const me = await inBlock('m-matherr', (el) => {
    const pv = el.querySelector('.md-preview') || el;
    const w = pv.querySelector('.math-inline');
    return { wrapped: !!w, hasSource: !!(w && w.querySelector('.math-source')) };
  });
  ok('C-27 行内公式错误态带 .math-inline 包裹', me && me.wrapped && me.hasSource, JSON.stringify(me));
  const mo = await inBlock('m-mathok', (el) => {
    const pv = el.querySelector('.md-preview') || el;
    const w = pv.querySelector('.math-inline');
    return { wrapped: !!w, hasSource: !!(w && w.querySelector('.math-source')) };
  });
  ok('C-27 行内公式成功态同构包裹（无源码兜底）', mo && mo.wrapped && !mo.hasSource, JSON.stringify(mo));
}

// ---------- B. C-23 失焦 guards ----------
// 口径说明：守卫作用于「段落源码文本 → 预览」的分类路径
// （存量段落打开/失焦时的渲染决策）。键入 "> " 本身走输
// 入期规则直接转 quote 块（既有行为，非本批范围），故本
// 组以存量段落文本断言分类结果。
await openMemo('b3-guard');
{
  const g1 = await page.evaluate(() => {
    const ed = document.querySelector('[data-bid="g1"]');
    const hit = document.querySelector('.md-hit[data-bids="g1"]');
    return { editable: !!ed, text: ed ? ed.textContent : null, converted: !!hit };
  });
  ok('C-23 极短引用（> a）不转预览、保持源码段', g1.editable && !g1.converted && (g1.text || '').includes('> a'), JSON.stringify(g1));
  const g2 = await page.evaluate(() => {
    const hit = document.querySelector('.md-hit[data-bids="g2"]');
    const bq = hit ? hit.querySelector('.md-preview blockquote') : null;
    return { converted: !!hit, bqText: bq ? bq.textContent : null };
  });
  ok('C-23 正常引用转预览（对照）', g2.converted && (g2.bqText || '').includes('引用文字'), JSON.stringify(g2));
}

// ---------- C. D-17 图库几何 ----------
await openMemo('b3-gal');
{
  const g = await page.evaluate(() => {
    const wrap = document.querySelector('[data-wrapbid="gal-full"]');
    const atomic = wrap.querySelector('.atomic');
    const grid = wrap.querySelector('.gallery-grid');
    const imgs = [...grid.querySelectorAll('img')].map((im) => { const r = im.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, radius: getComputedStyle(im).borderTopLeftRadius }; });
    const ar = atomic.getBoundingClientRect(); const gr = grid.getBoundingClientRect();
    return { imgs, gridInset: gr.x - ar.x, atomicX: ar.x };
  });
  ok('D-17 图库 2 列（首行两图、第三图换行）', g.imgs.length === 4 && approx(g.imgs[0].y, g.imgs[1].y, 1) && g.imgs[1].x > g.imgs[0].x && g.imgs[2].y > g.imgs[0].y + 100, JSON.stringify(g.imgs));
  ok('D-17 图高 366 / radius 22', g.imgs.every((im) => approx(im.h, 366, 1) && im.radius === '22px'), JSON.stringify(g.imgs[0]));
  ok('D-17 网格层无叠加内距（与外层齐平）', Math.abs(g.gridInset) < 2, 'inset=' + g.gridInset);
  const e = await page.evaluate(() => {
    const wrap = document.querySelector('[data-wrapbid="gal-empty"]');
    const tiles = [...wrap.querySelectorAll('.gallery-empty-tile')].map((t) => { const r = t.getBoundingClientRect(); return { h: r.height, cls: t.className, label: t.querySelector('.gallery-empty-label')?.textContent }; });
    return tiles;
  });
  ok('D-17 空态双占位格 366 高', e.length === 2 && e.every((t) => approx(t.h, 366, 1)), JSON.stringify(e));
  ok('D-17 空态文案 长按编辑添加/多张图片 + alt 格', e[0] && e[0].label === '长按编辑添加' && e[1] && e[1].label === '多张图片' && e[1].cls.includes('alt'), JSON.stringify(e));
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.waitForTimeout(600);
  const wide = await page.evaluate(() => {
    const body = document.querySelector('.editor-body');
    const wrap = document.querySelector('[data-wrapbid="gal-full"]');
    const atomic = wrap.querySelector('.atomic');
    const br = body.getBoundingClientRect(); const ar = atomic.getBoundingClientRect();
    const imgs = [...wrap.querySelectorAll('.gallery-grid img')].map((im) => im.getBoundingClientRect().height);
    return { inset: ar.x - br.x, hs: imgs };
  });
  ok('D-17 宽屏外层内缩 36/侧', approx(wide.inset, 36, 1.5), 'inset=' + wide.inset);
  ok('D-17 宽屏图高仍 366', wide.hs.every((h) => approx(h, 366, 1)), JSON.stringify(wide.hs));
  await page.setViewportSize({ width: 393, height: 852 });
  await page.waitForTimeout(400);
}

// ---------- D. C-11 / C-12 link-card ----------
await openMemo('b3-link');
{
  const ready = await page.evaluate(() => {
    const wrap = document.querySelector('[data-wrapbid="lc-ready"]');
    const card = wrap.querySelector('.link-card-block');
    return card ? { tag: card.tagName, dataUrl: card.getAttribute('data-url') } : null;
  });
  ok('C-11 ready 卡容器为 div + data-url', ready && ready.tag === 'DIV' && ready.dataUrl === 'https://example.com/page', JSON.stringify(ready));
  await page.evaluate(() => { window.__opened = []; });
  await clickBlockPt('lc-ready');
  const opened = await page.evaluate(() => window.__opened);
  ok('C-11 点击 ready 卡经委托新窗打开', JSON.stringify(opened) === JSON.stringify(['https://example.com/page']), JSON.stringify(opened));
  const err = await page.evaluate(() => {
    const wrap = document.querySelector('[data-wrapbid="lc-err"]');
    const card = wrap.querySelector('.link-card-err');
    return card ? { tag: card.tagName, title: card.querySelector('.lkc-title')?.textContent } : null;
  });
  ok('C-11 err 无 scheme 标题 = 完整 URL', err && err.tag === 'DIV' && err.title === 'example.com/path', JSON.stringify(err));
  const load = await page.evaluate(() => ({
    skeleton: !!document.querySelector('[data-wrapbid="lc-load"] .link-card-skeleton'),
    errCard: !!document.querySelector('[data-wrapbid="lc-load"] .link-card-err'),
  }));
  ok('C-12 无 loading 骨架态（落 err 卡）', !load.skeleton && load.errCard, JSON.stringify(load));
  const blocked = await page.evaluate(() => {
    const card = document.querySelector('[data-wrapbid="lc-blocked"] .link-card-block');
    return card ? card.getAttribute('data-url') : null;
  });
  ok('C-11 被拦 URL 的 data-url 为空', blocked === '', JSON.stringify(blocked));
  await page.evaluate(() => { window.__opened = []; });
  await clickBlockPt('lc-blocked');
  const opened2 = await page.evaluate(() => window.__opened);
  ok('C-11 被拦卡点击不打开', opened2.length === 0, JSON.stringify(opened2));
}

// ---------- E. C-14 / C-15 / C-10 / C-03 / C-04 / C-05 ----------
await openMemo('b3-cards');
{
  const itc = await page.evaluate(() => {
    const wrap = document.querySelector('[data-wrapbid="c-itc"]');
    const card = wrap.querySelector('.img-text-card');
    const ph = card.querySelector('.itc-placeholder');
    const txt = card.querySelector('.itc-text');
    const cr = card.getBoundingClientRect();
    return {
      phH: ph ? ph.getBoundingClientRect().height : null,
      phText: ph ? ph.textContent : null,
      phSvg: ph ? !!ph.querySelector('svg') : false,
      cardH: cr.height,
      radius: getComputedStyle(card).borderTopLeftRadius,
      role: txt.getAttribute('role'), tab: txt.getAttribute('tabindex'), aria: txt.getAttribute('aria-label'),
    };
  });
  // 文案断言随图标集统一更新（2026-11-25 用户定案 emoji→SVG）：
  // 📷 字面退役，占位 = SVG 图标 + 文案「长按打开菜单，点「编辑」添加图片」。
  ok('C-14 imgTextCard 占位盒 160px + SVG 图标 + 文案', itc.phH !== null && approx(itc.phH, 160, 1) && itc.phSvg && (itc.phText || '').includes('长按打开菜单，点「编辑」添加图片'), JSON.stringify(itc));
  ok('C-14 空卡总高与原版量测一致（≈209.8）', approx(itc.cardH, 209.8, 3), 'h=' + itc.cardH);
  ok('C-14 卡圆角 22 + 文本区 role/tabindex/aria', itc.radius === '22px' && itc.role === 'button' && itc.tab === '0' && itc.aria === '查看完整文本', JSON.stringify(itc));
  // 选中态：点占位盒中心选中卡。原断言「选中轮廓圆角跟随
  // 卡片 22px」已失去对象——该轮廓（.blk-wrap.sel 描边）按
  // 用户 2026-11-24 蓝框裁定整体删除；改断言选中态在场
  // （SelBlock 状态机保留）且 computed outline 为 none。
  const phBox = await page.evaluate(() => {
    const ph = document.querySelector('[data-wrapbid="c-itc"] .itc-placeholder');
    const r = ph.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  await page.mouse.click(phBox.x, phBox.y);
  await page.waitForTimeout(450);
  const sel = await page.evaluate(() => {
    const wrap = document.querySelector('[data-wrapbid="c-itc"]');
    return { cls: wrap.className, outline: getComputedStyle(wrap).outlineStyle };
  });
  ok('C-14 选中态在场且无描边（蓝框已删，2026-11-24 裁定）', sel.cls.includes('sel') && sel.outline === 'none', JSON.stringify(sel));
  const itr = await page.evaluate(() => {
    const wrap = document.querySelector('[data-wrapbid="c-itr"]');
    const ph = wrap.querySelector('.itr-placeholder');
    const txt = wrap.querySelector('.itr-text');
    return { tag: ph ? ph.tagName : null, svg: ph ? !!ph.querySelector('svg') : false, role: txt.getAttribute('role'), tab: txt.getAttribute('tabindex'), aria: txt.getAttribute('aria-label') };
  });
  // 同 C-14 口径：📷 字面随图标集统一退役，改断言 SVG 在场。
  ok('C-15 混排占位为 div + SVG 图标', itr.tag === 'DIV' && itr.svg, JSON.stringify(itr));
  ok('C-14 混排文本区 role/tabindex/aria', itr.role === 'button' && itr.tab === '0' && itr.aria === '查看完整文本');
  await page.waitForSelector('[data-wrapbid="c-att"] img.blk-media', { timeout: 10000 }).catch(() => {});
  const att = await page.evaluate(() => {
    const img = document.querySelector('[data-wrapbid="c-att"] img.blk-media');
    return img ? img.getAttribute('alt') : null;
  });
  ok('C-10 附件图 alt = manifest 文件名', att === '截图.png', JSON.stringify(att));
  const hs = await page.evaluate(() => ({
    h2: document.querySelector('[data-bid="c-h2"]')?.className || '',
    h5: document.querySelector('[data-bid="c-h5"]')?.className || '',
  }));
  ok('C-03 标题缺省级 = blk-h2', hs.h2.includes('blk-h2'), hs.h2);
  ok('C-03 h5 不被钳制', hs.h5.includes('blk-h5'), hs.h5);
  const q = await page.evaluate(() => {
    const bq = document.querySelector('blockquote.blk-quote');
    const inner = bq ? bq.querySelector(':scope > div') : null;
    return { exists: !!bq, innerBid: inner ? inner.getAttribute('data-bid') : null };
  });
  ok('C-04 quote 结构 blockquote.blk-quote > div', q.exists && q.innerBid === 'c-q', JSON.stringify(q));
  const todos = await page.evaluate(() => {
    const get = (bid) => {
      const ed = document.querySelector('[data-bid="' + bid + '"]');
      const row = ed ? ed.closest('.todo-row') : null;
      const btn = row ? row.querySelector('button.todo-checkbox') : null;
      return btn ? { role: btn.getAttribute('role'), checked: btn.getAttribute('aria-checked'), label: btn.getAttribute('aria-label') } : null;
    };
    return { t1: get('c-todo1'), t2: get('c-todo2') };
  });
  ok('C-05 待办钮 aria（checked）', todos.t1 && todos.t1.role === 'checkbox' && todos.t1.checked === 'true' && todos.t1.label === '待办事项一', JSON.stringify(todos));
  ok('C-05 待办钮 aria（unchecked）', todos.t2 && todos.t2.checked === 'false' && todos.t2.label === '待办事项二');
}

// ---------- F. MD-C10 围栏跨块合并 ----------
await openMemo('b3-fence');
{
  const f = await page.evaluate(() => {
    const hits = [...document.querySelectorAll('.md-hit')].map((h) => h.getAttribute('data-bids'));
    const previews = [...document.querySelectorAll('.md-preview')].map((p) => p.textContent);
    return {
      hits,
      f2Editable: !!document.querySelector('[data-bid="f2"]'),
      f4: !!document.querySelector('[data-bid="f4"]'),
      codeText: previews.find((t) => t.includes('fn main()')) || null,
    };
  });
  ok('MD-C10 拆段围栏打开后合并为一块预览', f.hits.includes('f1') && !f.f2Editable && f.codeText && f.codeText.includes('fn main() {}'), JSON.stringify(f));
  ok('MD-C10 合并不断链后续段', f.f4);
}

await browser.close();
L(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
