// 探针（卡片交互专项）：编辑页卡片块交互重构验收——
// ① 常驻悬浮钮（.blk-del）与悬停「•••」钮（.blk-more）
// 整体移除 ② 触屏长按拾起弹浮
// 层菜单（贴卡、原地松手留存）+ 拖动转入自动收起 + 菜单
// 删除落盘 ③ 编辑态门禁：非编辑态点图文文本区不开表、
// 点图片区仍开图片页；菜单「编辑」入态后点文本区开表、
// 点图片区直调系统选图换图（filechooser 实换落盘）；点
// 卡外退出编辑态 ④ 图库编辑态点格换单图（attrs.items
// 原生规范形保形：去兼容第三步 D2/D3 归一已批准，导入
// 时裸串先转 {fileId} 对象、写回对象替对象——期望由裸
// 串迁规范形，理由见 ④ 断言处）⑤ 高卡（图库）拾起四
// 边间隙相等（等距内
// 收口径）⑥ 覆盖面菜单项构成（音乐有编辑、链接/附件/
// 分隔线仅删除）⑦ 桌面右键全流程（开菜单/Esc 关/菜单
// 编辑入态/点卡外退态/再开菜单删除落盘）。
// Chromium 口径。
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

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

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAGklEQVR42mP8z8BQz0BEwMDAwMDEwMDAAAAASUVORK5CYII=', 'base64');
const ts = new Date().toISOString();
const para = (id, text) => ({ id, type: 'paragraph', children: [{ text }] });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'cm-memo', title: '卡片菜单探针', pinned: false, createdAt: ts, updatedAt: ts, doc: [
      para('cm-p1', '首段文字'),
      { id: 'cm-itc', type: 'imgTextCard', attrs: { fileId: 'imgA' }, children: [{ text: '图文说明甲' }] },
      { id: 'cm-itc2', type: 'imgTextCard', attrs: { fileId: 'imgA' }, children: [{ text: '图文说明乙' }] },
      { id: 'cm-img', type: 'image', attrs: { fileId: 'imgB' }, children: [] },
      { id: 'cm-gal', type: 'gallery', attrs: { items: ['g1', 'g2'] }, children: [] },
      { id: 'cm-mus', type: 'musicCard', status: 'ready', url: 'https://music.163.com/song?id=123', meta: { title: '测试歌曲', subtitle: '歌手', source: '网易云音乐' }, children: [{ text: '' }] },
      { id: 'cm-lnk', type: 'link-card', url: 'https://example.com/article', children: [{ text: '' }] },
      { id: 'cm-att', type: 'attachment', fileId: 'attF', status: 'done', image: false, children: [{ text: '' }] },
      { id: 'cm-div', type: 'divider', children: [] },
    ] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {
    imgA: { name: 'a.png', type: 'image/png' }, imgB: { name: 'b.png', type: 'image/png' },
    g1: { name: 'g1.png', type: 'image/png' }, g2: { name: 'g2.png', type: 'image/png' },
    attF: { name: '说明.txt', type: 'text/plain' },
  } }) },
  { name: 'attachments/imgA', data: PNG },
  { name: 'attachments/imgB', data: PNG },
  { name: 'attachments/g1', data: PNG },
  { name: 'attachments/g2', data: PNG },
  { name: 'attachments/attF', data: Buffer.from('hello file', 'utf8') },
]);

