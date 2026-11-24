// 专用探针：首页点击死亡故障（2026-11-24 生产故障）回归锁。
// 故障形态（用户真机诊断 proven）：带旧形态持久数据（D3 迁
// 移前：毫秒数值时间戳、musicCard 顶层 url/status 字段）启
// 动时，数据加载与列表重算后同秒触发 wasm trap
// （window.onerror RuntimeError: Unreachable code ...
// wasm.__wasm_bindgen_func_elem_NNNN），此后 row open 仍落
// Diag 但 EDIT page enter 永不出现、天气链永不启动——点
// 击全死、无痕正常。本探针把故障的输入条件全套钉进门禁：
//   WebKit + iPhone 视口/UA + 深色 + 持久 profile 预置旧形
//   态 memos_json/manifest_raw（同源种子页先写 IDB 再跳主
//   页，保证走 load_state 持久加载 + D3 迁移路径，而非种
//   子直启——旧构建空启动不落盘 memos_json，升级场景若不
//   预置即测了个寂寞，第二轮排查的教训）。
// 断言：① loaded persisted + MIGRATE d3 + persisted state
//   applied 三行齐（加载路径真走了）；② Diag 无
//   wasm_bindgen_func_elem 行、无 PANIC 行、mynote_panic_v1
//   键为空（panic 钩无记录）；③ 真实 tap 首卡后 EDIT page
//   enter 真出现；④ 二次启动（已迁移态）重复 ②③。
// 口径声明：box WebKit 为桌面引擎，与真机 iOS Safari 的
// JSC 存在版本差；本探针在 box 全绿只证明「输入条件 + 加
// 载路径 + 导航链」在该口径下无恙，故障终判以真机下次启
// 动的 PANIC 记录（diag panic 钩）为准——钩有记录即出处、
// 无记录即 bindgen 桩形态，二选一收尾。
// 用法：node probe_click_dead.mjs [distDir]
//   默认 rust/apps/web/dist；run_all_tests 传入 baseURL 时
//   忽略（自带静态服务，需同源种子页）。
import { webkit } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
let distDir = path.join(root, 'rust', 'apps', 'web', 'dist');
if (process.argv[2] && !process.argv[2].startsWith('http')) {
  distDir = path.resolve(process.argv[2]);
}
const PORT = 8151;
const BASE = `http://localhost:${PORT}/`;
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── 旧形态夹具（镜像真机导出 census：5 篇、heading=2、
// musicCard=4、todo=4、paragraph≈15、毫秒数值时间戳、
// musicCard 顶层 url/status/meta 字段） ──────────────
const T = 1795519750964;
const txt = (t) => [{ text: t }];
const P = (id, t) => ({ type: 'paragraph', id, children: txt(t) });
const FIXTURE = {
  version: 2,
  memos: [
    { id: 'demo_home', title: '本周待办与生活备忘', pinned: true, createdAt: T, updatedAt: T,
      doc: [
        { type: 'todo', id: 'dh1', children: txt('交季度报表'), attrs: { checked: true } },
        { type: 'todo', id: 'dh2', children: txt('预约牙科复查'), attrs: { checked: false } },
        { type: 'todo', id: 'dh3', children: txt('给阳台的薄荷换盆'), attrs: { checked: false } },
        { type: 'todo', id: 'dh4', children: txt('订周五晚的高铁票'), attrs: { checked: false } },
      ] },
    { id: 'demo_exhibit', title: '周末看展记录', pinned: false, createdAt: T, updatedAt: T,
      doc: [
        { type: 'heading', id: 'de0', children: txt('非物质再现'), attrs: { level: 1 } },
        P('de1', '今天去了 UCCA 的展。光线透过亚克力板投射在墙上。'),
        P('de2', '出口处的装置用了镜面与雾面两种材料。'),
        P('de3', '下次想带胶片机再来一次。'),
      ] },
    { id: 'demo_book', title: '在读的书', pinned: false, createdAt: T, updatedAt: T,
      doc: [P('db1', '《温柔的夜》读到第三章。'), P('db2', '摘抄：记忆是一种重写。'), P('db3', '下周还书。')] },
    { id: 'demo_music', title: '最近在听', pinned: false, createdAt: T, updatedAt: T,
      doc: [
        { type: 'heading', id: 'dm0', children: txt('歌单'), attrs: { level: 2 } },
        P('dm1', '夜里循环的四首。'),
        { type: 'musicCard', id: 'dm3', meta: null, status: 'loading', url: 'https://example.invalid/music/1', children: txt('') },
        { type: 'musicCard', id: 'dm4', meta: null, status: 'loading', url: 'https://example.invalid/music/2', children: txt('') },
        { type: 'musicCard', id: 'dm5', meta: null, status: 'loading', url: 'https://example.invalid/music/3', children: txt('') },
        { type: 'musicCard', id: 'dm6', meta: null, status: 'loading', url: 'https://example.invalid/music/4', children: txt('') },
        P('dm7', '封面图都是外链。'), P('dm8', '听完再补短评。'), P('dm9', '完。'),
      ] },
    { id: 'demo_tools', title: '工具清单', pinned: false, createdAt: T, updatedAt: T,
      doc: [P('dt1', '扳手一套。'), P('dt2', '电钻借给邻居了。'), P('dt3', '补一卷生料带。')] },
  ],
};
const MANIFEST = '{"version":1,"attachments":{}}';

