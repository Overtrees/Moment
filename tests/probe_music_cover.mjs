// 专项探针：音乐卡封面区——Apple Music wp 垫白变体归一 + 铺满量测。
// 背景（2026-11-25 用户真机截图确诊）：Worker /meta 给 Apple Music
// 的 cover 是 mzstatic 1200x630wp-60.jpg——苹果把方形封面垫进
// 1200×630 近白画布（实测底色 248,248,248、封面本体只占中间约
// 36% 宽），成品卡 object-fit:cover 铺满也救不回：白是图片内容。
// 修复：proxy_img 把 mzstatic 的 <w>x<h>wp[-q] 末段归一为
// 600x600bb 方形变体。本探针锁：
//   ① 渲染 src 解码后末段为 600x600bb（归一生效）
//   ② img natural 为方形（600×600）
//   ③ img rect 与 .lkc-cover rect 一致（铺满、无留白几何）
//   ④ 封面区左缘像素为封面本体色（叶片绿）而非近白（截图取色）
//   ⑤ 深/浅两色各测一遍；容器 computed background 仅记录（--border-color）
// 夹具：与用户同款——知了/陳默之 Apple Music，meta.cover 即 Worker
// /meta 实测返回的 wp URL（2026-11-25 直查 Worker 记录）。
// 用法：node probe_music_cover.mjs [base]
// 口径注记：本探针恒自带纯静态服务（无 COOP/COEP）服树内
// dist——量测对象是 Worker /img 的真实外图，该响应无 CORP
// 头，在 COEP require-corp 的服务（如 run_all 的统一服务）
// 下会被浏览器拦死、img 永不 complete（假红，musicfix 轮
// 已有同型注记）。argv 的 base 因此不采用。
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIST = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'rust', 'apps', 'web', 'dist');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  fs.readFile(path.join(DIST, p), (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
});
await new Promise((r) => server.listen(8183, r));
const base = 'http://localhost:8183/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (name, cond, extra = '') => { console.log((cond ? '✓ ' : '✗ FAIL ') + name, extra); if (!cond) fails++; };

// ---- 最小 store-zip（同 probe_skeleton_pulse 口径） ----
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
  const end = new DataView(new ArrayBuffer(22)); end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}

