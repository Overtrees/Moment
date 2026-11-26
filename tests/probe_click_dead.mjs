// 专用探针：首页点击死亡故障（2026-11-24 生产故障）回归锁。
// 根因（2026-11-24 晚定因 proven）：列表按 updatedAt 排序、
// 分组标签按 createdAt 派生，build_groups 旧实现只做连续
// 成组——任一备忘被编辑过（updatedAt 顶到近期）两序即分
// 叉，同一标签在序列中复现（如 过去7天…过去30天…过去7
// 天），产出两个同标签分组；列表以 g-{label} 为键控 key，
// 兄弟键重复违反 Dioxus 键控 diff 的键唯一不变量，换批
// diff 损坏 mount 表：真机 panic `invalid key @
// dioxus-core diff/mod.rs:44` 后渲染楔死（row open 有 Diag、
// EDIT page enter 永不出现），box WebKit 同输入呈 bindgen
// 桩 trap。修复 = build_groups 按标签归并（每标签至多一
// 组，键唯一由构造保证）。本探针把触发形态钉进门禁：
//   WebKit + iPhone 视口/UA + 深色 + 持久 profile 预置旧形
//   态 memos_json/manifest_raw（毫秒时间戳 + musicCard 旧
//   字段），其中 book/music 的 updatedAt 顶到当前（模拟健
//   康期编辑保存），使排序后标签序列非单调、同标签复现。
// 断言：① loaded persisted + MIGRATE d3 + persisted state
//   applied 三行齐（加载路径真走了）；MIGRATE 摘要另按
//   现行键集断言存在性（2026-11-25 同步：callout 改名与
//   §2.2 通道归一后键集含 callout_move/callout_clear、
//   fields_norm/layout_norm、mform/mdrop/mfield——按键
//   存在性/键值断言、不锁全串与键序，键集登记在
//   MIGRATE_KEYS 一处，与 probe_load_stock 同口径）；② Diag 无
//   wasm_bindgen_func_elem 行、无 PANIC 行、无 ERR 行、
//   moment_panic_v1 键为空；③ DOM 中「过去7天」分组头恰
//   一个且 5 卡齐全（归并真发生）；④ 真实 tap 首卡后
//   EDIT page enter 真出现；⑤ 二次启动重复 ②④ 且不再产
//   生 MIGRATE 行（迁移在换批场景下收敛）。
// 口径声明：box WebKit 为桌面引擎，与真机 iOS Safari 的
// JSC 存在版本差；本探针在 box 全绿证明触发输入在修复后
// 无恙，故障终判仍以真机下次启动的 Diag（无 PANIC/ERR、
// 点按可进编辑器）为准。
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
let distDir = path.join(root, '..', 'rust', 'apps', 'web', 'dist');
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
// musicCard=4、todo=4、毫秒数值时间戳、musicCard 顶层
// url/status/meta 字段）。时间戳按相对当前构造（分组标
// 签是相对今天的量，绝对旧值会把五篇压进同一桶、测不到
// 触发形态）：exhibit 今天、home -1d 置顶、tools 创建
// -3d、book 创建 -7d、music 创建 -14d；book/music 的
// updatedAt 顶到当前（健康期编辑保存的真机形态）——按
// updatedAt 排序后标签序列为 今天/过去7天/过去30天/过
// 去7天，同标签复现 = 本故障的触发输入。 ──────────────
const NOW = Date.now();
const DAY = 86400000;
const txt = (t) => [{ text: t }];
const P = (id, t) => ({ type: 'paragraph', id, children: txt(t) });
const FIXTURE = {
  version: 2,
  memos: [
    { id: 'demo_home', title: '本周待办与生活备忘', pinned: true, createdAt: NOW - DAY, updatedAt: NOW - DAY,
      doc: [
        { type: 'todo', id: 'dh1', children: txt('交季度报表'), attrs: { checked: true } },
        { type: 'todo', id: 'dh2', children: txt('预约牙科复查'), attrs: { checked: false } },
        { type: 'todo', id: 'dh3', children: txt('给阳台的薄荷换盆'), attrs: { checked: false } },
        { type: 'todo', id: 'dh4', children: txt('订周五晚的高铁票'), attrs: { checked: false } },
      ] },
    { id: 'demo_exhibit', title: '周末看展记录', pinned: false, createdAt: NOW, updatedAt: NOW,
      doc: [
        { type: 'heading', id: 'de0', children: txt('非物质再现'), attrs: { level: 1 } },
        P('de1', '今天去了 UCCA 的展。光线透过亚克力板投射在墙上。'),
        P('de2', '出口处的装置用了镜面与雾面两种材料。'),
        P('de3', '下次想带胶片机再来一次。'),
      ] },
    { id: 'demo_book', title: '在读的书', pinned: false, createdAt: NOW - 7 * DAY, updatedAt: NOW,
      doc: [P('db1', '《温柔的夜》读到第三章。'), P('db2', '摘抄：记忆是一种重写。'), P('db3', '下周还书。')] },
    { id: 'demo_music', title: '最近在听', pinned: false, createdAt: NOW - 14 * DAY, updatedAt: NOW,
      doc: [
        { type: 'heading', id: 'dm0', children: txt('歌单'), attrs: { level: 2 } },
        P('dm1', '夜里循环的四首。'),
        { type: 'musicCard', id: 'dm3', meta: null, status: 'loading', url: 'https://example.invalid/music/1', children: txt('') },
        { type: 'musicCard', id: 'dm4', meta: null, status: 'loading', url: 'https://example.invalid/music/2', children: txt('') },
        { type: 'musicCard', id: 'dm5', meta: null, status: 'loading', url: 'https://example.invalid/music/3', children: txt('') },
        { type: 'musicCard', id: 'dm6', meta: null, status: 'loading', url: 'https://example.invalid/music/4', children: txt('') },
        P('dm7', '封面图都是外链。'), P('dm8', '听完再补短评。'), P('dm9', '完。'),
      ] },
    { id: 'demo_tools', title: '工具清单', pinned: false, createdAt: NOW - 3 * DAY, updatedAt: NOW - 3 * DAY,
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

const readDiag = async () => page.evaluate(() => localStorage.getItem('moment_diag_v1') || '').then((s) => {
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
const trapLines = (lines) => lines.filter((l) => l.includes('wasm_bindgen_func_elem') || l.includes('PANIC') || l.includes('] ERR '));
// MIGRATE 摘要现行键集（core::migrate summary() 口径，
// 2026-11-25；与 probe_load_stock 的 MIGRATE_KEYS 同步）。
const MIGRATE_KEYS = ['memos', 'nodes', 'num_id', 'millis_ts', 'fileid_move', 'fileid_clear',
  'gal_str', 'gal_kids', 'gal_rm', 'gal_drop', 'level_move', 'level_clear',
  'checked_move', 'checked_clear', 'music', 'code', 'strike',
  'callout_move', 'callout_clear', 'mform', 'mdrop', 'mfield', 'fields_norm', 'layout_norm', 'quarantined', 'changed'];
const parseSummary = (line) => {
  const m = {};
  for (const mm of String(line || '').matchAll(/([a-z_]+)=(\d+)/g)) m[mm[1]] = Number(mm[2]);
  return m;
};
const panicKey = () => page.evaluate(() => localStorage.getItem('moment_panic_v1')).catch(() => '?');

async function bootAndProbe(tag, { navigate, expectMigrate, off }) {
  // Diag 跨启动累积：正向行只认本轮新增段（offset 之后），
  // trap/PANIC 行扫全环（任何一轮出现即失败）。offset 由
  // 调用方在导航/启动之前取（boot1 在种子页跳转前取 0）。
  if (navigate) await page.goto(BASE, { waitUntil: 'load' }).catch(() => {});
  let lines = await waitDiag((ls) => ls.slice(off).some((l) => l.includes('persisted state applied')), 12000);
  const seg = lines.slice(off);
  // boot1 断言恰 5 篇（种子页写入量）；boot2 容忍 boot1 的
  // 编辑会话落盘新增（开篇/自动保存可能 +1），只断言持久
  // 加载路径成立（≥5）。
  ok(
    tag + ' loaded persisted memos',
    seg.some((l) => expectMigrate
      ? l.includes('loaded persisted memos=5')
      : /loaded persisted memos=[5-9]\d*/.test(l)),
  );
  if (expectMigrate) {
    ok(tag + ' MIGRATE d3 出现', seg.some((l) => l.includes('MIGRATE d3')));
    const migLine = seg.find((l) => l.includes('MIGRATE d3 memos='));
    const s = parseSummary(migLine);
    const missing = MIGRATE_KEYS.filter((k) => !(k in s));
    ok(tag + ' MIGRATE 摘要键集与现行口径一致（全键在场、不锁键序）', !!migLine && missing.length === 0, missing.length ? `缺键 ${missing.join(',')}` : (migLine || '无 MIGRATE 行'));
  }
  if (!expectMigrate) ok(tag + ' 无 MIGRATE d3（迁移已收敛）', !seg.some((l) => l.includes('MIGRATE d3')), seg.find((l) => l.includes('MIGRATE d3')) || '');
  ok(tag + ' persisted state applied', seg.some((l) => l.includes('persisted state applied')));
  if (expectMigrate) {
    // 归并结构断言：触发输入下「过去7天」分组头恰一个
    // （book/tools 同组）、五篇卡齐全——修复前此处为两个
    // 同名分组头且渲染楔死、卡数不足。
    const dom = await page.evaluate(() => {
      const heads = [...document.querySelectorAll('.section-header')].map((e) => e.innerText.trim());
      // 卡数按 MemoRow 根 .swipe-wrapper 数、再按文本排除
      // 「新建笔记」行（它与备忘卡同壳同类、同在 .list-group
      // 内，结构口径无法区分——实测教训）；另核五篇标题
      // 逐篇在场（身份口径，不只计数）。
      const wraps = [...document.querySelectorAll('.swipe-wrapper')];
      const cards = wraps.filter((e) => !(e.innerText || '').trimStart().startsWith('新建笔记'));
      const titles = ['本周待办与生活备忘', '周末看展记录', '在读的书', '最近在听', '工具清单'];
      const allText = wraps.map((e) => e.innerText || '').join('\n');
      return { weekHeads: heads.filter((h) => h === '过去7天').length, heads, cards: cards.length, missing: titles.filter((t) => !allText.includes(t)) };
    }).catch(() => ({ weekHeads: -1, heads: [], cards: -1, missing: ['?'] }));
    ok(tag + ' 「过去7天」分组头恰一个（同标签已归并）', dom.weekHeads === 1, JSON.stringify(dom.heads));
    ok(tag + ' 五篇卡齐全', dom.cards === 5 && dom.missing.length === 0, `cards=${dom.cards} missing=${dom.missing.join(',')}`);
  }
  ok(tag + ' 无 elem trap / PANIC 行', trapLines(lines).length === 0, trapLines(lines).join(' | ').slice(0, 160));
  ok(tag + ' moment_panic_v1 为空', !(await panicKey()));
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
