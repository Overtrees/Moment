// 接管延迟对照（旧构建口径）：同 context 双页，第二页阻
// 断后关第一页，量 close→阻断层消失总延迟。旧构建无新版
// Diag/样式断言，只量时间。
// 用法：node probe_takeover.mjs <distDir> <port>
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const distDir = path.resolve(process.argv[2]);
const PORT = Number(process.argv[3] || 8235);
const BASE = `http://localhost:${PORT}/`;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream' };
const server = http.createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = path.join(distDir, p === '/' ? 'index.html' : p);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('nf'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp', 'Cross-Origin-Resource-Policy': 'same-origin', 'Cache-Control': 'no-store' });
    res.end(data);
  });
});
await new Promise((r) => server.listen(PORT, r));
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mn-takeover-'));
const ctx = await chromium.launchPersistentContext(dir, { executablePath: exe, args: ['--no-sandbox'] });
const p1 = await ctx.newPage();
await p1.goto(BASE, { waitUntil: 'load' });
await p1.waitForSelector('.list-item, .empty-state, .glass-search-trigger', { timeout: 30000 }).catch(() => {});
await sleep(3000);
const p2 = await ctx.newPage();
await p2.goto(BASE, { waitUntil: 'load' });
const blocked = await p2.waitForSelector('.storage-blocked', { timeout: 30000 }).then(() => true).catch(() => false);
console.log('second page blocked:', blocked);
const t0 = Date.now();
await p1.close();
let tGone = -1;
while (Date.now() - t0 < 30000) {
  const gone = await p2.evaluate(() => !document.querySelector('.storage-blocked')).catch(() => false);
  if (gone) { tGone = Date.now() - t0; break; }
  await sleep(20);
}
console.log(`TAKEOVER close->gone = ${tGone}ms`);
await ctx.close();
process.exit(0);
