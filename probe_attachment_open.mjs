// 专用探针：附件卡「打开」按钮 → 系统分享链（附件打开根治验证）。
// 背景：原版附件卡点 .att-hint 在手势内同步以内存中的文件数据
// 构造 File → canShare 判定 → navigator.share({files, title})，
// 不过则 <a download> 降级下载。Rust 版此前从未移植该链：点击
// 后 spawn 异步读 IDB → blob_url → window.open(_blank)，await
// 之后手势激活已失效、Safari 静默拦截且返回值被丢弃，真机表
// 现为「点击无效」；且 Diag 只有 intention 行、失败不留痕。
// 本探针以桩记录 App 侧链路（headless Chromium 的 Web Share
// 本身不可用，桩口径见下），关单条件：
//  ① PDF 附件行渲染（文件名查 manifest、hint 为「点击打开」）；
//  ② 点 hint → navigator.share 被以正确 File 调用（name/type/
//     size 与 manifest 及附件字节一致、title=文件名），且
//     canShare 先行判定；window.open 不得被用于附件打开；
//  ③ Diag 出现结果侧 ATT 行记录分享结局（shared）；
//  ④ 音乐文件行（musicCard+fileId）点 hint 同链分享音频 File；
//  ⑤ 图片附件仍渲染为图、点击开图片页（既有行为不回归）；
//  ⑥ canShare=false 时降级为下载（a[download] 以文件名触发、
//     不调 share）——原版兜底口径；
//  ⑦ 附件行点按后的菜单→BgSheet 链（diagnose_bgsheet_after_att
//     确诊回归锁）：长备忘打字获焦 → 滚动到附件行 → 真 tap 点行
//     （Diag ATT -> download）→ 开编辑菜单，菜单须留存（不被 S8
//     失焦回顶的编排滚动误关）→ 点「更换背景色」→ .bg-sheet
//     出现且 Diag 记 menu closed -> bg sheet。
// 口径说明：桩记录证「App 在手势内同步发起 share 且参数正
// 确」；Safari 的瞬时激活判定 Chromium 测不出，终判在真机
// （Diag ATT 结果行 + 用户复测）。
// 用法：node probe_attachment_open.mjs [base]
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

const pdfBytes = Buffer.concat([Buffer.from('%PDF-1.4 probe\n'), Buffer.alloc(2000, 0x41)]);
const pngBytes = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const mp3Bytes = Buffer.concat([Buffer.from('ID3 probe'), Buffer.alloc(500, 0x42)]);
const ts = new Date().toISOString();
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'pao-1', title: '附件打开探针', pinned: false, createdAt: ts, updatedAt: ts, doc: [
      { id: 'pao-p1', type: 'paragraph', children: [{ text: '附件打开链探针' }] },
      { id: 'pao-a1', type: 'attachment', attrs: { fileId: 'att-pdf-1' }, name: '季度报告.pdf', status: 'done', image: false },
      { id: 'pao-a2', type: 'attachment', attrs: { fileId: 'att-img-1' }, image: true },
      { id: 'pao-a3', type: 'musicCard', attrs: { fileId: 'att-mp3-1' } },
    ] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {
    'att-pdf-1': { name: '季度报告.pdf', type: 'application/pdf' },
    'att-img-1': { name: '照片.png', type: 'image/png' },
    'att-mp3-1': { name: '演示音频.mp3', type: 'audio/mpeg' },
  } }) },
  { name: 'attachments/att-pdf-1', data: pdfBytes },
  { name: 'attachments/att-img-1', data: pngBytes },
  { name: 'attachments/att-mp3-1', data: mp3Bytes },
]);

// 桩：记录 App 侧对 share/canShare/window.open/下载锚的调用。
// canShareResult 可配（⑥ 用 false 验降级）。
function stubJS(canShareResult) {
  return `
    window.__attProbe = { share: [], canShare: [], open: [], downloads: [] };
    Object.defineProperty(navigator, 'share', { configurable: true, value: (data) => {
      window.__attProbe.share.push({ title: data.title || null, files: (data.files || []).map(f => ({ name: f.name, type: f.type, size: f.size })) });
      return Promise.resolve();
    } });
    Object.defineProperty(navigator, 'canShare', { configurable: true, value: (data) => {
      window.__attProbe.canShare.push({ nfiles: (data.files || []).length });
      return ${canShareResult ? 'true' : 'false'};
    } });
    window.open = (url, target) => { window.__attProbe.open.push({ url: String(url).slice(0, 80), target: target || null }); return null; };
    const origAClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () {
      if (this.download) window.__attProbe.downloads.push({ name: this.download, href: String(this.href).slice(0, 30) });
      return origAClick.call(this);
    };
  `;
}

