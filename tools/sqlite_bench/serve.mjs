// 阶段二演练用静态服务：发 dist + /sqlite-bench/（演练台
// 与夹具），带 COOP/COEP/CORP 头（与生产托管口径一致的
// 一组跨源隔离头；SAHPool 本身不依赖它们，见 spike 报告）。
// 用法：node serve.mjs <distDir> <port>
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(process.argv[2]);
const PORT = Number(process.argv[3] || 8143);
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream', '.zip': 'application/zip', '.mjs': 'text/javascript' };
http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = p.startsWith('/sqlite-bench/')
    ? path.join(root, p.slice('/sqlite-bench/'.length))
    : path.join(distDir, p === '/' ? 'index.html' : p);
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
}).listen(PORT, () => console.log('serving ' + distDir + ' on ' + PORT));
