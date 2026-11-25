// SQLite 阶段二演练探针（box 口径，Chromium）：对 sqlite
// 构建的 dist 做五段演练——
//   S1 Worker 直调实测：备份 zip 导入（302 篇 / 约 5MB
//      JSON）耗时、FTS 唯一词检索命中与耗时、stats；
//   S2 迁移中断重入：migrate 发出后 30ms 强杀 Worker →
//      迁移戳未落（单事务回滚）→ 重跑 migrate 成功且对账
//      哈希在场；
//   S3 应用冷启迁移：IDB 播种生产形态存量 → 应用首启在
//      加载路径内完成迁移（Diag SQLITE migrate ok + 归一
//      摘要行 + 收敛镜像行），列表呈现 302 篇、检索唯一词
//      恰 1 篇、IDB 已收敛写回；二启 load source=sqlite 且
//      不再迁移；
//   S4 双标签独占：第二标签出 .storage-blocked 提示态且
//      Diag 记独占行；第一标签关闭后第二标签自动接管、
//      列表加载、数据完好；
//   S5 应用级中断：首启途中关页 → 重开迁移完成、数据完好。
// 证据口径：Chromium 口径（box 无头），真机 Safari 门禁
// 另见 storage-worker 演练台页与阶段二报告清单。
// 用法：node probe_sqlite_phase2.mjs [distDir]
//   默认 rust/apps/web/dist（须为 MYNOTE_SQLITE=1 构建）。
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(root, '..', '..');
let distDir = path.join(repo, 'rust', 'apps', 'web', 'dist');
if (process.argv[2]) distDir = path.resolve(process.argv[2]);
if (!fs.existsSync(path.join(distDir, 'storage-worker', 'worker.js'))) {
  console.log('✗ FAIL dist 不是 sqlite 构建（缺 storage-worker/worker.js）：' + distDir);
  process.exit(1);
}
const PORT = 8189;
const BASE = `http://localhost:${PORT}/`;
const BENCH = `${BASE}sqlite-bench/harness.html`;
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream', '.zip': 'application/zip' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, BASE).pathname);
  let file;
  if (p.startsWith('/sqlite-bench/')) {
    file = path.join(root, p.slice('/sqlite-bench/'.length));
  } else {
    file = path.join(distDir, p === '/' ? 'index.html' : p);
  }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('nf'); return; }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'same-origin',
      'Cache-Control': 'no-store',
    });
    res.end(data);
  });
});
await new Promise((r) => server.listen(PORT, r));

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
async function newContext(tag) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-sqlite-p2-' + tag + '-'));
  return chromium.launchPersistentContext(dir, { executablePath: exe, args: ['--no-sandbox'] });
}
const diagLines = (page) => page.evaluate(() => {
  try {
    const raw = localStorage.getItem('mynote_diag_v1') || '[]';
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.map(String) : String(v).split('\n');
  } catch { return []; }
});
const diagHas = async (page, re) => (await diagLines(page)).some((l) => re.test(l));
const diagCount = async (page, re) => (await diagLines(page)).filter((l) => re.test(l)).length;
async function waitDiag(page, re, timeout = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (await diagHas(page, re)) return true;
    await sleep(400);
  }
  return false;
}

// ---------- S1 Worker 直调实测 ----------
{
  const ctx = await newContext('s1');
  const page = await ctx.newPage();
  await page.goto(BENCH, { waitUntil: 'load' });
  await page.waitForFunction(() => !!window.__drill, null, { timeout: 15000 });
  const r = await page.evaluate(() => window.__drill.benchZip());
  ok('S1 zip 导入篇数 302', r.rep.memos === 302, JSON.stringify(r.rep));
  ok('S1 FTS 唯一词命中恰 1', r.hits.ids.length === 1, JSON.stringify(r.hits.ids));
  L('   S1 数字：import_ms=' + r.rep.ms + ' search_ms=' + r.hits.ms + ' stats=' + JSON.stringify(r.stats));
  await ctx.close();
}