async function seedAndOpen(canShareResult) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
  await page.addInitScript(stubJS(canShareResult));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'att_open.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=pao-1', { waitUntil: 'load' });
  await page.waitForSelector('.attachment-file', { timeout: 15000 });
  await page.waitForTimeout(800);
  return { ctx, page };
}

async function diagAtt(page) {
  // Diag 落盘 1s 节流（批 10）：轮询等结果侧 ATT 行落盘。
  // 存储形态为 JSON 数组（每元素一行 "[HH:MM:SS] TAG msg"）。
  const read = () => page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch { return []; }
  }).then((lines) => lines.filter((s) => s.includes('] ATT ')));
  for (let i = 0; i < 12; i++) {
    const att = await read();
    if (att.some((s) => /-> (shared|download|cancelled|error|missing)/.test(s))) return att;
    await page.waitForTimeout(400);
  }
  return read();
}

// ===== 主场景：canShare=true =====
{
  const { ctx, page } = await seedAndOpen(true);
  const pdfRow = page.locator('.attachment-file', { hasText: '季度报告.pdf' });
  ok('① PDF 附件行渲染、文件名=季度报告.pdf', await pdfRow.count() === 1);
  const hint = pdfRow.locator('.att-hint');
  ok('① att-hint 为「点击打开」', (await hint.innerText()) === '点击打开', await hint.innerText());

  await hint.tap();
  await page.waitForTimeout(600);
  const probe = await page.evaluate(() => window.__attProbe);
  L('  stub:', JSON.stringify(probe));
  const sh = probe.share[0];
  ok('② 点打开 → navigator.share 被调用一次', probe.share.length === 1, `share=${probe.share.length}`);
  ok('② File name/type/size 正确', !!sh && sh.files.length === 1 && sh.files[0].name === '季度报告.pdf' && sh.files[0].type === 'application/pdf' && sh.files[0].size === pdfBytes.length, JSON.stringify(sh && sh.files));
  ok('② share title=文件名', !!sh && sh.title === '季度报告.pdf', sh && sh.title);
  ok('② canShare 先行判定', probe.canShare.length >= 1, `canShare=${probe.canShare.length}`);
  ok('② window.open 未被用于附件打开', probe.open.length === 0, JSON.stringify(probe.open));

  const att = await diagAtt(page);
  L('  diag ATT:', JSON.stringify(att));
  ok('③ Diag 结果侧 ATT 行记录 share 结局（att-pdf-1 shared）', att.some((s) => s.includes('att-pdf-1') && s.includes('-> shared')), att.join(' | '));

  // ④ 音乐文件行
  const mp3Row = page.locator('.attachment-file', { hasText: '演示音频.mp3' });
  ok('④ 音乐文件行渲染', await mp3Row.count() === 1);
  await mp3Row.locator('.att-hint').tap();
  await page.waitForTimeout(600);
  const probe2 = await page.evaluate(() => window.__attProbe);
  const sh2 = probe2.share[1];
  ok('④ 音乐行点打开 → share 音频 File', !!sh2 && sh2.files.length === 1 && sh2.files[0].name === '演示音频.mp3' && sh2.files[0].type === 'audio/mpeg' && sh2.files[0].size === mp3Bytes.length, JSON.stringify(probe2.share));

  // ⑤ 图片附件 → 图片页（既有行为；触摸 tap 与真机同路）
  const imgRect = await page.evaluate(() => {
    const el = document.querySelector('.atomic.attachment img');
    const b = el.getBoundingClientRect();
    return [b.x + b.width / 2, b.y + b.height / 2];
  });
  await page.touchscreen.tap(imgRect[0], imgRect[1]);
  const imgPage = await page.waitForSelector('.img-page', { timeout: 8000 }).catch(() => null);
  ok('⑤ 图片附件点击开图片页', !!imgPage);
  await ctx.close();
}