const readDoc = (page) => page.evaluate(async () => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const raw = await new Promise((res, rej) => { const rq = db.transaction('kv', 'readonly').objectStore('kv').get('memos_json'); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  const data = JSON.parse(raw);
  const memos = Array.isArray(data) ? data : data.memos;
  const m = (memos || []).find((x) => x.title === '卡片菜单探针');
  return m ? m.doc : null;
});
const diagText = (page) => page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || ''));
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
const wrapRect = async (page, bid) => page.evaluate((b) => {
  const el = document.querySelector('[data-wrapbid="' + b + '"]');
  if (!el) return null;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x, y: r.y, w: r.width, h: r.height, cx: r.x + r.width / 2, cy: r.y + r.height / 2 };
}, bid);
const zoneCenter = (page, bid, sel) => page.evaluate(([b, s]) => {
  const w = document.querySelector('[data-wrapbid="' + b + '"]');
  const el = w ? w.querySelector(s) : null;
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, [bid, sel]);
const menuState = (page) => page.evaluate(() => {
  const p = document.querySelector('.card-menu-panel');
  if (!p) return null;
  const items = [...p.querySelectorAll('.menu-item')].map((b) => ({
    danger: b.classList.contains('danger'),
    text: b.textContent.trim(),
  }));
  const r = p.getBoundingClientRect();
  return { items, x: r.x, y: r.y, w: r.width, h: r.height };
});
const wrapCls = (page, bid) => page.evaluate((b) => document.querySelector('[data-wrapbid="' + b + '"]')?.className || '', bid);
const paraPt = (page, bid) => page.evaluate((b) => {
  const el = document.querySelector('[data-bid="' + b + '"]');
  if (!el) return null;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, bid);

async function importAndOpen(page) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'card_menu.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=cm-memo', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-wrapbid="cm-itc"]', { timeout: 15000 });
  await page.waitForTimeout(900);
}

// ---------- 触屏 ----------
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
await ctx.addInitScript(() => localStorage.setItem('mynote_hint_editor_v1', '1'));
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await importAndOpen(page);
const cdp = await ctx.newCDPSession(page);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});

// ① 常驻悬浮钮整体移除
ok('① 无 .blk-del 常驻悬浮钮', await page.evaluate(() => document.querySelectorAll('.blk-del').length === 0));
ok('① 无 .blk-more 悬停钮残留（菜单入口只剩长按+右键）', await page.evaluate(() => document.querySelectorAll('.blk-more').length === 0));

// ② 长按图文卡 → 菜单贴卡弹出（编辑+删除）、原地松手留存
const r1 = await wrapRect(page, 'cm-itc');
await touch('touchStart', r1.cx, r1.cy);
await page.waitForTimeout(750);
let ms = await menuState(page);
ok('② 长按拾起弹浮层菜单', !!ms, ms ? '' : 'no panel');
ok('② 菜单含编辑+删除两项', !!ms && ms.items.length === 2 && ms.items.some((i) => i.danger) && ms.items.some((i) => !i.danger),
  ms ? JSON.stringify(ms.items) : '');
ok('② 菜单贴卡（横向与卡左缘近齐、纵向在卡下方或上方近邻）', !!ms
  && Math.abs(ms.x - r1.x) <= 16 && (Math.abs(ms.y - (r1.y + r1.h)) <= 20 || Math.abs(ms.y + ms.h - r1.y) <= 20),
  ms ? `panel=${ms.x},${ms.y} card=${r1.x},${r1.y},h=${r1.h}` : '');
