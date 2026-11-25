// 专用探针：IDB 分条存储 + save_all 多店单事务（idb-optimize）
// 验收锁。三段：
//  ① 写放大实测：旧形态大库（40 篇 × 约 20KB）种子 → 新版
//     首启拆条迁移（Diag IDB split-migrate ok memos=40、盘
//     上 memos_json 删除、memos 店 40 条）→ 深链打开一篇真
//     实键入一字 → persist 结果行 IDB save ok up=1 del=0
//     bytes=<单篇量级> full=false（与整库量级差一个数量级
//     以上，断言 bytes ≤ 整库/8 且 ≥ 单篇下限）。
//  ② 存量迁移无损：同 profile 先以旧版 dist 跑旧库（3 篇），
//     注销 SW/清缓存后换新版 dist 打开 → split-migrate 落地、
//     组装内容与旧版落盘逐篇深相等（顺序 id 列亦相等）、列
//     表三篇标题在场；再启一次走分条路径、无 split-migrate
//     行（幂等）。
//  ③ 导入原子性：新版下以设置导入大 ZIP（25 篇 + 25 个
//     300KB 附件，拉长 save_all 单事务窗口），确认导入后
//     以不同延迟多次整页关闭（杀页），每次重开后状态必须
//     是「导入前」或「完整导入后」二者之一，绝不允许混合
//     态（篇数与附件数不匹配 / 部分篇在场）。
// 用法：node probe_idb_split.mjs [newDist] [oldDist]
//   oldDist 省略时②段以 newDist 充旧版（仅验拆条幂等，迁移
//   对照降级为同版重跑，报告中注明）。
import { webkit } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const newDist = path.resolve(process.argv[2] || path.join(root, 'rust', 'apps', 'web', 'dist'));
const oldDist = process.argv[3] ? path.resolve(process.argv[3]) : newDist;
const PORT = 8163;
const BASE = `http://localhost:${PORT}/`;
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- zipStore（stored 模式，与 probe_attachment_open 同实现） ----------
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

// ---------- 静态服务（dist 可切换） ----------
let currentDist = newDist;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
let seedPayload = null; // {memos, manifest}
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Cache-Control', 'no-store');
  if (p === '/__seed.html') {
    const html = `<!doctype html><meta charset="utf-8"><script>
const memos = ${JSON.stringify(seedPayload.memos)};
const manifest = ${JSON.stringify(seedPayload.manifest)};
const req = indexedDB.open('mynote-web', 1);
req.onupgradeneeded = () => { const db = req.result; db.createObjectStore('kv'); db.createObjectStore('attachments'); };
req.onsuccess = () => {
  const db = req.result;
  const tx = db.transaction('kv', 'readwrite');
  tx.objectStore('kv').put(memos, 'memos_json');
  tx.objectStore('kv').put(manifest, 'manifest_raw');
  tx.oncomplete = () => location.replace('/');
};
</script>seeding`;
    res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(html); return;
  }
  if (p === '/') p = '/index.html';
  const fp = path.join(currentDist, p);
  if (!fp.startsWith(currentDist) || !fs.existsSync(fp) || fs.statSync(fp).isDirectory()) { res.writeHead(404); res.end('nf'); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'application/octet-stream' });
  fs.createReadStream(fp).pipe(res);
});
await new Promise((r) => server.listen(PORT, r));

