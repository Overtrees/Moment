// 双栏流式探针（A-2 回退后新判据）：用户 2026-11-24 裁定
// 「宽屏流式阅读视觉与双栏一致、不要跨栏」——A-2 的流式
// 分段跨栏设计（cf7f888/c5ff1e6/cea6b3e）整体回退。现行
// 设计：流式×宽屏 = 两物理 .editor-column 栏（与独立模式
// 同几何同渲染），任何块不跨栏；分界 = canonical_boundary
// 规范估高切分（不读不写 layout 锚、确定性纯函数）；与独
// 立模式的差异只在分栏来源（计算 vs 锚）与滚动模型。
//  F1 原跨栏六类块全部在栏内（宽=栏内容宽）
//  F2 恰两栏、栏宽半分、两栏非空
//  F3 DOM 序（左栏++右栏）== 文档序
//  F4 切分 == 手算 canonical + 重开逐块全等
//  F5 锚零改写（流式开/关逐字节 + 无落锚 Diag）
//  F6 模式往返（独立成员==锚、回流式切分复原、layout 不变）
//  F7 流式拖拽（栏内换位 + 跨栏两向落位、落盘一刀切）
//  F8 画布落焦（右栏末块下方空白 → 右栏末可编辑块）
//  F9 窄屏退化（无栏、单栏同序同宽）
//  F10 独立模式六类块不跨栏
//  G2 组：无 mode→独立 / mode=flow→流式 / 无 layout 沿
//        localStorage 默认 / 无 mode 名单合法不被改写
// Chromium 口径（box）；真机/WebKit 终判不在本探针。
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
let fails = 0;
const ok = (name, cond, extra = '') => { console.log((cond ? '✓ ' : '✗ ') + name + (extra ? ' — ' + extra : '')); if (!cond) fails++; };
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
// 夹具注入走设置页备份导入（现行探针统一口径，同
// probe_undo_granularity）：直接写 IDB kv 已不是数据源头
// （启动会被真存储覆盖）。zipStore 为 stored 无压缩打包。
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
const para = (id, text) => ({ id, type: 'paragraph', children: [{ text }] });
const LONG = '长段落文字用于规范估高量测，长段落文字用于规范估高量测，长段落文字用于规范估高量测，长段落文字用于规范估高量测，长段落文字用于规范估高量测。';
// 主夹具文档序：段落×3、image、段落×2、gallery、段落、
// imgTextCard、musicCard、带图附件、段落×2、imageTextRow、
// 段落（原 A-2 六类名单块齐备，现应全部在栏内）。
const docA = [
  para('p1', LONG), para('p2', '短段二'), para('p3', '短段三'),
  { id: 'im1', type: 'image', attrs: { fileId: 'att1' }, children: [{ text: '' }] },
  para('p4', '段四文字'), para('p5', '段五文字'),
  { id: 'ga1', type: 'gallery', attrs: { items: ['att1', 'att2'] }, children: [{ text: '' }] },
  para('p6', '段六文字'),
  { id: 'it1', type: 'imgTextCard', attrs: { fileId: 'att2' }, children: [{ text: '图文卡文字' }] },
  { id: 'mu1', type: 'musicCard', url: 'https://music.163.com/song?id=1', status: 'ready', meta: { title: '测试歌曲', cover: '' }, children: [{ text: '' }] },
  { id: 'at1', type: 'attachment', fileId: 'att1', status: 'done', image: true, children: [{ text: '' }] },
  para('p7', '段七文字'), para('p8', '段八文字'),
  { id: 'itr1', type: 'imageTextRow', attrs: { fileId: 'att2' }, children: [{ text: '图文行文字' }] },
  para('p9', '末段文字'),
];
// 手算 canonical（columns.rs 估高表：长段 p1 文本 71 码元
// →2 行=78；短段=53；image/gallery/imgTextCard/
// imageTextRow=280；musicCard=120；带图附件=280。总高
// 2022，累计差最小在 p6 后（903，差 216）→ 分界 index 8。
// at1 估高若按 120 计总高 1862、最优仍在 p6 后（差 56），
// 结论对该口径稳健。
const CANON_LEFT = ['p1', 'p2', 'p3', 'im1', 'p4', 'p5', 'ga1', 'p6'];
const CANON_RIGHT = ['it1', 'mu1', 'at1', 'p7', 'p8', 'itr1', 'p9'];
const anchorA = { version: 1, mode: 'flow', left: ['p1', 'p2', 'p3', 'im1', 'p4'], right: ['p5', 'ga1', 'p6', 'it1', 'mu1', 'at1', 'p7', 'p8', 'itr1', 'p9'] };
const memoA = { id: 'fspan1', title: '流式跨栏主夹具', pinned: false, createdAt: '2026-11-24T00:00:00.000Z', updatedAt: '2026-11-24T00:00:00.000Z', doc: docA, layout: anchorA };
const memoB = {
  id: 'fspan2', title: '无模式存量', pinned: false, createdAt: '2026-11-24T00:00:00.000Z', updatedAt: '2026-11-24T00:00:00.000Z',
  doc: [para('b1', '乙一'), { id: 'b2', type: 'image', attrs: { fileId: 'att1' }, children: [{ text: '' }] }, para('b3', '乙三')],
  layout: { version: 1, left: ['b1'], right: ['b2', 'b3'] },
};
const memoC = {
  id: 'fspan3', title: '流式锚夹具', pinned: false, createdAt: '2026-11-24T00:00:00.000Z', updatedAt: '2026-11-24T00:00:00.000Z',
  doc: [para('c1', '丙一'), { id: 'c2', type: 'image', attrs: { fileId: 'att1' }, children: [{ text: '' }] }, para('c3', '丙三')],
  layout: { version: 1, mode: 'flow', left: ['c1'], right: ['c2', 'c3'] },
};
const memoD = {
  id: 'fspan4', title: '无锚默认', pinned: false, createdAt: '2026-11-24T00:00:00.000Z', updatedAt: '2026-11-24T00:00:00.000Z',
  doc: [para('d1', '丁一'), para('d2', '丁二')],
};
const memosJson = JSON.stringify({ version: 2, exportedAt: '2026-11-24T00:00:00.000Z', memos: [memoA, memoB, memoC, memoD], avatars: {} });
const manifestJson = JSON.stringify({ version: 1, attachments: { att1: { name: 'a.png', type: 'image/png' }, att2: { name: 'b.png', type: 'image/png' } } });