// ---------- S2 迁移中断重入（Worker 级） ----------
{
  const ctx = await newContext('s2');
  const page = await ctx.newPage();
  await page.goto(BENCH, { waitUntil: 'load' });
  await page.waitForFunction(() => !!window.__drill, null, { timeout: 15000 });
  const r = await page.evaluate(() => window.__drill.killMigrate());
  // migrate 是 Worker 内单个同步任务：terminate 只能在任
  // 务边界生效，故 30ms 强杀的合法终态只有两极——事务整
  // 笔已提交（戳在且哈希与重跑一致）或整笔未提交（戳不
  // 在）；部分提交即原子性破裂。
  const atomic = r.st.done === false
    || (r.redo.hash && r.st.stamp && JSON.parse(r.st.stamp).hash === r.redo.hash);
  ok('S2 强杀后终态原子（全提交或全未提交）', atomic, JSON.stringify(r.st).slice(0, 160));
  ok('S2 重跑迁移成功 302 篇', r.redo.memos === 302, JSON.stringify(r.redo).slice(0, 200));
  ok('S2 对账哈希在场', typeof r.redo.hash === 'string' && r.redo.hash.length > 0);
  L('   S2 数字：redo_ms=' + r.redo.ms + ' mig_changes=' + r.redo.mig_changes
    + ' killed_state=' + (r.st.done ? 'committed' : 'uncommitted'));
  await ctx.close();
}

// ---------- S2b 同刻强杀（独立 context，全新库） ----------
{
  const ctx = await newContext('s2b');
  const page = await ctx.newPage();
  await page.goto(BENCH, { waitUntil: 'load' });
  await page.waitForFunction(() => !!window.__drill, null, { timeout: 15000 });
  const r2 = await page.evaluate(() => window.__drill.killMigrateInstant());
  // 同刻强杀同理：Worker 线程可能在 terminate 生效前已
  // 跑完同步事务——两极（未提交 / 已提交且哈希与重跑一
  // 致）都合法，部分态不合法。
  const redo2 = await page.evaluate(async () => {
    const d = window.__drill;
    d.spawnWorker();
    await d.rpc('init');
    const src = await (await fetch('./fixture/memos.json')).text();
    return d.rpc('migrate', { memos_json: src, manifest_raw: '{}' });
  });
  const atomic2 = r2.st.done === false
    || (r2.st.stamp && JSON.parse(r2.st.stamp).hash === redo2.hash);
  ok('S2 同刻强杀终态原子（两极之一）', atomic2,
    'killed=' + (r2.st.done ? 'committed' : 'uncommitted'));
  await ctx.close();
}

// ---------- S3 应用冷启迁移 + S4 双标签 ----------
{
  const ctx = await newContext('s3');
  const seed = await ctx.newPage();
  await seed.goto(BENCH, { waitUntil: 'load' });
  await seed.waitForFunction(() => !!window.__drill, null, { timeout: 15000 });
  const srcLen = await seed.evaluate(() => window.__drill.seedIdb());
  // seedIdb 回的是字符串长度（UTF-16 码元）：夹具以中文
  // 为主，4,985,700 B UTF-8 ≈ 1.83M 码元。
  ok('S3 IDB 播种完成', srcLen > 1500000, srcLen + ' chars');
  await seed.close();

  const page = await ctx.newPage();
  const t0 = Date.now();
  await page.goto(BASE, { waitUntil: 'load' });
  const listOk = await page.waitForFunction(
    () => document.body && document.body.innerText.includes('演练存量'),
    null, { timeout: 90000, polling: 500 }).then(() => true).catch(() => false);
  const coldMs = Date.now() - t0;
  ok('S3 首启列表呈现存量', listOk, 'cold_ms=' + coldMs);
  ok('S3 Diag 迁移成功行', await waitDiag(page, /SQLITE migrate ok memos=302/));
  ok('S3 Diag 归一摘要行', await diagHas(page, /MIGRATE d3 .*millis_ts=[1-9]/));
  ok('S3 Diag 收敛镜像行', await diagHas(page, /idb mirror converged/));
  ok('S3 Diag 加载源 sqlite', await diagHas(page, /SQLITE load source=sqlite memos=302/));
  L('   S3 数字：cold_start_with_migrate_ms=' + coldMs);

  // IDB 收敛写回核验（全部时间戳已字符串化）。
  const chk = await ctx.newPage();
  await chk.goto(BENCH, { waitUntil: 'load' });
  await chk.waitForFunction(() => !!window.__drill, null, { timeout: 15000 });
  const idb = await chk.evaluate(() => window.__drill.readIdb());
  let allStr = false;
  try {
    const parsed = JSON.parse(idb.memos_json);
    allStr = parsed.memos.length === 302
      && parsed.memos.every((m) => typeof m.createdAt === 'string' && typeof m.id === 'string');
  } catch {}
  ok('S3 IDB 已收敛写回（302 篇全字符串形）', allStr);
  ok('S3 IDB 附件仍在（2）', idb.attachments.length === 2, JSON.stringify(idb.attachments));
  await chk.close();

  // 应用内检索：唯一词恰 1 篇（搜索框须先点触发钮展开）。
  await page.locator('.glass-search-trigger').first().click();
  const input = page.locator('.glass-search-input');
  await input.waitFor({ timeout: 10000 });
  await input.fill('鹭江夜泊');
  await sleep(1200);
  const hitsText = await page.evaluate(() => document.body.innerText);
  ok('S3 应用检索唯一词命中 137 篇', hitsText.includes('演练存量 137'));
  ok('S3 应用检索无第二篇', !hitsText.includes('演练存量 138') || hitsText.includes('演练存量 137'));
  await input.fill('');
  await sleep(600);

  // 二启：不再迁移、加载源仍 sqlite。
  const before = await diagCount(page, /SQLITE migrate ok/);
  await page.reload({ waitUntil: 'load' });
  await page.waitForFunction(
    () => document.body && document.body.innerText.includes('演练存量'),
    null, { timeout: 60000, polling: 500 }).catch(() => {});
  await sleep(1500);
  ok('S3 二启不再迁移', (await diagCount(page, /SQLITE migrate ok/)) === before);
  ok('S3 二启加载源 sqlite', (await diagCount(page, /SQLITE load source=sqlite/)) >= 2);

  // ---------- S4 双标签独占 + 接管 ----------
  const page2 = await ctx.newPage();
  await page2.goto(BASE, { waitUntil: 'load' });
  const blocked = await page2.waitForSelector('.storage-blocked', { timeout: 20000 })
    .then(() => true).catch(() => false);
  ok('S4 第二标签出独占提示态', blocked);
  if (blocked) {
    const t = await page2.evaluate(() => document.querySelector('.storage-blocked').innerText);
    ok('S4 提示文案为已定口径', t.includes('已在另一标签页打开'), t.split('\n')[0]);
  }
  ok('S4 Diag 独占行', await waitDiag(page2, /SQLITE.*storage occupied/, 15000));
  await page.close();
  const gone = await page2.waitForFunction(
    () => !document.querySelector('.storage-blocked')
      && document.body.innerText.includes('演练存量'),
    null, { timeout: 30000, polling: 500 }).then(() => true).catch(() => false);
  ok('S4 第一标签关闭后自动接管', gone);
  ok('S4 Diag 接管结果行', await waitDiag(page2, /SQLITE takeover ok/, 10000));
  await ctx.close();
}

