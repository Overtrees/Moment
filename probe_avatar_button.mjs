// 专用探针：头像入口形态复原（审计 E-8(b)）关单验证。
// 背景：原版头像为 <button aria-label="更换笔记头像">，
// Rust 此前为 <label> 包 #file-avatar（靠 label 原生唤起）。
// E-8(a) 已给 label 补 aria-label；E-8(b) 把形态复原为
// button、点击经 eval 唤起 #file-avatar（与 #file-media
// 唤起同路径）。关单条件 = 本探针实跑通过：
//  ① 头像控件为 BUTTON 元素且 aria-label 正确；
//  ② 点击后 filechooser 被唤起（eval click 链成立）；
//  ③ 经 chooser 选图后头像 img 出现（pick_avatar 全链）。
// 口径说明：本探针为 Chromium 口径，证「点击→选择器→
// 落图」链完整；Safari 瞬时激活（eval click 是否被
// WebKit 认作用户手势）Chromium 测不出，终判在真机
// /WebKit——若真机不过，回退 label + aria-label 等价
// 收口并在 TESTING.md 登记。
// 用法：node probe_avatar_button.mjs [base]
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
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'pa-1', title: '头像探针', pinned: false, createdAt: ts, updatedAt: ts, doc: [{ id: 'pa1-1', type: 'paragraph', children: [{ text: '正文' }] }] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'avatar_button.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });

await page.goto(base + '?open=pa-1', { waitUntil: 'load' });
await page.waitForSelector('.editor-avatar-button', { timeout: 15000 });
await page.waitForTimeout(500);

// ① 形态：BUTTON + aria-label
const shape = await page.$eval('.editor-avatar-button', (e) => ({ tag: e.tagName, aria: e.getAttribute('aria-label') }));
ok('① 头像控件为 BUTTON', shape.tag === 'BUTTON', JSON.stringify(shape));
ok('① aria-label 为「更换笔记头像」', shape.aria === '更换笔记头像', String(shape.aria));

// ② 点击唤起 filechooser（eval click 链）
const chooserPromise = page.waitForEvent('filechooser', { timeout: 8000 }).catch(() => null);
await page.click('.editor-avatar-button');
const chooser = await chooserPromise;
ok('② 点击后 filechooser 被唤起', !!chooser);

// ③ 选图后头像 img 出现（pick_avatar 全链）
if (chooser) {
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  await chooser.setFiles({ name: 'avatar.png', mimeType: 'image/png', buffer: png });
  const got = await page.waitForSelector('.editor-avatar-button img', { timeout: 8000 }).catch(() => null);
  ok('③ 选图后头像 img 出现', !!got);
} else {
  ok('③ 选图后头像 img 出现', false, '无 chooser 可选图');
}

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