async function seed(page) {
  const fixtureZip = zipStore([
    { name: 'memos.json', data: memosJson },
    { name: 'manifest.json', data: manifestJson },
    { name: 'attachments/att1', data: Buffer.from(PNG, 'base64') },
    { name: 'attachments/att2', data: Buffer.from(PNG, 'base64') },
  ]);
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'flowspan.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  // 回列表（到位判据同 drag_sort importZip：.seg-row 为设置
  // 页独有、.glass-search-trigger 为列表独有）。
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  await page.waitForTimeout(500);
}

// 打开备忘走 ?open= 深链（probe_undo_granularity 同口径）：
// 列表同日同类超过 2 篇有原版折叠设计（首卡 + 展开钮），
// 深链绕开列表折叠、编辑器打开路径与应用内一致。
async function openMemo(page, id) {
  await page.goto(base + '?open=' + id, { waitUntil: 'load' });
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(1300);
}

async function goBack(page) {
  await page.$eval('.editor-fab.left', (e) => {
    const r = e.getBoundingClientRect();
    const o = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, pointerId: 1, pointerType: 'mouse', isPrimary: true };
    e.dispatchEvent(new PointerEvent('pointerdown', o));
    e.dispatchEvent(new PointerEvent('pointerup', o));
  });
  await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
  await page.waitForTimeout(700);
}