async function launch(profile) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), profile));
  const ctx = await webkit.launchPersistentContext(dir, {
    viewport: { width: 393, height: 852 },
    colorScheme: 'dark',
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Mobile/15E148 Safari/604.1',
  });
  const page = ctx.pages()[0] || (await ctx.newPage());
  return { ctx, page };
}
const readDiag = (page) => page.evaluate(() => {
  try { const v = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); return Array.isArray(v) ? v : []; } catch { return []; }
}).catch(() => []);
async function waitDiag(page, pred, timeout = 20000) {
  const t0 = Date.now(); let lines = [];
  while (Date.now() - t0 < timeout) {
    lines = await readDiag(page);
    if (pred(lines)) return lines;
    await sleep(500);
  }
  return lines;
}
// 盘上状态摘要：{legacy:boolean, meta:boolean, memoIds:[], attCount, assembled|null}
const readStore = (page) => page.evaluate(() => new Promise((resolve) => {
  const req = indexedDB.open('mynote-web');
  req.onsuccess = () => {
    const db = req.result;
    try {
      const names = [...db.objectStoreNames];
      const tx = db.transaction(names, 'readonly');
      const getKv = (key) => new Promise((r2) => { const g = tx.objectStore('kv').get(key); g.onsuccess = () => r2(g.result); g.onerror = () => r2(undefined); });
      const allKeys = (store) => new Promise((r2) => { if (!names.includes(store)) { r2([]); return; } const g = tx.objectStore(store).getAllKeys(); g.onsuccess = () => r2(g.result || []); g.onerror = () => r2([]); });
      const allVals = (store) => new Promise((r2) => { if (!names.includes(store)) { r2([]); return; } const g = tx.objectStore(store).getAll(); g.onsuccess = () => r2(g.result || []); g.onerror = () => r2([]); });
      Promise.all([getKv('memos_json'), getKv('backup_meta'), getKv('memos_order'), allKeys('memos'), allVals('memos'), allKeys('attachments')])
        .then(([legacy, meta, orderRaw, mks, mvs, aks]) => {
          let assembled = null;
          if (meta) {
            const order = JSON.parse(orderRaw || '[]');
            const byId = new Map(mks.map((k, i) => [String(k), mvs[i]]));
            const root = JSON.parse(meta);
            root.memos = order.map((id) => byId.get(String(id))).filter((v) => v !== undefined).map((v) => JSON.parse(v));
            assembled = root;
          }
          resolve({ legacy: legacy !== undefined, meta: meta !== undefined, memoIds: mks.map(String), attCount: aks.length, assembled });
        }).catch(() => resolve(null));
    } catch { resolve(null); }
  };
  req.onerror = () => resolve(null);
})).catch(() => null);

const iso = (i) => new Date(Date.UTC(2026, 0, 1 + i)).toISOString();
function makeMemo(id, title, text, i) {
  return { id, title, pinned: false, createdAt: iso(i), updatedAt: iso(i), doc: [{ id: id + '-p1', type: 'paragraph', children: [{ text }] }] };
}

// ═══════ ① 写放大实测 ═══════
{
  const N = 40, PER = 20000;
  const memos = Array.from({ length: N }, (_, i) => makeMemo('amp-' + String(i).padStart(2, '0'), 'amp ' + i, 'x'.repeat(PER), i));
  const legacyJson = JSON.stringify({ version: 2, memos });
  const totalBytes = legacyJson.length;
  seedPayload = { memos: legacyJson, manifest: '{"version":1,"attachments":{}}' };
  currentDist = newDist;
  const { ctx, page } = await launch('idbsplit-amp-');
  await page.goto(BASE + '__seed.html', { waitUntil: 'load' }).catch(() => {});
  let lines = await waitDiag(page, (ls) => ls.some((l) => l.includes('persisted state applied')));
  ok('① 首启拆条迁移落地', lines.some((l) => l.includes('IDB split-migrate ok memos=40')), lines.find((l) => l.includes('split-migrate')) || '');
  ok('① loaded persisted memos=40', lines.some((l) => l.includes('loaded persisted memos=40')));
  const st = await readStore(page);
  ok('① 盘上旧全量键已删', st && st.legacy === false);
  ok('① 信封在位、memos 店 40 条', st && st.meta === true && st.memoIds.length === 40, st ? `meta=${st.meta} n=${st.memoIds.length}` : 'readStore null');
  // 深链打开一篇并真实键入
  const off = (await readDiag(page)).length;
  await page.goto(BASE + '?open=amp-07', { waitUntil: 'load' }).catch(() => {});
  lines = await waitDiag(page, (ls) => ls.slice(off).some((l) => l.includes('EDIT page enter')), 15000);
  ok('① 深链打开 amp-07 进编辑器', lines.slice(off).some((l) => l.includes('EDIT page enter')));
  const para = page.locator('.editor-body [data-bid]').first();
  await para.click().catch(() => {});
  await page.keyboard.type('Z');
  lines = await waitDiag(page, (ls) => ls.slice(off).some((l) => /IDB save ok up=1 del=0 bytes=\d+ full=false/.test(l)), 15000);
  const saveLine = lines.slice(off).filter((l) => l.includes('IDB save ok')).pop() || '';
  const m = saveLine.match(/bytes=(\d+)/);
  const bytes = m ? Number(m[1]) : -1;
  ok('① 单篇编辑 persist 为增量行', !!m, saveLine);
  ok('① 写入字节为单篇量级（≥15KB 且 ≤整库/8）', bytes >= 15000 && bytes <= totalBytes / 8, `bytes=${bytes} total=${totalBytes} ratio=${(totalBytes / Math.max(bytes, 1)).toFixed(1)}x`);
  ok('① 无 full=true 写行（迁移后）', !lines.slice(off).some((l) => l.includes('IDB save ok') && l.includes('full=true')), lines.slice(off).filter((l) => l.includes('IDB save')).join(' | '));
  await ctx.close();
}