// ===== ⑥ 降级场景：canShare=false → 下载兜底 =====
{
  const { ctx, page } = await seedAndOpen(false);
  const pdfRow = page.locator('.attachment-file', { hasText: '季度报告.pdf' });
  await pdfRow.locator('.att-hint').tap();
  await page.waitForTimeout(600);
  const probe = await page.evaluate(() => window.__attProbe);
  L('  stub(⑥):', JSON.stringify(probe));
  ok('⑥ canShare=false 时不调 share', probe.share.length === 0, `share=${probe.share.length}`);
  ok('⑥ 降级下载以文件名触发', probe.downloads.length >= 1 && probe.downloads[0].name === '季度报告.pdf', JSON.stringify(probe.downloads));
  await ctx.close();
}

// ===== ⑦ 附件行点按后菜单→BgSheet 链（S8 编排滚动误关菜单回归锁） =====
// 确诊（diagnose_bgsheet_after_att.md）：可编辑块获焦且页面已滚动时，
// 点 fab 开菜单使块失焦、触发桥 S8 回顶 window.scrollTo(0,0)；该编排
// 滚动曾被滚动订阅当作用户滚动、以 MenuAfter::None 关掉刚打开的菜单
// 并作废待定的 Bg 去向——菜单「正常关闭」、底表永不出现。修复后滚动
// 订阅区分 prog（编排）与用户滚动。本段以真实手势走完整链锁定。
{
  const paras = [];
  for (let i = 0; i < 24; i++) paras.push({ id: 'pao2-p' + i, type: 'paragraph', children: [{ text: '底表链长备忘段落 ' + i + ' 内容内容内容内容内容内容' }] });
  const longZip = zipStore([
    { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
      { id: 'pao-2', title: '附件底表链探针', pinned: false, createdAt: ts, updatedAt: ts, doc: [
        ...paras,
        { id: 'pao2-a1', type: 'attachment', attrs: { fileId: 'att-pdf-1' }, name: '季度报告.pdf', status: 'done', image: false },
      ] },
    ], avatars: {} }) },
    { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {
      'att-pdf-1': { name: '季度报告.pdf', type: 'application/pdf' },
    } }) },
    { name: 'attachments/att-pdf-1', data: pdfBytes },
  ]);
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
  await page.addInitScript(stubJS(false));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'att_bg.zip', mimeType: 'application/zip', buffer: longZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=pao-2', { waitUntil: 'load' });
  await page.waitForSelector('.attachment-file', { timeout: 15000 });
  await page.waitForTimeout(800);

  // 打字获焦（可编辑块持有焦点 = S8 触发态的一半）
  await page.click('.detail .ed-line >> nth=0');
  await page.keyboard.press('End');
  await page.keyboard.type('X');
  await page.waitForTimeout(400);
  // 滚动到附件行（sy>0 = 触发态另一半）
  await page.evaluate(() => document.querySelector('#editor-root .attachment-file')?.scrollIntoView({ block: 'center' }));
  await page.waitForTimeout(700);
  const sy = await page.evaluate(() => Math.round(window.scrollY));
  ok('⑦ 前置：编辑器已滚动（sy>100）', sy > 100, `sy=${sy}`);
  // 真 tap 点附件行 → 下载兜底
  const row = page.locator('.attachment-file', { hasText: '季度报告.pdf' });
  const box = await row.boundingBox();
  await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
  const att = await diagAtt(page);
  ok('⑦ 附件行点按走下载兜底（Diag ATT -> download）', att.some((s) => s.includes('att-pdf-1') && s.includes('-> download')), att.join(' | '));
  // 开菜单：fab 点按使获焦块失焦、S8 回顶——菜单必须留存
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 12000 });
  await page.waitForTimeout(800);
  ok('⑦ 菜单打开后留存（不被编排滚动误关）', !!(await page.$('.editor-menu-panel')));
  // 点更换背景色 → 底表必须挂载
  await page.locator('.editor-menu-panel .menu-item:has-text("更换背景色")').click();
  const sheet = await page.waitForSelector('.bg-sheet', { timeout: 8000 }).catch(() => null);
  ok('⑦ 更换背景色 → BgSheet 底表出现', !!sheet);
  // Diag 结果行：menu closed -> bg sheet（轮询等 1s 节流落盘）
  const readEdit = () => page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch { return []; }
  });
  let bgLine = false;
  for (let i = 0; i < 12 && !bgLine; i++) {
    const lines = await readEdit();
    bgLine = lines.some((s) => s.includes('menu closed -> bg sheet'));
    if (!bgLine) await page.waitForTimeout(400);
  }
  ok('⑦ Diag 记 menu closed -> bg sheet', bgLine);
  await ctx.close();
}

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