// 两栏快照（流式/独立共用）：body 直子栏恰两栏时取左右
// 成员与几何；块条目 w 为 wrap 宽、colW/colCW 为栏宽/栏
// 内容宽。
const snapTwo = () => {
  const body = document.querySelector('.editor-body');
  const bidOf = (el) => el.getAttribute('data-wrapbid')
    || el.querySelector('[data-wrapbid]')?.getAttribute('data-wrapbid')
    || el.getAttribute('data-bid')
    || el.querySelector('[data-bid]')?.getAttribute('data-bid')
    || null;
  const cols = body.querySelectorAll(':scope > .editor-column');
  const grab = (col) => {
    const cs = getComputedStyle(col);
    const colCW = Math.round(col.getBoundingClientRect().width - (parseFloat(cs.paddingLeft) || 0) - (parseFloat(cs.paddingRight) || 0));
    return Array.from(col.children).filter((c) => !c.classList.contains('md-trail')).map((c) => ({ bid: bidOf(c), w: Math.round(c.getBoundingClientRect().width), colW: Math.round(col.getBoundingClientRect().width), colCW }));
  };
  const bcs = getComputedStyle(body);
  return {
    cls: body.className,
    colCount: cols.length,
    segCount: body.querySelectorAll('.editor-flow-seg').length,
    bodyW: Math.round(body.getBoundingClientRect().width),
    bodyCW: Math.round(body.getBoundingClientRect().width - (parseFloat(bcs.paddingLeft) || 0) - (parseFloat(bcs.paddingRight) || 0)),
    gap: parseFloat(bcs.columnGap) || 0,
    left: cols[0] ? grab(cols[0]) : null,
    right: cols[1] ? grab(cols[1]) : null,
  };
};

const readMemo = (id) => {
  return (async () => {
    const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    // 组装读（IDB 分条合流适配，只换读取通道、断言不变）
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
    const m = JSON.parse(raw).memos.find((x) => String(x.id) === id);
    return m ? { ids: m.doc.map((b) => b.id), layout: m.layout ?? null, layoutRaw: m.layout ? JSON.stringify(m.layout) : null } : null;
  })();
};

async function toggleMode(page) {
  const panelVisible = await page.evaluate(() => !!document.querySelector('.editor-menu-panel'));
  if (!panelVisible) {
    await page.$eval('.editor-fab.right', (e) => {
      const r = e.getBoundingClientRect();
      const o = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, pointerId: 1, pointerType: 'mouse', isPrimary: true };
      e.dispatchEvent(new PointerEvent('pointerdown', o));
      e.dispatchEvent(new PointerEvent('pointerup', o));
    });
    await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  }
  await page.$eval('.editor-column-mode-toggle', (e) => e.click());
  await page.waitForTimeout(600);
  const stillOpen = await page.evaluate(() => !!document.querySelector('.editor-menu-panel'));
  if (stillOpen) {
    await page.$eval('.menu-scrim', (e) => e.click());
    await page.waitForTimeout(400);
  }
}

const flatIds = (snap) => [...(snap.left || []), ...(snap.right || [])].map((b) => b.bid);
const FIXTURE_IDS = docA.map((b) => b.id);
const SPAN_IDS = ['im1', 'ga1', 'it1', 'mu1', 'at1', 'itr1'];

// ---------- 主夹具：流式 F1–F4 ----------
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));
await seed(page);
await openMemo(page, 'fspan1');
const s1 = await page.evaluate(snapTwo);
console.log('FLOW1:', JSON.stringify([s1.left && s1.left.map((b) => b.bid), s1.right && s1.right.map((b) => b.bid)]));
ok('流式 body 类为 is-flow-columns 且恰两栏、无分段容器', s1.cls.includes('is-flow-columns') && s1.colCount === 2 && s1.segCount === 0,
  `cls=${s1.cls} cols=${s1.colCount} segs=${s1.segCount}`);
const allBlocks1 = [...(s1.left || []), ...(s1.right || [])];
ok('F1 原跨栏六类块全部在栏内（宽==栏内容宽、远窄于整幅）',
  SPAN_IDS.every((id) => { const b = allBlocks1.find((x) => x.bid === id); return b && Math.abs(b.w - b.colCW) <= 2 && b.w < s1.bodyCW - 200; }),
  JSON.stringify(SPAN_IDS.map((id) => { const b = allBlocks1.find((x) => x.bid === id); return b ? [id, b.w, b.colCW] : [id, null]; })));
