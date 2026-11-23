// 探针（Rust）：C-30 URL 协议白名单——原版 safeHttpUrl/
// safeImageUrl 只许 http(s)（图片另许 data:image 白名单），
// Rust 多处把 extra.url 原样写 href/src，javascript: 可点
// 触发。断言：渲染面无危险协议 href/src、正常链接/图片不
// 受影响；HTML 导出同样无危险协议。Chromium 口径。
// 用法：node probe_link_safety.mjs [base]
import { chromium } from 'playwright-core';
import { writeFileSync } from 'node:fs';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xFFFFFFFF; for (const b of buf) c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zipStore(files) {
  const enc = new TextEncoder();
  const chunks = []; const central = []; let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name); const data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
    const crc = crc32(data); const size = data.length;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
    lh.setUint32(14, crc, true); lh.setUint32(18, size, true); lh.setUint32(22, size, true);
    lh.setUint16(26, name.length, true);
    chunks.push(Buffer.from(lh.buffer), Buffer.from(name), Buffer.from(data));
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, 0x0800, true);
    ch.setUint32(16, crc, true); ch.setUint32(20, size, true); ch.setUint32(24, size, true);
    ch.setUint16(28, name.length, true); ch.setUint32(42, offset, true);
    central.push(Buffer.from(ch.buffer), Buffer.from(name));
    offset += 30 + name.length + size;
  }
  const cdSize = central.reduce((a, c) => a + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}

const now = new Date();
const ts = now.toISOString();
const PNG1_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const DATA_PNG = 'data:image/png;base64,' + PNG1_B64;
const doc = [
  { id: 'lc-bad', type: 'link-card', url: 'javascript:alert(1)', meta: { title: '坏卡标题', source: 'evil' }, children: [] },
  { id: 'lc-err', type: 'link-card', url: 'javascript:alert(2)', children: [] },
  { id: 'lc-ok', type: 'link-card', url: 'https://example.com/page', meta: { title: '好卡标题', source: 'example', cover: 'https://example.com/c.png' }, children: [] },
  { id: 'mc-bad', type: 'musicCard', url: 'javascript:alert(3)', status: 'ready', meta: { title: '坏歌', cover: 'https://example.com/m.png' }, children: [] },
  { id: 'img-bad', type: 'image', url: 'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==', children: [] },
  { id: 'img-ok', type: 'image', url: DATA_PNG, children: [] },
  { id: 'md-links', type: 'paragraph', children: [{ text: '[坏链](javascript:alert(4)) [好链](https://example.com) [邮链](mailto:a@b.c)' }] },
  { id: 'md-img', type: 'paragraph', children: [{ text: '![坏图](javascript:alert(5)) ![好图](' + DATA_PNG + ')' }] },
  { id: 'node-link', type: 'paragraph', children: [{ text: '前' }, { type: 'link', url: 'javascript:alert(6)', children: [{ text: '节点坏链' }] }, { text: '后' }] },
];
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'sec1', title: '链接安全', pinned: false, createdAt: ts, updatedAt: ts, doc },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
page.on('download', (d) => d.cancel().catch(() => {}));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'link_safety.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.goto(base + '?open=sec1', { waitUntil: 'load' });
await page.waitForSelector('.editor-body .blk-wrap', { timeout: 15000 });
await page.waitForTimeout(1500);

const DANGER = /^\s*(javascript|data|vbscript|file):/i;
const render = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const hrefs = [...body.querySelectorAll('a')].map((a) => a.getAttribute('href'));
  const srcs = [...body.querySelectorAll('img')].map((i) => i.getAttribute('src') || '');
  const byText = (t) => [...body.querySelectorAll('a')].find((a) => (a.textContent || '').includes(t));
  return {
    hrefs, srcs,
    goodCard: byText('好卡标题')?.getAttribute('href') ?? null,
    goodMd: byText('好链')?.getAttribute('href') ?? null,
    mailMd: byText('邮链')?.getAttribute('href') ?? null,
    badMdAnchor: !!byText('坏链'),
    musicTitleShown: (body.textContent || '').includes('坏歌'),
    nodeLinkTextShown: (body.textContent || '').includes('节点坏链'),
    imgOkSrc: srcs.find((s) => s.startsWith('data:image/png')) || null,
    imgBadRendered: srcs.some((s) => s.startsWith('data:text/html')),
  };
});
L('HREFS:', JSON.stringify(render.hrefs));
L('SRCS:', JSON.stringify(render.srcs.map((s) => s.slice(0, 40))));
ok('渲染面无危险协议 href', !render.hrefs.some((h) => h && DANGER.test(h)), JSON.stringify(render.hrefs.filter((h) => h && DANGER.test(h))));
ok('渲染面无危险协议 img src', !render.srcs.some((s) => /^\s*(javascript|vbscript):/i.test(s) || s.startsWith('data:text')), '');
ok('正常链接卡 href 不受影响', render.goodCard === 'https://example.com/page', String(render.goodCard));
ok('md 正常链接 href 不受影响', render.goodMd === 'https://example.com', String(render.goodMd));
ok('md mailto 链接保留', render.mailMd === 'mailto:a@b.c', String(render.mailMd));
ok('图片块 data:image 正常渲染', !!render.imgOkSrc);
ok('图片块 data:text 未渲染为 img', !render.imgBadRendered);
ok('音乐卡标题仍渲染', render.musicTitleShown);
ok('行内链接节点文本仍渲染', render.nodeLinkTextShown);

// ---------- HTML 导出面 ----------
const dlPromise = page.waitForEvent('download', { timeout: 20000 }).catch(() => null);
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
await page.waitForTimeout(400);
await page.click('[data-export-format="html"]');
const dl = await dlPromise;
ok('HTML 导出下载触发', !!dl);
if (dl) {
  const p = '/tmp/link_safety_export.html';
  await dl.saveAs(p);
  const { readFileSync } = await import('node:fs');
  const html = readFileSync(p, 'utf8');
  writeFileSync('/tmp/link_safety_export_kept.html', html);
  ok('导出 HTML 无 javascript: href', !/href="[^"]*javascript:/i.test(html));
  ok('导出 HTML 无 data:text src/href', !/(src|href)="data:text/i.test(html));
  ok('导出 HTML 保留正常链接卡 href', html.includes('href="https://example.com/page"'));
  ok('导出 HTML 保留链接文本（节点坏链）', html.includes('节点坏链'));
  ok('导出 HTML 保留 data:image 图片', html.includes('data:image/png;base64'));
}
await browser.close();
L(fails ? `RESULT: ${fails} FAIL` : 'RESULT: ALL PASS');
process.exit(fails ? 1 : 0);