await touch('touchEnd');
await page.waitForTimeout(500);
ms = await menuState(page);
ok('② 原地松手菜单留存', !!ms);
// 点删除 → 块消失落盘、菜单关闭、Diag 记行
const delPt = await page.evaluate(() => {
  const b = document.querySelector('.card-menu-panel .menu-item.danger');
  const r = b.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
await page.touchscreen.tap(delPt.x, delPt.y);
await page.waitForTimeout(700);
const docAfterDel = await readDoc(page);
ok('② 菜单删除落盘（cm-itc 消失）', !!docAfterDel && !docAfterDel.some((b) => b.id === 'cm-itc')
  && docAfterDel.some((b) => b.id === 'cm-itc2'));
ok('② 删除后菜单关闭', (await menuState(page)) === null);
const diag1 = await waitDiag(page, (t) => t.includes('card menu open') && t.includes('card menu delete'));
ok('② Diag 记 card menu open / card menu delete', diag1.includes('card menu open') && diag1.includes('card menu delete'));

// ②b 长按后移动转拖动 → 菜单自动收起
const r2 = await wrapRect(page, 'cm-img');
await touch('touchStart', r2.cx, r2.cy);
await page.waitForTimeout(750);
ok('②b 图片块长按亦弹菜单', (await menuState(page)) !== null);
await touch('touchMove', r2.cx, r2.cy + 70);
await page.waitForTimeout(350);
ok('②b 移动转拖动菜单自动收起', (await menuState(page)) === null);
await touch('touchEnd');
await page.waitForTimeout(800);
const docAfterDrag = await readDoc(page);
ok('②b 拖动后块仍在（未误删）', !!docAfterDrag && docAfterDrag.some((b) => b.id === 'cm-img'));

// ③ 编辑态门禁（cm-itc2）
const tz = await zoneCenter(page, 'cm-itc2', '.itc-text');
await page.touchscreen.tap(tz.x, tz.y);
await page.waitForTimeout(500);
ok('③ 非编辑态点文本区不开底表', (await page.$('.image-text-sheet')) === null);
ok('③ 非编辑态点文本区只选中卡片', (await wrapCls(page, 'cm-itc2')).includes('sel'));
const iz = await zoneCenter(page, 'cm-itc2', '.itc-img-wrap img');
await page.touchscreen.tap(iz.x, iz.y);
await page.waitForTimeout(600);
ok('③ 非编辑态点图片区仍开图片页', (await page.$('.img-page')) !== null);
await page.click('.img-page .editor-fab.left');
await page.waitForTimeout(500);
ok('③ 图片页可关（返回编辑页）', (await page.$('.img-page')) === null);
// 菜单 → 编辑入态
const r3 = await wrapRect(page, 'cm-itc2');
await touch('touchStart', r3.cx, r3.cy);
await page.waitForTimeout(750);
const editPt = await page.evaluate(() => {
  const b = [...document.querySelectorAll('.card-menu-panel .menu-item')].find((x) => !x.classList.contains('danger'));
  const r = b.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
await touch('touchEnd');
// 落位合成 click 抑制窗为 400ms（桥既有口径）：菜单项点
// 按须等抑制窗过后再发，否则 click 被抑制层吞掉。
await page.waitForTimeout(650);
await page.touchscreen.tap(editPt.x, editPt.y);
await page.waitForTimeout(500);
ok('③ 菜单编辑入编辑态（card-editing 类）', (await wrapCls(page, 'cm-itc2')).includes('card-editing'),
  await wrapCls(page, 'cm-itc2'));
// 编辑态点文本区 → 开表
const tz2 = await zoneCenter(page, 'cm-itc2', '.itc-text');
await page.touchscreen.tap(tz2.x, tz2.y);
await page.waitForTimeout(600);
ok('③ 编辑态点文本区开底表', (await page.$('.image-text-sheet')) !== null);
await page.touchscreen.tap(200, 120);
await page.waitForTimeout(600);
ok('③ 底表可关', (await page.$('.image-text-sheet')) === null);
// 编辑态点图片区 → 系统选图，实换落盘
const fcP = page.waitForEvent('filechooser', { timeout: 8000 });
const iz2 = await zoneCenter(page, 'cm-itc2', '.itc-img-wrap img');
await page.touchscreen.tap(iz2.x, iz2.y);
const fc = await fcP.catch(() => null);
ok('③ 编辑态点图片区触发系统选图', !!fc);
if (fc) await fc.setFiles({ name: 'new.png', mimeType: 'image/png', buffer: PNG });
await page.waitForTimeout(900);
const docAfterPick = await readDoc(page);
const itc2 = docAfterPick ? docAfterPick.find((b) => b.id === 'cm-itc2') : null;
ok('③ 换图落盘（fileId 已变）', !!itc2 && !!itc2.attrs && !!itc2.attrs.fileId && itc2.attrs.fileId !== 'imgA',
  itc2 ? JSON.stringify(itc2.attrs) : 'no block');
// 点卡外退出编辑态
const p1 = await paraPt(page, 'cm-p1');
await page.touchscreen.tap(p1.x, p1.y);
await page.waitForTimeout(500);
ok('③ 点卡外退出编辑态', !(await wrapCls(page, 'cm-itc2')).includes('card-editing'));
const diag3 = await waitDiag(page, (t) => t.includes('card edit enter') && t.includes('card edit exit'));
ok('③ Diag 记 card edit enter / exit', diag3.includes('card edit enter') && diag3.includes('card edit exit'));

// ④+⑤ 图库：长按拾起量拾起框↔格网视觉面四边间隙
// （高卡；视觉面口径——框 = 格网 ⊕ 4px，全矩阵见
// probe_lift_surface；此处守菜单探针内的图库不变量）；
// 菜单编辑入态点格换单图
const g0 = await wrapRect(page, 'cm-gal');
await touch('touchStart', g0.cx, g0.cy);
await page.waitForTimeout(750 + 450);
const g1r = await page.evaluate(() => {
  const el = document.querySelector('.mn-lifted');
  const grid = document.querySelector('[data-wrapbid="cm-gal"] .gallery-grid');
  if (!el || !grid) return null;
  const cs = getComputedStyle(el, '::before');
  // ::before 定位相对内边距盒，须加回边框宽（同
  // probe_lift_surface __frameRect 口径）
  const fl = parseFloat(cs.left) + (el.clientLeft || 0), ft = parseFloat(cs.top) + (el.clientTop || 0);
  const fw = parseFloat(cs.width), fh = parseFloat(cs.height);
  if ([fl, ft, fw, fh].some((v) => Number.isNaN(v))) return null;
  const r = el.getBoundingClientRect();
  const kx = r.width / el.offsetWidth, ky = r.height / el.offsetHeight;
  const gr = grid.getBoundingClientRect();
  return {
    gaps: [
      gr.left - (r.left + fl * kx), (r.left + (fl + fw) * kx) - gr.right,
      gr.top - (r.top + ft * ky), (r.top + (ft + fh) * ky) - gr.bottom,
    ],
  };
});
const gaps = g1r ? g1r.gaps : null;
ok('⑤ 高卡（图库）拾起框↔格网四边间隙 = 4px（两两差 ≤1px）', !!gaps
  && Math.max(...gaps) - Math.min(...gaps) <= 1 && gaps.every((g) => g >= 3 && g <= 5),
  gaps ? 'gaps=' + gaps.map((g) => g.toFixed(2)).join('/') : 'no lift');
const editPt2 = await page.evaluate(() => {
  const b = [...document.querySelectorAll('.card-menu-panel .menu-item')].find((x) => !x.classList.contains('danger'));
  if (!b) return null;
  const r = b.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
await touch('touchEnd');
await page.waitForTimeout(650);
ok('④ 图库菜单含编辑项', !!editPt2);
if (editPt2) await page.touchscreen.tap(editPt2.x, editPt2.y);
await page.waitForTimeout(500);
ok('④ 图库入编辑态', (await wrapCls(page, 'cm-gal')).includes('card-editing'));
const fcP2 = page.waitForEvent('filechooser', { timeout: 8000 });
const tile2 = await page.evaluate(() => {
  const imgs = document.querySelectorAll('[data-wrapbid="cm-gal"] .gallery-grid img');
  const r = imgs[1].getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
await page.touchscreen.tap(tile2.x, tile2.y);
const fc2 = await fcP2.catch(() => null);
ok('④ 编辑态点图库格触发选图', !!fc2);
if (fc2) await fc2.setFiles({ name: 'g-new.png', mimeType: 'image/png', buffer: PNG });
await page.waitForTimeout(900);
const docAfterGal = await readDoc(page);
const gal = docAfterGal ? docAfterGal.find((b) => b.id === 'cm-gal') : null;
const items = gal && gal.attrs ? gal.attrs.items : null;
// 期望迁移（2026-11-24 链尾定性、父级定夺）：夹具经备份
// 导入落库，D2/D3 归一（去兼容第三步，用户已批准）在导
// 入时已把 items 裸串转成原生规范形 {fileId}；换图写回
// 路径保形（对象替对象）。旧期望「保裸串」停留在归一前
// 口径，故迁为规范形：[0] 仍指 g1、[1] 为新 fileId 对象。
ok('④ 换单图落盘且保原生规范形（items[0] 不动、[1] 为新 {fileId}）', Array.isArray(items)
  && items[0] && typeof items[0] === 'object' && items[0].fileId === 'g1'
  && items[1] && typeof items[1] === 'object' && typeof items[1].fileId === 'string' && items[1].fileId !== 'g2',
  items ? JSON.stringify(items) : 'no items');
const p1b = await paraPt(page, 'cm-p1');
await page.touchscreen.tap(p1b.x, p1b.y);
await page.waitForTimeout(400);

// ⑥ 覆盖面菜单项构成：音乐有编辑；链接/附件/分隔线仅删除
for (const [bid, wantEdit, label] of [
  ['cm-mus', true, '音乐卡'],
  ['cm-lnk', false, '链接卡'],
  ['cm-att', false, '附件卡'],
  ['cm-div', false, '分隔线'],
]) {
  const rr = await wrapRect(page, bid);
  await touch('touchStart', rr.cx, rr.cy);
  await page.waitForTimeout(750);
  const m = await menuState(page);
  await touch('touchEnd');
  await page.waitForTimeout(200);
  ok(`⑥ ${label}菜单项构成（编辑=${wantEdit}）`, !!m
    && m.items.some((i) => i.danger)
    && m.items.some((i) => !i.danger) === wantEdit
    && m.items.length === (wantEdit ? 2 : 1),
    m ? JSON.stringify(m.items) : 'no panel');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(250);
}
await ctx.close();

// ---------- 桌面 ----------
const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 800 } });
await ctx2.addInitScript(() => localStorage.setItem('mynote_hint_editor_v1', '1'));
const p2 = await ctx2.newPage();
p2.on('pageerror', (e) => L('PAGEERROR(d)', String(e).slice(0, 200)));
await importAndOpen(p2);
// 右键出菜单
const d1 = await wrapRect(p2, 'cm-itc');
await p2.mouse.click(d1.cx, d1.cy, { button: 'right' });
await p2.waitForTimeout(600);
const dm = await menuState(p2);
ok('⑦ 桌面右键出同一菜单（编辑+删除）', !!dm && dm.items.length === 2, dm ? JSON.stringify(dm.items) : 'no panel');
await p2.keyboard.press('Escape');
await p2.waitForTimeout(300);
ok('⑦ Esc 关菜单', (await menuState(p2)) === null);
// 右键全流程：再开菜单 → 点「编辑」入态 → 点卡外退态
// → 三开菜单 → 点「删除」落盘（与触屏长按路同覆盖面）
const d2 = await wrapRect(p2, 'cm-itc');
await p2.mouse.click(d2.cx, d2.cy, { button: 'right' });
await p2.waitForTimeout(600);
ok('⑦ 右键再开菜单', (await menuState(p2)) !== null);
const editPtD = await p2.evaluate(() => {
  const b = [...document.querySelectorAll('.card-menu-panel .menu-item')].find((x) => !x.classList.contains('danger'));
  if (!b) return null;
  const r = b.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
ok('⑦ 右键菜单含编辑项', !!editPtD);
if (editPtD) await p2.mouse.click(editPtD.x, editPtD.y);
await p2.waitForTimeout(500);
ok('⑦ 右键菜单编辑入编辑态（card-editing 类）', (await wrapCls(p2, 'cm-itc')).includes('card-editing'),
  await wrapCls(p2, 'cm-itc'));
const dp1 = await paraPt(p2, 'cm-p1');
await p2.mouse.click(dp1.x, dp1.y);
await p2.waitForTimeout(500);
ok('⑦ 点卡外退出编辑态', !(await wrapCls(p2, 'cm-itc')).includes('card-editing'));
const d3 = await wrapRect(p2, 'cm-itc');
await p2.mouse.click(d3.cx, d3.cy, { button: 'right' });
await p2.waitForTimeout(600);
ok('⑦ 右键三开菜单', (await menuState(p2)) !== null);
const delPtD = await p2.evaluate(() => {
  const b = document.querySelector('.card-menu-panel .menu-item.danger');
  if (!b) return null;
  const r = b.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
ok('⑦ 右键菜单含删除项', !!delPtD);
if (delPtD) await p2.mouse.click(delPtD.x, delPtD.y);
await p2.waitForTimeout(700);
const docAfterDelD = await readDoc(p2);
ok('⑦ 右键菜单删除落盘（cm-itc 消失、cm-itc2 仍在）', !!docAfterDelD
  && !docAfterDelD.some((b) => b.id === 'cm-itc') && docAfterDelD.some((b) => b.id === 'cm-itc2'));
ok('⑦ 删除后菜单关闭', (await menuState(p2)) === null);
await ctx2.close();

await browser.close();
L(fails === 0 ? 'CARD MENU ALL PASS' : `CARD MENU ${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