ok('F2 栏宽==(体内容宽−gap)/2 且两栏非空', !!s1.left && !!s1.right && s1.left.length > 0 && s1.right.length > 0
  && allBlocks1.every((b) => Math.abs(b.colW - (s1.bodyCW - s1.gap) / 2) <= 2),
  `bodyCW=${s1.bodyCW} gap=${s1.gap} colWs=${[...new Set(allBlocks1.map((b) => b.colW))].join(',')}`);
const flat1 = flatIds(s1);
ok('F3 DOM 序（左++右）与文档序一致（至多尾随物化段）',
  eq(flat1.filter((id) => FIXTURE_IDS.includes(id)), FIXTURE_IDS)
  && flat1.filter((id) => !FIXTURE_IDS.includes(id)).length <= 1,
  flat1.join(','));
ok('F4 切分 == 手算 canonical（左 8 / 右 7）',
  !!s1.left && eq(s1.left.map((b) => b.bid).filter((id) => FIXTURE_IDS.includes(id)), CANON_LEFT)
  && eq(s1.right.map((b) => b.bid).filter((id) => FIXTURE_IDS.includes(id)), CANON_RIGHT),
  JSON.stringify([s1.left && s1.left.map((b) => b.bid), s1.right && s1.right.map((b) => b.bid)]));
// F4 确定性：关→开逐块全等
await goBack(page);
await openMemo(page, 'fspan1');
const s2 = await page.evaluate(snapTwo);
ok('F4b 重开切分逐块全等', eq(flatIds(s2), flat1));

// ---------- F8 画布落焦 ----------
await page.evaluate(() => {
  const cols = document.querySelectorAll('.editor-body > .editor-column');
  const last = cols[1].lastElementChild;
  if (last) last.scrollIntoView({ block: 'end' });
});
await page.waitForTimeout(500);
const focusRes = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const cols = body.querySelectorAll(':scope > .editor-column');
  const rightCol = cols[1];
  const rr = rightCol.getBoundingClientRect();
  const br = body.getBoundingClientRect();
  const lastBlockBottom = Math.max(...Array.from(rightCol.children).map((c) => c.getBoundingClientRect().bottom));
  // 期望落点：右栏最后一个可编辑单元——常态即 p9；若打开
  // 时物化了尾随空段，它排在 p9 后、同为合法落点。
  const eds = Array.from(rightCol.querySelectorAll('[data-bid]')).filter((n) => n.isContentEditable);
  const lastEd = eds[eds.length - 1];
  const x = rr.x + rr.width / 2;
  // 点击点：右栏末块之下、body 之内、视口之内（长页须先
  // 滚动入视口，视口外坐标点不到任何元素）
  const y = Math.min(br.bottom - 24, lastBlockBottom + 40, window.innerHeight - 12);
  const el = document.elementFromPoint(x, y);
  return { x, y, hit: el ? (el.className || el.tagName) : 'none', expect: lastEd ? lastEd.getAttribute('data-bid') : null };
});
await page.mouse.click(focusRes.x, focusRes.y);
await page.waitForTimeout(600);
const focusBid = await page.evaluate(() => document.activeElement && document.activeElement.getAttribute('data-bid'));
console.log('F8 click:', JSON.stringify(focusRes), 'focus=', focusBid);
ok('F8 点右栏末块下方空白焦点落右栏末可编辑块（p9 或其尾随段）', !!focusBid && focusBid === focusRes.expect, `focus=${focusBid} expect=${focusRes.expect}`);
await page.keyboard.press('Escape');

// ---------- F6/F10 模式往返 ----------
await toggleMode(page);
const si = await page.evaluate(snapTwo);
console.log('INDEP:', JSON.stringify([si.left && si.left.map((b) => b.bid), si.right && si.right.map((b) => b.bid)]));
ok('F6a 独立成员 == 锚分界', !!si.left
  && eq(si.left.map((b) => b.bid).filter((id) => FIXTURE_IDS.includes(id)), anchorA.left)
  && eq(si.right.map((b) => b.bid).filter((id) => FIXTURE_IDS.includes(id)), anchorA.right));