// ═══════ ② 存量迁移无损（旧版 → 新版） ═══════
{
  const memos = [makeMemo('mig-a', '迁移甲', '甲篇正文', 1), makeMemo('mig-b', '迁移乙', '乙篇正文', 2), makeMemo('mig-c', '迁移丙', '丙篇正文', 3)];
  seedPayload = { memos: JSON.stringify({ version: 2, memos }), manifest: '{"version":1,"attachments":{}}' };
  currentDist = oldDist;
  const { ctx, page } = await launch('idbsplit-mig-');
  await page.goto(BASE + '__seed.html', { waitUntil: 'load' }).catch(() => {});
  let lines = await waitDiag(page, (ls) => ls.some((l) => l.includes('persisted state applied')));
  ok('② 旧版加载旧库成功', lines.some((l) => l.includes('loaded persisted memos=3')));
  const before = await page.evaluate(() => new Promise((resolve) => {
    const req = indexedDB.open('mynote-web');
    req.onsuccess = () => {
      const g = req.result.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
      g.onsuccess = () => resolve(g.result || '');
      g.onerror = () => resolve('');
    };
    req.onerror = () => resolve('');
  })).catch(() => '');
  let beforeMemos = null;
  try { beforeMemos = JSON.parse(before).memos; } catch { /* keep null */ }
  ok('② 旧版落盘快照取得（3 篇）', Array.isArray(beforeMemos) && beforeMemos.length === 3);
  // 注销 SW + 清缓存，切新版 dist（IDB 不动）
  await page.evaluate(async () => {
    for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister();
    for (const k of await caches.keys()) await caches.delete(k);
  }).catch(() => {});
  const off = (await readDiag(page)).length;
  currentDist = newDist;
  await page.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  lines = await waitDiag(page, (ls) => ls.slice(off).some((l) => l.includes('persisted state applied')), 20000);
  const seg = lines.slice(off);
  ok('② 新版首启 split-migrate ok memos=3', seg.some((l) => l.includes('IDB split-migrate ok memos=3')), seg.find((l) => l.includes('split-migrate')) || '');
  ok('② 新版加载 3 篇', seg.some((l) => l.includes('loaded persisted memos=3')));
  const st = await readStore(page);
  ok('② 旧键已清、分条 3 条', st && st.legacy === false && st.memoIds.length === 3, st ? `legacy=${st.legacy} n=${st.memoIds.length}` : 'null');
  let same = false, orderSame = false;
  if (st && st.assembled && beforeMemos) {
    const byId = (arr) => Object.fromEntries(arr.map((x) => [String(x.id), JSON.stringify(x)]));
    const a = byId(beforeMemos), b = byId(st.assembled.memos || []);
    same = JSON.stringify(Object.keys(a).sort()) === JSON.stringify(Object.keys(b).sort()) && Object.keys(a).every((k) => a[k] === b[k]);
    orderSame = JSON.stringify((st.assembled.memos || []).map((x) => String(x.id))) === JSON.stringify(beforeMemos.map((x) => String(x.id)));
  }
  ok('② 组装内容与旧版落盘逐篇深相等', same);
  ok('② 篇目顺序保持', orderSame);
  const bodyText = await page.evaluate(() => document.body.innerText).catch(() => '');
  ok('② 列表三篇标题在场', ['迁移甲', '迁移乙', '迁移丙'].every((t) => bodyText.includes(t)));
  // 再启：走分条路径、幂等
  const off2 = (await readDiag(page)).length;
  await page.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  lines = await waitDiag(page, (ls) => ls.slice(off2).some((l) => l.includes('persisted state applied')), 20000);
  const seg2 = lines.slice(off2);
  ok('② 再启 loaded memos=3', seg2.some((l) => l.includes('loaded persisted memos=3')));
  ok('② 再启无 split-migrate 行（幂等）', !seg2.some((l) => l.includes('split-migrate')), seg2.find((l) => l.includes('split-migrate')) || '');
  await ctx.close();
}

