// 探针（音乐输入胶囊接入块级统一机制）：音乐卡 input 态
// 胶囊旧形态裸挂编辑区直子（不进 .blk-wrap），桥的拾起命
// 中、卡片菜单（编辑/删除）、右键菜单三路全够不着——菜单
// 删除无路（键盘删块收口 K4 明文「删胶囊走卡片菜单」成
// 死路）、长按拾起被归类文本块又恒被自身光标挡下。本探
// 针锁接入后行为：
// ① 结构：胶囊在 .blk-wrap 内（data-wrapbid/data-wtype=
//    musicCard），文案为新版「…回车解析...」
// ② 冷长按（光标不在胶囊内）→ 拾起 + 卡片菜单（编辑+删
//    除两项）、Diag 记 card menu open
// ③ 长按拖动排序：胶囊块落位到目标段之后、落盘序变、
//    Diag 记 drag pickup/drop
// ④ 编辑守卫：点入胶囊（光标在内）后长按 → 不拾起、不弹
//    菜单（文本选择/粘贴口径，与文本块一致）
// ⑤ 菜单删除 → 落盘消失 + Ctrl+Z 撤销可回（status=input
//    保形）
// ⑥ 点击落焦粘贴链接 → musicInput 解析链：胶囊卸载、节
//    点转 ready/error（非 input）、焦点落卡下段首、Diag
//    记 music input resolve
// ⑦ 对照组：ready 音乐卡长按菜单仍为编辑+删除（unitKind
//    新分类不误伤普通 wrap）
// ⑧ 换篇完整性：切到第二篇再回来，各块只出现一次、无串篇
// 真实触摸走 CDP dispatchTouchEvent（同 probe_card_menu
// 口径）。Chromium 口径。用法：node probe_music_capsule.mjs [base]
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

const ts = new Date().toISOString();
const para = (id, text) => ({ id, type: 'paragraph', children: [{ text }] });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'mc-memo', title: '音乐胶囊探针', pinned: false, createdAt: ts, updatedAt: ts, doc: [
      para('mc-p1', '第一段文字'),
      { id: 'mc-cap', type: 'musicCard', url: '', meta: null, status: 'input' },
      para('mc-p2', '第二段文字'),
      { id: 'mc-mus', type: 'musicCard', status: 'ready', url: 'https://music.163.com/song?id=123', meta: { title: '测试歌曲', subtitle: '歌手', source: '网易云音乐' }, children: [{ text: '' }] },
      para('mc-p3', '第三段文字'),
    ] },
    { id: 'mc-memo-b', title: '音乐胶囊探针B', pinned: false, createdAt: ts, updatedAt: ts, doc: [
      para('mc-b1', 'B篇独有段落'),
    ] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const readDoc = (page, title = '音乐胶囊探针') => page.evaluate(async (ttl) => {
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
  const data = JSON.parse(raw);
  const memos = Array.isArray(data) ? data : data.memos;
  const m = (memos || []).find((x) => x.title === ttl);
  return m ? m.doc : null;
}, title);
const diagText = (page) => page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || ''));
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
const bidRect = async (page, bid) => page.evaluate((b) => {
  const el = document.querySelector('[data-bid="' + b + '"]');
  if (!el) return null;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x, y: r.y, w: r.width, h: r.height, cx: r.x + r.width / 2, cy: r.y + r.height / 2 };
}, bid);
const menuState = (page) => page.evaluate(() => {
  const p = document.querySelector('.card-menu-panel');
  if (!p) return null;
  const items = [...p.querySelectorAll('.menu-item')].map((b) => ({
    danger: b.classList.contains('danger'),
    text: b.textContent.trim(),
  }));
  return { items };
});
const menuItemPt = (page, danger) => page.evaluate((d) => {
  const b = [...document.querySelectorAll('.card-menu-panel .menu-item')]
    .find((x) => x.classList.contains('danger') === d);
  if (!b) return null;
  const r = b.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, danger);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
await ctx.addInitScript(() => localStorage.setItem('mynote_hint_editor_v1', '1'));
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));