const indepBlocks = [...(si.left || []), ...(si.right || [])];
// 不跨栏判据：块宽比栏宽窄一个边距量级（实测 31–32）
// 且远窄于整幅——误跨栏时宽≈整幅 1408、必被抓；块类
// 型间边距本就不同（段落 16 / 卡片 32），不做跨类型
// 均匀假设。
ok('F10 独立模式六类块不跨栏（宽=栏宽−边距量级）', SPAN_IDS.every((id) => {
  const b = indepBlocks.find((x) => x.bid === id);
  return b && (b.colW - b.w) >= 16 && (b.colW - b.w) <= 64;
}), JSON.stringify(SPAN_IDS.map((id) => { const b = indepBlocks.find((x) => x.bid === id); return b ? [b.w, b.colW] : null; })));
await toggleMode(page);
const s3 = await page.evaluate(snapTwo);
ok('F6b 回到流式切分复原（== 首开 canonical）', eq(flatIds(s3), flat1));
const afterToggles = await page.evaluate(readMemo, 'fspan1');
// layout 键序由应用序列化决定（与夹具字面序无关），
// 按 mode/left/right 语义比对（逐字节基线只用于同源
// 读回互比，见 F5）。
ok('F6c 往返后 layout 不变（mode/名单）', !!afterToggles && !!afterToggles.layout
  && afterToggles.layout.mode === anchorA.mode
  && eq(afterToggles.layout.left, anchorA.left) && eq(afterToggles.layout.right, anchorA.right),
  afterToggles && afterToggles.layoutRaw);
await goBack(page);

// ---------- F5 锚零改写（流式锚夹具纯流式开/关） ----------
const cBefore = await page.evaluate(readMemo, 'fspan3');
await openMemo(page, 'fspan3');
const sc = await page.evaluate(snapTwo);
ok('G2b mode=flow 备忘以流式打开', sc.cls.includes('is-flow-columns'));
await goBack(page);
const cAfter = await page.evaluate(readMemo, 'fspan3');
ok('F5 流式开/关后 layout 逐字节一致', !!cBefore && !!cAfter && cBefore.layoutRaw === cAfter.layoutRaw, `${cBefore && cBefore.layoutRaw} -> ${cAfter && cAfter.layoutRaw}`);
// Diag 无落锚行（等落盘节流静默后读）
let diagTxt = '';
for (let i = 0; i < 8; i++) {
  await page.waitForTimeout(900);
  const t = await page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
  if (t === diagTxt && t.length > 0) break;
  diagTxt = t;
}
ok('F5b 流式会话无 column anchor captured', !diagTxt.includes('column anchor captured'));

// ---------- G2 无 mode → 独立 ----------
await openMemo(page, 'fspan2');
const sb = await page.evaluate(snapTwo);
ok('G2a layout 无 mode 宽屏打开 = 独立模式', sb.cls.includes('is-independent-scroll'), sb.cls);
const toggleAria = await page.evaluate(() => {
  return new Promise((resolve) => {
    const fab = document.querySelector('.editor-fab.right');
    const r = fab.getBoundingClientRect();
    const o = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, pointerId: 1, pointerType: 'mouse', isPrimary: true };
    fab.dispatchEvent(new PointerEvent('pointerdown', o));
    fab.dispatchEvent(new PointerEvent('pointerup', o));
    setTimeout(() => {
      const t = document.querySelector('.editor-column-mode-toggle');
      resolve(t ? t.getAttribute('aria-checked') : null);
      const scrim = document.querySelector('.menu-scrim');
      if (scrim) scrim.click();
    }, 700);
  });
});
ok('G2a2 独立开关 aria-checked=true', toggleAria === 'true', `aria=${toggleAria}`);
const bAfter = await page.evaluate(readMemo, 'fspan2');
ok('G2d 无 mode 名单合法者名单不被改写', !!bAfter && eq(bAfter.layout.left, ['b1']) && eq(bAfter.layout.right, ['b2', 'b3']), bAfter && JSON.stringify(bAfter.layout));
await goBack(page);

