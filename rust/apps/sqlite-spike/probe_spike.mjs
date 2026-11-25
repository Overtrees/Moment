// SQLite spike 探针（阶段一脚手架，阶段二丢弃）。
// 在 box Chromium（headless shell）里验证：Dedicated Worker 内
// SAHPool VFS 开库 → 建表/写入/查询 → FTS5 trigram 中文检索 →
// 整页 reload 与同 context 第二页均可读回（OPFS 落盘成立）。
// 静态服务刻意不下发 COOP/COEP，验证 SAHPool 免头口径。
// 用法：node probe_spike.mjs [webDir]（默认 ./web）
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const webDir = path.resolve(process.argv[2] || './web');
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm' };

const server = http.createServer((req, res) => {
  const p = path.join(webDir, req.url === '/' ? 'index.html' : decodeURIComponent(req.url.split('?')[0]));
  fs.readFile(p, (err, data) => {
    if (err) { res.writeHead(404); res.end('nf'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}/`;
console.log('serving', webDir, 'at', base, '(no COOP/COEP headers)');

let fails = 0;
const ok = (cond, label, extra = '') => {
  console.log((cond ? '✓' : '✗ FAIL') + ' ' + label + (extra ? ' :: ' + extra : ''));
  if (!cond) fails++;
};

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'spike-profile-'));
const ctx = await chromium.launchPersistentContext(profile, { executablePath: exe, args: ['--no-sandbox'] });
const page = await ctx.newPage();
page.on('console', m => console.log('[page]', m.type(), m.text()));
page.on('pageerror', e => console.log('[pageerror]', String(e)));
await page.goto(base);
await page.waitForFunction(() => window.__spikeReady === true, null, { timeout: 30000 });

const tag = 'spike-' + Math.random().toString(36).slice(2, 10);
const bodyHit = '这是中文全文检索测试文本，模拟备忘正文内容。';
const bodyMiss = '另一篇备忘，只有英文与数字 12345。';

const read0 = await page.evaluate(() => window.__spike.read());
console.log('read0:', JSON.stringify(read0.result));
ok(read0.result.exists === false && read0.result.count === 0, 'fresh profile: 库不存在、零行');

const w1 = await page.evaluate(([t, b]) => window.__spike.write(t, b), [tag, bodyHit]);
console.log('write1:', JSON.stringify(w1.result));
console.log('opfs after write1:', JSON.stringify(w1.opfs));
ok(w1.result.count === 1, 'write1: count=1');
ok(Array.isArray(w1.result.fts_hits) && w1.result.fts_hits.includes(tag), 'write1: FTS「文检索」命中写入行', JSON.stringify(w1.result.fts_hits));
ok(!!w1.result.sqlite_version, 'sqlite_version 在位', w1.result.sqlite_version);
ok(Array.isArray(w1.opfs) && w1.opfs.some(f => f.size > 0), 'write1: OPFS 已有非空文件', JSON.stringify(w1.opfs));

const w2 = await page.evaluate(([t, b]) => window.__spike.write(t + '-b', b), [tag, bodyMiss]);
console.log('write2:', JSON.stringify(w2.result));
ok(w2.result.count === 2, 'write2: count=2');
ok(w2.result.fts_hits.length === 1 && w2.result.fts_hits[0] === tag, 'write2: FTS 只命中中文行', JSON.stringify(w2.result.fts_hits));

await page.reload();
await page.waitForFunction(() => window.__spikeReady === true, null, { timeout: 30000 });
const read1 = await page.evaluate(() => window.__spike.read());
console.log('read after reload:', JSON.stringify(read1.result));
ok(read1.result.exists === true && read1.result.count === 2, 'reload 后: 数据仍在 count=2');
ok(read1.result.rows.some(r => r.title === tag && r.body === bodyHit), 'reload 后: 首行内容逐字一致');

// SAHPool 同步句柄独占（spike 实测）：第一页 Worker 存活时，
// 第二页 install 直接失败（creating sync access handle 出错）——
// 与官方「one connection at a time」一致。故第二页核验须先关
// 第一页、等句柄释放后再开；释放耗时如实记录，不掩盖独占语义。
await page.close();
const page2 = await ctx.newPage();
await page2.goto(base);
await page2.waitForFunction(() => window.__spikeReady === true, null, { timeout: 30000 });
let read2 = null, releaseMs = -1;
{
  const t0 = Date.now();
  for (let i = 0; i < 40; i++) {
    try { read2 = await page2.evaluate(() => window.__spike.read()); releaseMs = Date.now() - t0; break; }
    catch { await new Promise(r => setTimeout(r, 500)); }
  }
}
console.log('read page2:', JSON.stringify(read2 && read2.result), 'handle release ms:', releaseMs);
console.log('opfs page2:', JSON.stringify(read2 && read2.opfs));
ok(!!read2 && read2.result.count === 2 && read2.result.fts_hits.includes(tag), '第二页（第一页关闭后）: 可读回且 FTS 命中（落盘终态）');

await ctx.close();
server.close();
console.log(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