// 导入夹具并打开目标篇
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'music_capsule.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.goto(base + '?open=mc-memo', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-btype="musicInput"]', { timeout: 15000 });
await page.waitForTimeout(900);

const cdp = await ctx.newCDPSession(page);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});

// ① 结构：胶囊进 wrap + 新文案
const struct1 = await page.evaluate(() => {
  const pill = document.querySelector('[data-btype="musicInput"]');
  if (!pill) return null;
  const wrap = pill.closest('.blk-wrap');
  return {
    inWrap: !!wrap,
    wrapbid: wrap?.getAttribute('data-wrapbid'),
    wtype: wrap?.getAttribute('data-wtype'),
    cls: wrap?.className || '',
    text: pill.innerText.trim(),
  };
});
ok('① 胶囊在 .blk-wrap 内（wrapbid=mc-cap、wtype=musicCard）',
  !!struct1 && struct1.inWrap && struct1.wrapbid === 'mc-cap' && struct1.wtype === 'musicCard' && struct1.cls.includes('blk-music'),
  JSON.stringify(struct1));
ok('① 胶囊文案为新版（回车解析）', !!struct1 && struct1.text === '粘贴音乐链接到这里，回车解析...', struct1?.text);
// 注：胶囊 -webkit-touch-callout:default 规则为 WebKit 专
// 有面，Chromium 量不到（computed 恒空），以代码级核查为
// 准（styles/editor.css wrap 抑制规则后的恢复规则），不
// 在本探针设断言；iOS 呼出菜单行为留真机终判。

// ② 冷长按（先点第一段把光标放别处，再长按胶囊）→ 菜单
const p1pt = await page.evaluate(() => {
  const el = document.querySelector('[data-bid="mc-p1"]');
  const r = el.getBoundingClientRect();
  return { x: r.x + 10, y: r.y + r.height / 2 };
});
await page.touchscreen.tap(p1pt.x, p1pt.y);
await page.waitForTimeout(400);
const rc = await wrapRect(page, 'mc-cap');
await touch('touchStart', rc.cx, rc.cy);
await page.waitForTimeout(750);
let ms = await menuState(page);
ok('② 冷长按胶囊弹卡片菜单', !!ms, ms ? '' : 'no panel');
ok('② 菜单含编辑+删除两项（musicCard 口径）', !!ms && ms.items.length === 2 && ms.items.some((i) => i.danger) && ms.items.some((i) => !i.danger),
  ms ? JSON.stringify(ms.items) : '');
await touch('touchEnd');
await page.waitForTimeout(500);
ok('② 原地松手菜单留存', (await menuState(page)) !== null);
const diag2 = await waitDiag(page, (t) => t.includes('card menu open mc-cap'));
ok('② Diag 记 card menu open mc-cap', diag2.includes('card menu open mc-cap'));
// 点遮罩关菜单
await page.touchscreen.tap(30, 300);
await page.waitForTimeout(400);
ok('② 点遮罩关菜单', (await menuState(page)) === null);

// ③ 长按拖动排序：胶囊拖到第二段之后
const rc2 = await wrapRect(page, 'mc-cap');
const rp2 = await bidRect(page, 'mc-p2');
await touch('touchStart', rc2.cx, rc2.cy);
await page.waitForTimeout(750);
ok('③ 拾起弹菜单（拖动前）', (await menuState(page)) !== null);
await touch('touchMove', rc2.cx, rc2.cy + 30);
await page.waitForTimeout(200);
ok('③ 移动转拖动菜单自动收起', (await menuState(page)) === null);
await touch('touchMove', rc2.cx, rp2.y + rp2.h + 30);
await page.waitForTimeout(500);
await touch('touchEnd');
await page.waitForTimeout(900);
const docDrag = await readDoc(page);
const idsDrag = (docDrag || []).map((b) => b.id);
ok('③ 拖动落盘：mc-cap 位于 mc-p2 之后', idsDrag.indexOf('mc-cap') > idsDrag.indexOf('mc-p2') && idsDrag.indexOf('mc-cap') < idsDrag.indexOf('mc-mus'),
  JSON.stringify(idsDrag));