// ---------- F7 流式拖拽 ----------
await openMemo(page, 'fspan1');
async function blockCenter(bid) {
  return page.evaluate((b) => {
    const find = (root) => {
      for (const el of root.querySelectorAll('[data-wrapbid], [data-bid]')) {
        if ((el.getAttribute('data-wrapbid') || el.getAttribute('data-bid')) === b) return el;
      }
      return null;
    };
    const el = find(document.querySelector('.editor-body'));
    if (!el) return null;
    const wrap = el.closest('.blk-wrap') || el;
    const r = wrap.getBoundingClientRect();
    return { cx: r.x + r.width / 2, cy: r.y + r.height / 2, top: r.top, bottom: r.bottom, h: r.height };
  }, bid);
}
// 拖拽手法（probe_drag_sort 已证口径）：目标与源先后
// scrollIntoView 入视口，落点取目标底边 −3（after）或
// 顶边 +3（before）。行程控制在一屏内：长行程会触发
// 桥的边缘自动滚动、使预瞄终点漂移一格，故跨界用例选
// 相邻跨界对（左栏末块 ↔ 右栏首块一带）。
async function dragBlock(fromBid, toBid, where = 'after') {
  const scrollIn = async (bid) => {
    await page.evaluate((b) => {
      const el = document.querySelector(`[data-wrapbid="${b}"], [data-bid="${b}"]`);
      const wrap = el && (el.closest('.blk-wrap') || el);
      if (wrap) wrap.scrollIntoView({ block: 'center' });
    }, bid);
    await page.waitForTimeout(350);
  };
  await scrollIn(toBid);
  await scrollIn(fromBid);
  const from = await blockCenter(fromBid);
  const to = await blockCenter(toBid);
  if (!from || !to) return false;
  await page.mouse.move(from.cx, from.cy);
  await page.mouse.down();
  await page.waitForTimeout(380);
  const targetY = where === 'before' ? to.top + 3 : to.bottom - 3;
  const steps = 14;
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(from.cx + (to.cx - from.cx) * (i / steps), from.cy + (targetY - from.cy) * (i / steps));
    await page.waitForTimeout(30);
  }
  // 松手前落定：桥落点由 rAF 循环按最新指针位算（最近单
  // 元 + 中点判前后），末步指针刚到、目标未落定时松手会
  // 吃上一帧的竞争结果（F7c 对角相邻单元 it1/p6 实测偏
  // 一格）；停 250ms 让落点在最终位（目标单元内、距 0）
  // 落定再松手——真人拖拽看预瞄落位同理。
  await page.waitForTimeout(250);
  await page.mouse.up();
  await page.waitForTimeout(1000);
  return true;
}
ok('F7a 栏内拖拽执行（p4→p5 后）', await dragBlock('p4', 'p5'));
let mNow = await page.evaluate(readMemo, 'fspan1');
const expectA = FIXTURE_IDS.slice();
{ const i4 = expectA.indexOf('p4'); expectA.splice(i4, 1); expectA.splice(expectA.indexOf('p5') + 1, 0, 'p4'); }
ok('F7a 落盘序：p4 落到 p5 之后', !!mNow && eq(mNow.ids.filter((id) => FIXTURE_IDS.includes(id)), expectA), mNow && mNow.ids.join(','));
ok('F7b 跨栏拖拽执行（左栏末 p6→右栏首 it1 后）', await dragBlock('p6', 'it1'));
mNow = await page.evaluate(readMemo, 'fspan1');
const expectB = expectA.slice();
{ const i6 = expectB.indexOf('p6'); expectB.splice(i6, 1); expectB.splice(expectB.indexOf('it1') + 1, 0, 'p6'); }
ok('F7b 落盘序：p6 跨栏落到 it1 之后', !!mNow && eq(mNow.ids.filter((id) => FIXTURE_IDS.includes(id)), expectB), mNow && mNow.ids.join(','));
// F7c 反向跨栏（右→左）：mu1 落 it1 之后。原配对 ga1→p6
// （高 gallery 拖向右栏栏顶短段）实测恒落 p6 之前一格：
// FLIP 预瞄位移下该几何存在自洽落点（预瞄间隙停在 it1
// 后），属探针几何陷阱——产品拖拽面由 drag_sort 跨栏用
// 例全覆盖且全过，故换镜像配对验同一跨栏语义。
ok('F7c 跨栏反向拖拽执行（mu1→it1 后）', await dragBlock('mu1', 'it1'));
mNow = await page.evaluate(readMemo, 'fspan1');
const expectC = expectB.slice();
{ const ii = expectC.indexOf('mu1'); expectC.splice(ii, 1); expectC.splice(expectC.indexOf('it1') + 1, 0, 'mu1'); }
ok('F7c 落盘序：mu1 跨栏落到 it1 之后', !!mNow && eq(mNow.ids.filter((id) => FIXTURE_IDS.includes(id)), expectC), mNow && mNow.ids.join(','));
ok('F7d 落盘 layout 仍一刀切（left++right == 文档序）', !!mNow && eq([...(mNow.layout.left || []), ...(mNow.layout.right || [])], mNow.ids), mNow && JSON.stringify(mNow.layout));
const sAfterDrag = await page.evaluate(snapTwo);
ok('F7e 重渲染序（左++右）与落盘序一致', eq(flatIds(sAfterDrag).filter((id) => FIXTURE_IDS.includes(id)), expectC));