// ═══════ ③ 导入原子性（中途杀页） ═══════
{
  const baseMemos = [makeMemo('base-a', '基线甲', '基线正文甲', 1), makeMemo('base-b', '基线乙', '基线正文乙', 2), makeMemo('base-c', '基线丙', '基线正文丙', 3)];
  seedPayload = { memos: JSON.stringify({ version: 2, memos: baseMemos }), manifest: '{"version":1,"attachments":{}}' };
  currentDist = newDist;
  const { ctx, page } = await launch('idbsplit-atom-');
  await page.goto(BASE + '__seed.html', { waitUntil: 'load' }).catch(() => {});
  let lines = await waitDiag(page, (ls) => ls.some((l) => l.includes('persisted state applied')));
  ok('③ 基线库就绪（3 篇）', lines.some((l) => l.includes('loaded persisted memos=3')));
  // 大 ZIP：25 篇 + 25 个 300KB 附件
  const NM = 25;
  const impMemos = Array.from({ length: NM }, (_, i) => makeMemo('imp-' + i, '导入篇' + i, '导入正文' + i, 10 + i));
  const atts = {};
  const files = [];
  for (let i = 0; i < NM; i++) { atts['imp-att-' + i] = { name: 'f' + i + '.bin', type: 'application/octet-stream' }; }
  const bigZip = zipStore([
    { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: new Date().toISOString(), memos: impMemos, avatars: {} }) },
    { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: atts }) },
    ...Object.keys(atts).map((id) => ({ name: 'attachments/' + id, data: Buffer.alloc(300 * 1024, 0x43) })),
  ]);
  files.push(bigZip);
  const summarize = async (pg) => {
    const st = await readStore(pg);
    if (!st || !st.assembled) return null;
    return { n: st.memoIds.length, atts: st.attCount, titles: (st.assembled.memos || []).map((x) => x.title) };
  };
  const isBase = (s) => s && s.n === 3 && s.atts === 0 && ['基线甲', '基线乙', '基线丙'].every((t) => s.titles.includes(t));
  const isFull = (s) => s && s.n === NM && s.atts === NM && s.titles.filter((t) => String(t).startsWith('导入篇')).length === NM;
  let pg = page;
  for (const delay of [40, 150, 400]) {
    // 每次尝试前确认处于基线态（若已完整导入则先正常导入基线 ZIP 复位）
    let pre = await summarize(pg);
    if (!isBase(pre)) {
      const baseZip = zipStore([
        { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: new Date().toISOString(), memos: baseMemos, avatars: {} }) },
        { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
      ]);
      await importViaUi(pg, baseZip);
      pre = await summarize(pg);
    }
    ok(`③ 杀页尝试前为基线态（delay=${delay}）`, isBase(pre), JSON.stringify(pre && { n: pre.n, atts: pre.atts }));
    // 发起导入 → 延迟 → 整页关闭（杀页）
    await openImport(pg);
    await pg.setInputFiles('#file-import', { name: 'big.zip', mimeType: 'application/zip', buffer: bigZip });
    await pg.waitForSelector('.backup-modal', { timeout: 10000 });
    await pg.click('.backup-modal .backup-btn.primary');
    await sleep(delay);
    await pg.close().catch(() => {});
    pg = await ctx.newPage();
    await pg.goto(BASE, { waitUntil: 'load' }).catch(() => {});
    await waitDiag(pg, (ls) => ls.some((l) => l.includes('persisted state applied')), 20000);
    const post = await summarize(pg);
    ok(`③ 杀页后状态为基线或完整导入（delay=${delay}）`, isBase(post) || isFull(post), JSON.stringify(post && { n: post.n, atts: post.atts }));
    ok(`③ 杀页后无混合态（delay=${delay}）`, !(post && !isBase(post) && !isFull(post)), JSON.stringify(post && { n: post.n, atts: post.atts, titles: post.titles.slice(0, 3) }));
  }
  await ctx.close();
}

async function openImport(pg) {
  await pg.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  await pg.waitForSelector('.list-item', { timeout: 20000 });
  await pg.$eval('h1.page-title', (e) => e.click());
  await pg.waitForSelector('.page-content', { timeout: 8000 });
  await pg.click('.set-row:has-text("备份与恢复")');
  await pg.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
}
async function importViaUi(pg, zip) {
  await openImport(pg);
  await pg.setInputFiles('#file-import', { name: 'base.zip', mimeType: 'application/zip', buffer: zip });
  await pg.waitForSelector('.backup-modal', { timeout: 10000 });
  await pg.click('.backup-modal .backup-btn.primary');
  await pg.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 30000 });
  await pg.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  await waitDiag(pg, (ls) => ls.some((l) => l.includes('persisted state applied')), 20000);
}

await ctxCleanup();
async function ctxCleanup() { /* contexts closed inline */ }
server.close();
L(fails === 0 ? 'ALL PASS' : `FAILED ${fails}`);
process.exit(fails === 0 ? 0 : 1);