const diag3 = await waitDiag(page, (t) => t.includes('drag pickup') && t.includes('drag drop'));
ok('③ Diag 记 drag pickup / drag drop', diag3.includes('drag pickup') && diag3.includes('drag drop'));

// ④ 编辑守卫：点入胶囊后长按 → 不拾起不弹菜单
const pillPt = await page.evaluate(() => {
  const el = document.querySelector('[data-btype="musicInput"]');
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x + 30, y: r.y + r.height / 2 };
});
await page.touchscreen.tap(pillPt.x, pillPt.y);
await page.waitForTimeout(500);
const focusIn = await page.evaluate(() => document.activeElement?.dataset?.btype || '');
ok('④ 点按落焦进胶囊', focusIn === 'musicInput', focusIn);
await touch('touchStart', pillPt.x, pillPt.y);
await page.waitForTimeout(800);
const guard = await page.evaluate(() => ({
  menu: !!document.querySelector('.card-menu-panel'),
  lifted: !!document.querySelector('.mn-lifted'),
}));
ok('④ 光标在胶囊内长按不弹菜单', !guard.menu);
ok('④ 光标在胶囊内长按不拾起（文本选择口径）', !guard.lifted);
await touch('touchEnd');
await page.waitForTimeout(300);
// 点回第一段解除胶囊焦点
await page.touchscreen.tap(p1pt.x, p1pt.y);
await page.waitForTimeout(400);

// ⑤ 菜单删除 + 撤销可回
const rc3 = await wrapRect(page, 'mc-cap');
await touch('touchStart', rc3.cx, rc3.cy);
await page.waitForTimeout(750);
await touch('touchEnd');
await page.waitForTimeout(650); // 等落位 click 抑制窗过
const delPt = await menuItemPt(page, true);
ok('⑤ 菜单删除项可达', !!delPt);
await page.touchscreen.tap(delPt.x, delPt.y);
await page.waitForTimeout(700);
const docDel = await readDoc(page);
ok('⑤ 菜单删除落盘（mc-cap 消失、其余块俱在）', !!docDel && !docDel.some((b) => b.id === 'mc-cap')
  && ['mc-p1', 'mc-p2', 'mc-mus', 'mc-p3'].every((id) => docDel.some((b) => b.id === id)),
  JSON.stringify((docDel || []).map((b) => b.id)));
const diag5 = await waitDiag(page, (t) => t.includes('card menu delete mc-cap'));
ok('⑤ Diag 记 card menu delete mc-cap', diag5.includes('card menu delete mc-cap'));
await page.keyboard.press('Control+z');
await page.waitForTimeout(900);
const docUndo = await readDoc(page);
const capBack = (docUndo || []).find((b) => b.id === 'mc-cap');
ok('⑤ Ctrl+Z 撤销删除（mc-cap 回归且 status=input 保形）', !!capBack && capBack.status === 'input',
  capBack ? JSON.stringify(capBack) : 'missing');

// ⑥ 点击落焦 + 粘贴链接解析回填
const pillPt2 = await page.evaluate(() => {
  const el = document.querySelector('[data-btype="musicInput"]');
  if (!el) return null;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.x + 30, y: r.y + r.height / 2 };
});
ok('⑥ 撤销后胶囊重新挂载', !!pillPt2);
await page.touchscreen.tap(pillPt2.x, pillPt2.y);
await page.waitForTimeout(500);
// 全选后粘贴（真实粘贴主路径：覆盖占位文案；若点位把光
// 标落在文案中间直接插入，文案被劈开后剥离不净、URL 尾
// 会吞入残文——那是原版同口径的提取器行为，不在本探针
// 判据内）。
await page.keyboard.press('Control+a');
await cdp.send('Input.insertText', { text: 'https://music.163.com/song?id=999' });
let resolved = null;
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(500);
  const d = await readDoc(page);
  const cap = (d || []).find((b) => b.id === 'mc-cap');
  if (cap && cap.status !== 'input' && cap.status !== 'loading') { resolved = cap; break; }
  if (cap && cap.url) resolved = cap; // 已转 loading 也记下，循环继续等终态
}
const pillGone = await page.evaluate(() => !document.querySelector('[data-btype="musicInput"]'));
ok('⑥ 粘贴后胶囊卸载、节点脱离 input 态且 URL 干净', pillGone && !!resolved && resolved.url === 'https://music.163.com/song?id=999' && resolved.status !== 'input',
  resolved ? JSON.stringify({ url: resolved.url, status: resolved.status }) : 'no resolve');