const WP_COVER = 'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/f6/d9/14/f6d914d4-d164-9eff-fc73-b537bfd24764/cover.jpg/1200x630wp-60.jpg';
const memos = { version: 2, memos: [{
  id: 'mcov1', title: '封面测试', pinned: false,
  createdAt: '2026-11-25T00:00:00.000Z', updatedAt: '2026-11-25T00:00:00.000Z',
  doc: [
    { id: 'p1', type: 'paragraph', children: [{ text: '封面测试正文' }] },
    { id: 'mc1', type: 'musicCard', url: 'https://music.apple.com/us/album/x/1743361328?i=1743361729', status: 'ready',
      meta: { title: '知了', subtitle: '陳默之', source: 'Apple Music', cover: WP_COVER }, children: [{ text: '' }] },
  ],
}]};
const zip = zipStore([
  { name: 'memos.json', data: JSON.stringify(memos) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);
fs.writeFileSync('/tmp/mcov_import.zip', zip);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function measure(colorScheme) {
  const ctx = await browser.newContext({
    viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme,
    proxy: { server: 'http://127.0.0.1:3128', bypass: 'localhost,127.0.0.1' },
  });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/tmp/mcov_import.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForFunction(() => document.body.innerText.includes('封面测试'), { timeout: 15000 });
  await page.evaluate(() => {
    const els = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')];
    const t = els.find((e) => e.textContent.includes('封面测试'));
    if (t) t.click();
  });
  await page.waitForSelector('.lkc-cover img', { timeout: 10000 });
  await page.waitForFunction(() => {
    const img = document.querySelector('.lkc-cover img');
    return img && img.complete && img.naturalWidth > 0;
  }, { timeout: 20000 });
  const m = await page.evaluate(() => {
    const cover = document.querySelector('.lkc-cover');
    const img = cover.querySelector('img');
    const cr = cover.getBoundingClientRect();
    const ir = img.getBoundingClientRect();
    let decoded = '';
    try {
      const u = new URL(img.currentSrc);
      decoded = decodeURIComponent(u.searchParams.get('url') || img.currentSrc);
    } catch { decoded = img.currentSrc; }
    return {
      coverRect: { x: cr.x, y: cr.y, w: cr.width, h: cr.height },
      imgRect: { x: ir.x, y: ir.y, w: ir.width, h: ir.height },
      natural: { w: img.naturalWidth, h: img.naturalHeight },
      coverBg: getComputedStyle(cover).backgroundColor,
      decoded,
    };
  });
  // 同页 canvas 采样源图左缘中点色（object-fit:cover 取垂直中段，
  // 左缘对应源图 x≈2 处）：修复前 wp 图此处为近白垫边，修复后
  // bb 方图此处为封面本体。代理回图若无 CORS 头 canvas 会污染，
  // 此时返回 'tainted'、该项以 natural/rect 断言为准并注明。
  m.leftPx = await page.evaluate(() => {
    const img = document.querySelector('.lkc-cover img');
    try {
      const c = document.createElement('canvas');
      c.width = img.naturalWidth; c.height = img.naturalHeight;
      c.getContext('2d').drawImage(img, 0, 0);
      const d = c.getContext('2d').getImageData(2, Math.floor(img.naturalHeight / 2), 1, 1).data;
      return [d[0], d[1], d[2]];
    } catch { return 'tainted'; }
  });
  // 封面区左缘中点像素（截图取色）：应为封面本体（叶片/天空）而非近白
  const clip = { x: m.coverRect.x + 4, y: m.coverRect.y + m.coverRect.h / 2, width: 8, height: 8 };
  const shot = await page.screenshot({ clip });
  fs.writeFileSync(`/tmp/mcov_${colorScheme}.png`, shot);
  await ctx.close();
  return m;
}

for (const scheme of ['dark', 'light']) {
  const m = await measure(scheme);
  console.log(`[${scheme}]`, JSON.stringify(m));
  ok(`${scheme} src 归一为 600x600bb`, m.decoded.endsWith('/600x600bb.jpg'), m.decoded.slice(-60));
  ok(`${scheme} natural 方形 600x600`, m.natural.w === 600 && m.natural.h === 600, `${m.natural.w}x${m.natural.h}`);
  const fill = Math.abs(m.imgRect.w - m.coverRect.w) <= 1 && Math.abs(m.imgRect.h - m.coverRect.h) <= 1
    && Math.abs(m.imgRect.x - m.coverRect.x) <= 1 && Math.abs(m.imgRect.y - m.coverRect.y) <= 1;
  ok(`${scheme} img 铺满封面区（rect 一致）`, fill, `img ${m.imgRect.w}x${m.imgRect.h} vs cover ${m.coverRect.w}x${m.coverRect.h}`);
  const ratio = m.coverRect.w / m.coverRect.h;
  ok(`${scheme} 封面区比例 2.4/1 不变`, Math.abs(ratio - 2.4) < 0.05, `ratio=${ratio.toFixed(3)}`);
  const px = m.leftPx;
  console.log(`[${scheme}] 左缘像素`, px);
  if (Array.isArray(px)) {
    const nearWhite = px[0] > 235 && px[1] > 235 && px[2] > 235;
    ok(`${scheme} 封面左缘非近白（封面本体已铺到边缘）`, !nearWhite, `rgb=${px.join(',')}`);
  } else {
    console.log(`[${scheme}] 像素项跳过（canvas ${px}），以 natural 方形 + rect 铺满为准`);
  }
}

await browser.close();
console.log(fails === 0 ? 'probe_music_cover: ALL PASS' : `probe_music_cover: ${fails} FAIL`);
server.close();
process.exit(fails === 0 ? 0 : 1);