// ── 静态服务（COOP/COEP/CORP + no-store，同 harness 口径；
// 另发同源种子页 /__seed.html） ───────────────────────
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
const SEED_HTML = `<!doctype html><meta charset="utf-8"><script>
const memos = ${JSON.stringify(JSON.stringify(FIXTURE))};
const manifest = ${JSON.stringify(MANIFEST)};
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
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Cache-Control', 'no-store');
  if (p === '/__seed.html') { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(SEED_HTML); return; }
  if (p === '/') p = '/index.html';
  const fp = path.join(distDir, p);
  if (!fp.startsWith(distDir) || !fs.existsSync(fp) || fs.statSync(fp).isDirectory()) { res.writeHead(404); res.end('nf'); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'application/octet-stream' });
  fs.createReadStream(fp).pipe(res);
});
await new Promise((r) => server.listen(PORT, r));

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clickdead-'));
const ctx = await webkit.launchPersistentContext(dir, {
  viewport: { width: 393, height: 852 },
  colorScheme: 'dark',
  hasTouch: true,
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Mobile/15E148 Safari/604.1',
});
const page = ctx.pages()[0] || (await ctx.newPage());
const pageErrors = [];
page.on('pageerror', (e) => pageErrors.push(String(e).slice(0, 200)));

const readDiag = async () => page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '').then((s) => {
  try { const v = JSON.parse(s); return Array.isArray(v) ? v : String(s).split('\n'); } catch { return String(s).split('\n'); }
}).catch(() => []);
const waitDiag = async (pred, timeout = 9000) => {
  const t0 = Date.now();
  let lines = [];
  while (Date.now() - t0 < timeout) {
    lines = await readDiag();
    if (pred(lines)) return lines;
    await sleep(600);
  }
  return lines;
};
const trapLines = (lines) => lines.filter((l) => l.includes('wasm_bindgen_func_elem') || l.includes('PANIC'));
const panicKey = () => page.evaluate(() => localStorage.getItem('mynote_panic_v1')).catch(() => '?');

async function bootAndProbe(tag, { navigate, expectMigrate, off }) {
  // Diag 跨启动累积：正向行只认本轮新增段（offset 之后），
  // trap/PANIC 行扫全环（任何一轮出现即失败）。offset 由
  // 调用方在导航/启动之前取（boot1 在种子页跳转前取 0）。
  if (navigate) await page.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  let lines = await waitDiag((ls) => ls.slice(off).some((l) => l.includes('persisted state applied')), 12000);
  const seg = lines.slice(off);
  ok(tag + ' loaded persisted memos=5', seg.some((l) => l.includes('loaded persisted memos=5')));
  if (expectMigrate) ok(tag + ' MIGRATE d3 出现', seg.some((l) => l.includes('MIGRATE d3')));
  ok(tag + ' persisted state applied', seg.some((l) => l.includes('persisted state applied')));
  ok(tag + ' 无 elem trap / PANIC 行', trapLines(lines).length === 0, trapLines(lines).join(' | ').slice(0, 160));
  ok(tag + ' mynote_panic_v1 为空', !(await panicKey()));
  const pt = await page.evaluate(() => {
    const el = document.querySelector('.img-card, .list-item:not(.set-row)');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + Math.min(r.height / 2, 40) };
  });
  ok(tag + ' 首卡可定位', !!pt);
  if (pt) {
    const off2 = (await readDiag()).length;
    if (page.touchscreen) await page.touchscreen.tap(pt.x, pt.y); else await page.mouse.click(pt.x, pt.y);
    lines = await waitDiag((ls) => ls.slice(off2).some((l) => l.includes('EDIT page enter')), 9000);
    ok(tag + ' tap 后 EDIT page enter 出现', lines.slice(off2).some((l) => l.includes('EDIT page enter')));
    ok(tag + ' tap 后仍无 trap', trapLines(lines).length === 0);
  }
  ok(tag + ' pageerror 无 Unreachable', !pageErrors.some((e) => e.includes('Unreachable')), pageErrors.join(' | ').slice(0, 160));
}

// 种子页先写 IDB，再跳主页（应用此时才首次启动，boot1 不再导航）
await page.goto(BASE + '__seed.html', { waitUntil: 'load' }).catch(() => {});
await waitDiag((ls) => ls.some((l) => l.includes('APP start')), 12000);
await bootAndProbe('boot1(旧形态)', { navigate: false, expectMigrate: true, off: 0 });
// 二次启动（已迁移态）：整页重载回列表
await bootAndProbe('boot2(已迁移)', { navigate: true, expectMigrate: false, off: (await readDiag()).length });

await ctx.close();
server.close();
L(fails === 0 ? 'ALL PASS' : `FAILED ${fails}`);
process.exit(fails === 0 ? 0 : 1);