const diag6 = await waitDiag(page, (t) => t.includes('music input resolve mc-cap'), 8000);
ok('⑥ Diag 记 music input resolve mc-cap', diag6.includes('music input resolve mc-cap'));
// 落点口径（focusCaretBelowResolvedCard）：③ 拖动后胶囊
// 下方是音乐卡（非文本块）→ 解析后补一个空段落并落焦其
// 首，即 doc 中紧随 mc-cap 的新段。
const docAt6 = await readDoc(page);
const belowId = (() => {
  const i = (docAt6 || []).findIndex((b) => b.id === 'mc-cap');
  return i >= 0 ? (docAt6[i + 1]?.id || '') : '';
})();
const focusBelow = await page.evaluate(() => document.activeElement?.dataset?.bid || '');
ok('⑥ 解析后焦点落卡下方新补空段首', !!belowId && focusBelow === belowId && belowId !== 'mc-mus',
  `below=${belowId} focus=${focusBelow}`);

// ⑦ 对照组：ready 音乐卡长按菜单仍编辑+删除
const rm = await wrapRect(page, 'mc-mus');
await touch('touchStart', rm.cx, rm.cy);
await page.waitForTimeout(750);
ms = await menuState(page);
ok('⑦ ready 音乐卡长按菜单仍为编辑+删除', !!ms && ms.items.length === 2 && ms.items.some((i) => i.danger) && ms.items.some((i) => !i.danger),
  ms ? JSON.stringify(ms.items) : 'no panel');
await touch('touchEnd');
await page.waitForTimeout(400);
await page.touchscreen.tap(30, 300);
await page.waitForTimeout(300);

// ⑧ 换篇完整性：去 B 篇再回来
await page.click('.editor-fab.left');
await page.waitForTimeout(800);
await page.evaluate(() => {
  const t = [...document.querySelectorAll('.list-item .item-title-text, .img-card-title-text')]
    .find((e) => e.textContent.includes('音乐胶囊探针B'));
  if (t) t.click();
});
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(800);
const bText = await page.evaluate(() => document.querySelector('.editor-body')?.innerText || '');
ok('⑧ B 篇内容无串篇（只有 B 篇独有段落）', bText.includes('B篇独有段落') && !bText.includes('第一段文字'), bText.slice(0, 80));
await page.click('.editor-fab.left');
await page.waitForTimeout(800);
await page.evaluate(() => {
  const t = [...document.querySelectorAll('.list-item .item-title-text, .img-card-title-text')]
    .find((e) => e.textContent.trim() === '音乐胶囊探针');
  if (t) t.click();
});
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(900);
const docFinal = await readDoc(page);
const idsFinal = (docFinal || []).map((b) => b.id);
// ⑥ 解析时在 mc-cap 与 mc-mus 间补了一个空段（落点口
// 径），故终态 6 块：原五块各一次 + 新段一次、无串篇。
ok('⑧ 回 A 篇各块只出现一次、无串篇', idsFinal.length === 6 && new Set(idsFinal).size === 6
  && ['mc-p1', 'mc-p2', 'mc-cap', 'mc-mus', 'mc-p3'].every((id) => idsFinal.includes(id))
  && idsFinal.indexOf('mc-mus') === idsFinal.indexOf('mc-cap') + 2,
  JSON.stringify(idsFinal));
const docB = await readDoc(page, '音乐胶囊探针B');
ok('⑧ B 篇落盘未被扰动', !!docB && docB.length === 1 && docB[0].id === 'mc-b1', JSON.stringify(docB));

L(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