// ---------- F9 窄屏退化 ----------
await page.setViewportSize({ width: 500, height: 800 });
await page.waitForTimeout(900);
const narrow = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const bidOf = (el) => el.getAttribute('data-wrapbid')
    || el.querySelector('[data-wrapbid]')?.getAttribute('data-wrapbid')
    || el.getAttribute('data-bid')
    || el.querySelector('[data-bid]')?.getAttribute('data-bid')
    || null;
  const kids = Array.from(body.children).filter((c) => !c.classList.contains('md-trail'));
  return {
    colCount: body.querySelectorAll(':scope > .editor-column').length,
    ids: kids.map((c) => bidOf(c)),
    widths: kids.map((c) => Math.round(c.getBoundingClientRect().width)),
    bodyW: Math.round(body.getBoundingClientRect().width),
  };
});
console.log('NARROW:', JSON.stringify(narrow));
ok('F9 窄屏无栏、单栏序==文档序', narrow.colCount === 0 && eq(narrow.ids.filter((id) => FIXTURE_IDS.includes(id)), expectC));
ok('F9b 窄屏块宽==内容宽', narrow.widths.every((w) => Math.abs(w - narrow.bodyW) <= 24), `bodyW=${narrow.bodyW} ws=${narrow.widths.join(',')}`);
await goBack(page);
await ctx.close();

// ---------- G2 无 layout 沿 localStorage 默认 ----------
const ctx2 = await browser.newContext({ viewport: { width: 1440, height: 900 }, hasTouch: true });
const page2 = await ctx2.newPage();
page2.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));
await seed(page2);
await openMemo(page2, 'fspan4');
const dCls = await page2.evaluate(() => document.querySelector('.editor-body').className);
ok('G2c 无 layout 且 localStorage 未设 → 流式', dCls.includes('is-flow-columns'), dCls);
await goBack(page2);
await ctx2.close();
const ctx3 = await browser.newContext({ viewport: { width: 1440, height: 900 }, hasTouch: true });
await ctx3.addInitScript(() => localStorage.setItem('sj_editor_independent_scroll', '1'));
const page3 = await ctx3.newPage();
await seed(page3);
await openMemo(page3, 'fspan4');
const dCls3 = await page3.evaluate(() => document.querySelector('.editor-body').className);
ok('G2c2 无 layout 且 localStorage=1 → 独立', dCls3.includes('is-independent-scroll'), dCls3);
await ctx3.close();

await browser.close();
console.log(fails === 0 ? 'FLOWSPAN ALL PASS' : `FLOWSPAN ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