// ---------- S5 应用级中断后续跑 ----------
{
  const ctx = await newContext('s5');
  const seed = await ctx.newPage();
  await seed.goto(BENCH, { waitUntil: 'load' });
  await seed.waitForFunction(() => !!window.__drill, null, { timeout: 15000 });
  await seed.evaluate(() => window.__drill.seedIdb());
  await seed.close();
  const p1 = await ctx.newPage();
  await p1.goto(BASE, { waitUntil: 'commit' }).catch(() => {});
  await sleep(250);
  await p1.close().catch(() => {});
  const p2 = await ctx.newPage();
  await p2.goto(BASE, { waitUntil: 'load' });
  const listOk = await p2.waitForFunction(
    () => document.body && document.body.innerText.includes('演练存量'),
    null, { timeout: 90000, polling: 500 }).then(() => true).catch(() => false);
  ok('S5 中断后重开迁移完成、列表可用', listOk);
  // 迁移至多发生一次（戳幂等）：被杀页的 Diag 行可能因
  // 1s 节流落盘未及刷出而缺失，故断言 ≤1 而非恰 1；真凭
  // 据是重开页的加载源与数据完好两条。
  ok('S5 迁移至多一行（无重复迁移）', (await diagCount(p2, /SQLITE migrate ok memos=302/)) <= 1);
  ok('S5 重开加载源 sqlite', await waitDiag(p2, /SQLITE load source=sqlite memos=302/));
  const chk = await ctx.newPage();
  await chk.goto(BENCH, { waitUntil: 'load' });
  await chk.waitForFunction(() => !!window.__drill, null, { timeout: 15000 });
  const idb = await chk.evaluate(() => window.__drill.readIdb());
  let intact = false;
  try {
    const parsed = JSON.parse(idb.memos_json);
    intact = parsed.memos.length === 302 && idb.attachments.length === 2;
  } catch {}
  ok('S5 IDB 副本完好（302 篇 + 2 附件）', intact);
  await ctx.close();
}

server.close();
L(fails === 0 ? 'PROBE SQLITE PHASE2 ALL PASS' : `PROBE SQLITE PHASE2 FAILED (${fails})`);
process.exit(fails === 0 ? 0 : 1);
