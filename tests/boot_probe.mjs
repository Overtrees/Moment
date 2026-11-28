// 启动分段量测探针（fix/web-boot-latency）
// 用法: node boot_probe.mjs <scenario>
//   prod-fresh   全新 profile 冷启（无节流）
//   prod-warm    同 profile 二次冷启（SW+缓存已热）
//   prod-fresh-mid / prod-fresh-slow / prod-warm-mid / prod-warm-slow 节流档
//   update-sim   本地静态服：旧归档首启 → 原地换新归档 → 更新后首启 → 再启
//   swcheck      单版本本地服：首启装缓存 → 二启（指纹资产应零网络）→ 关服三启（应纯缓存启动）
// 节流档（CDP Network.emulateNetworkConditions，如实标档）：
//   mid : 下 1.6Mbps / 上 750kbps / RTT 150ms
//   slow: 下 400kbps / 上 400kbps / RTT 400ms
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const PROD = 'https://canopies-moment.pages.dev/';
const EXE = process.env.CHROME_EXE || '/usr/lib/chromium/chromium';
const scenario = process.argv[2];

const THROTTLE = {
  mid: { offline: false, downloadThroughput: (1.6 * 1024 * 1024) / 8, uploadThroughput: (750 * 1024) / 8, latency: 150 },
  slow: { offline: false, downloadThroughput: (400 * 1024) / 8, uploadThroughput: (400 * 1024) / 8, latency: 400 },
};

async function newPage(browser, throttle, blockSW) {
  const ctx = await browser.newContext(blockSW ? { serviceWorkers: 'block' } : {});
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  if (throttle) await cdp.send('Network.emulateNetworkConditions', THROTTLE[throttle]);
  return { ctx, page, cdp };
}

// 字节记账走 CDP Network.dataReceived 逐包累加（encodedDataLength
// 对 h3 流式 wasm 严重少报、playwright sizes() 对缓存响应给负值，
// 均不用）；分段用 CDP 单调时钟（requestWillBeSent/loadingFinished）。
function watch(cdp, rec) {
  const byId = new Map();
  cdp.on('Network.requestWillBeSent', (e) => {
    try {
      const p = new URL(e.request.url).pathname;
      byId.set(e.requestId, { p, start: Math.round(e.timestamp * 1000), data: 0 });
      if (e.type === 'Document' && (!rec.navMonoMs || Math.round(e.timestamp * 1000) < rec.navMonoMs)) {
        rec.navMonoMs = Math.round(e.timestamp * 1000);
      }
    } catch {}
  });
  cdp.on('Network.dataReceived', (e) => {
    const r = byId.get(e.requestId);
    if (r) r.data += e.encodedDataLength;
  });
  cdp.on('Network.responseReceived', (e) => {
    const r = byId.get(e.requestId);
    if (!r) return;
    r.status = e.response.status;
    r.fromDiskCache = !!e.response.fromDiskCache;
    r.fromSW = !!e.response.fromServiceWorker;
    r.proto = e.response.protocol;
  });
  cdp.on('Network.loadingFinished', (e) => {
    const r = byId.get(e.requestId);
    if (!r) return;
    rec.reqs.push({ p: r.p, body: r.data, tStart: r.start, tEnd: Math.round(e.timestamp * 1000), status: r.status, fromDiskCache: r.fromDiskCache, fromSW: r.fromSW, proto: r.proto });
    rec.bytes += r.data;
  });
  cdp.on('Network.loadingFailed', (e) => {
    const r = byId.get(e.requestId);
    rec.failed.push(((r && r.p) || e.requestId) + ' :: ' + e.errorText);
  });
}

async function bootOnce(page, rec, url) {
  const t0 = Date.now();
  rec.t0 = t0;
  const nav = page.goto(url, { waitUntil: 'commit', timeout: 180000 }).catch((e) => { rec.navErr = String(e); });
  // 轮询启动完成信号：localStorage moment_boot_ok 出现/变化 或 #main .splash 消失且 #main 有子节点
  // evaluate 加 2.5s 竞速：页面主线程忙等时单次 evaluate 会无限
  // 堵住轮询（旧版在本地源实测），竞速超时按未启动继续轮。
  let bootedAt = 0, fcp = 0;
  const deadline = Date.now() + (parseInt(process.env.BOOT_DEADLINE_MS || '180000', 10));
  while (Date.now() < deadline) {
    try {
      const st = await Promise.race([
        page.evaluate(() => {
        let ok = null;
        try { ok = localStorage.getItem('moment_boot_ok'); } catch {}
        const splash = !!document.querySelector('#main .splash');
        const mainKids = document.querySelector('#main')?.childElementCount || 0;
        const paints = performance.getEntriesByType('paint');
        const f = paints.find((p) => p.name === 'first-contentful-paint');
          return { ok, splash, mainKids, fcp: f ? f.startTime : 0 };
        }),
        new Promise((res) => setTimeout(() => res(null), 2500)),
      ]);
      if (!st) { await new Promise((r) => setTimeout(r, 200)); continue; }
      if (st.fcp && !fcp) fcp = st.fcp;
      if ((st.ok || (!st.splash && st.mainKids > 0)) && !bootedAt) { bootedAt = Date.now(); break; }
    } catch {}
    await new Promise((r) => setTimeout(r, 50));
  }
  await nav;
  rec.bootMs = bootedAt ? bootedAt - t0 : -1;
  rec.fcpMs = fcp ? Math.round(fcp) : -1;
  const base = rec.navMonoMs || t0;
  const seg = (name) => {
    const r = rec.reqs.find((x) => x.p.endsWith(name));
    return r ? r.tEnd - base : -1;
  };
  rec.navMonoMs = rec.navMonoMs || null;
  const segRe = (re) => {
    const r = rec.reqs.find((x) => re.test(x.p));
    return r ? r.tEnd - base : -1;
  };
  rec.seg = {
    indexEnd: seg('/index.html') >= 0 ? seg('/index.html') : seg('/'),
    jsEnd: segRe(/\/moment-web[^/]*\.js$/),
    wasmEnd: segRe(/_bg[^/]*\.wasm$/),
  };
  const wasmReqs = rec.reqs.filter((x) => /_bg[^/]*\.wasm$/.test(x.p));
  rec.wasmReqCount = wasmReqs.length;
  rec.wasmBytes = wasmReqs.reduce((a, x) => a + x.body, 0);
  rec.swState = await page.evaluate(async () => {
    if (!('serviceWorker' in navigator)) return 'no-sw-api';
    const regs = await navigator.serviceWorker.getRegistrations();
    return regs.map((r) => ({ scope: r.scope, active: !!r.active, installing: !!r.installing, waiting: !!r.waiting }));
  }).catch((e) => 'err:' + e);
  return rec;
}

function freshRec() { return { reqs: [], bytes: 0, failed: [] }; }

// swcheck：单版本（NEW_DIR）验 SW 策略——首启装缓存、二启
// 指纹资产零网络（服务端账为准）、服务端全灭（关服）三启
// 仍从缓存启动（缓存优先 + 枢轴网络优先回退缓存）。
async function swcheck(browser) {
  const rootDir = process.env.NEW_DIR;
  const srvLog = [];
  const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
  const srv = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p === '/') p = '/index.html';
    const fp = path.join(rootDir, p);
    const entry = { p, status: 200, sent: 0, t: Date.now() };
    srvLog.push(entry);
    if (!fs.existsSync(fp) || fs.statSync(fp).isDirectory()) { entry.status = 404; res.writeHead(404); res.end(); return; }
    const data = fs.readFileSync(fp);
    const etag = 'W/"' + data.length + '-' + fs.statSync(fp).mtimeMs.toString(36) + '"';
    res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
    res.setHeader('ETag', etag);
    if (req.headers['if-none-match'] === etag) { entry.status = 304; res.writeHead(304); res.end(); return; }
    res.setHeader('Content-Type', mime[path.extname(fp)] || 'application/octet-stream');
    const ae = req.headers['accept-encoding'] || '';
    let body = data;
    if (ae.includes('br') && ['.wasm', '.js', '.html', '.json'].includes(path.extname(fp))) {
      res.setHeader('Content-Encoding', 'br');
      body = zlib.brotliCompressSync(data);
    }
    entry.sent = body.length;
    res.end(body);
  });
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${srv.address().port}/`;
  const { ctx, page, cdp } = await newPage(browser, null);
  const rec1 = freshRec(); watch(cdp, rec1);
  await bootOnce(page, rec1, url);
  await page.waitForTimeout(4000); // 等 SW 预缓存落定
  const mark1 = srvLog.length;
  const rec2 = freshRec(); watch(cdp, rec2);
  await bootOnce(page, rec2, url);
  await page.waitForTimeout(1500);
  const boot2Srv = srvLog.slice(mark1);
  srv.close(); // 服务端全灭（连接被拒），验缓存独立启动
  const rec3 = freshRec(); watch(cdp, rec3);
  await bootOnce(page, rec3, url);
  const out = {
    boot1Ms: rec1.bootMs, boot2Ms: rec2.bootMs, boot3Ms: rec3.bootMs,
    boot2SrvPaths: boot2Srv.map((x) => `${x.p}:${x.status}:${x.sent}`),
    boot2SrvFingerprinted: boot2Srv.filter((x) => /moment-web[^/]*\.(js|wasm)$/.test(x.p) || x.p.includes('/snippets/')).length,
    boot2PageReqs: rec2.reqs.map((x) => `${x.p} st=${x.status} sw=${x.fromSW} disk=${x.fromDiskCache} body=${x.body}`),
    swState: rec3.swState,
  };
  await ctx.close();
  return out;
}

async function main() {
  // 全局看门狗：任何一段挂死都吐部分结果退出，不无限等
  setTimeout(() => { console.log('{"watchdog":"timeout"}'); process.exit(2); }, parseInt(process.env.WATCHDOG_MS || '600000', 10));
  const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
  const out = { scenario, exe: EXE };
  if (scenario.startsWith('prod-')) {
    const parts = scenario.split('-'); // prod, fresh|warm, mid|slow?
    const throttle = parts[2] || null;
    // fresh 组屏蔽 SW：页面会话 CDP 节流覆盖不到 SW 目标（其实测
    // 无节流抢跑预缓存），首访纯网络路径须在无 SW 下量；warm 组
    // 保留 SW 量稳态。
    const { ctx, page, cdp } = await newPage(browser, throttle, parts[1] === 'fresh');
    if (parts[1] === 'fresh') {
      const rec = freshRec(); watch(cdp, rec);
      await bootOnce(page, rec, PROD);
      out.run = rec;
    } else {
      const rec1 = freshRec(); watch(cdp, rec1);
      await bootOnce(page, rec1, PROD);
      out.prime = { bootMs: rec1.bootMs };
      const rec2 = freshRec(); watch(cdp, rec2);
      await bootOnce(page, rec2, PROD);
      out.run = rec2;
    }
    await ctx.close();
  } else if (scenario === 'update-sim') {
    // 本地静态服：先供旧归档、后原地换新归档（同源同 URL，模拟部署切换）
    const OLD = process.env.OLD_DIR, NEW = process.env.NEW_DIR;
    let root = OLD;
    const srvLog = [];
    const BPS = parseInt(process.env.THROTTLE_BPS || '0', 10); // 服务端限速（字节/秒，0=不限）
    const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.css': 'text/css' };
    const srv = http.createServer((req, res) => {
      let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
      if (p === '/') p = '/index.html';
      const fp = path.join(root, p);
      const entry = { p, status: 200, sent: 0, t: Date.now() };
      srvLog.push(entry);
      try { fs.appendFileSync('/tmp/srvlog.jsonl', JSON.stringify(entry) + '\n'); } catch {}
      if (!fp.startsWith(root) || !fs.existsSync(fp) || fs.statSync(fp).isDirectory()) { entry.status = 404; res.writeHead(404); res.end(); return; }
      const data = fs.readFileSync(fp);
      const etag = 'W/"' + data.length + '-' + fs.statSync(fp).mtimeMs.toString(36) + '"';
      res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
      res.setHeader('ETag', etag);
      if (req.headers['if-none-match'] === etag) { entry.status = 304; res.writeHead(304); res.end(); return; }
      res.setHeader('Content-Type', mime[path.extname(fp)] || 'application/octet-stream');
      const ae = req.headers['accept-encoding'] || '';
      let body = data;
      if (ae.includes('br') && ['.wasm', '.js', '.html', '.json'].includes(path.extname(fp))) {
        res.setHeader('Content-Encoding', 'br');
        body = zlib.brotliCompressSync(data);
      }
      entry.sent = body.length;
      if (!BPS) { res.end(body); return; }
      // 限速发送：16KB 分片，片间延迟按 BPS 折算
      let off = 0;
      const CH = 16384;
      const step = () => {
        if (off >= body.length) { res.end(); return; }
        const part = body.subarray(off, off + CH);
        off += part.length;
        res.write(part);
        setTimeout(step, Math.round((part.length / BPS) * 1000));
      };
      step();
    });
    await new Promise((r) => srv.listen(0, '127.0.0.1', r));
    const url = `http://127.0.0.1:${srv.address().port}/`;
    out.localUrl = url;
    const { ctx, page, cdp } = await newPage(browser, null);
    const mark = () => srvLog.length;
    const slice = (a, b) => srvLog.slice(a, b);
    let m0 = mark();
    const rec1 = freshRec(); watch(cdp, rec1);
    await bootOnce(page, rec1, url);
    out.oldBoot = rec1;
    out.oldBootSrv = slice(m0, mark());
    // 等旧 SW 安装落定（预缓存完成）再切换部署，避免把安装中的
    // 跨版污染算进更新账
    await page.waitForTimeout(3000);
    m0 = mark();
    root = NEW; // 部署切换
    const rec2 = freshRec(); watch(cdp, rec2);
    await bootOnce(page, rec2, url);
    out.updateBoot = rec2;
    out.updateBootSrv = slice(m0, mark());
    // 等新 SW 预缓存落定后计其流量（预缓存与页面加载异步重叠，
    // 单列观察窗 6s 内的后续请求）
    m0 = mark();
    await page.waitForTimeout(6000);
    out.updateSettleSrv = slice(m0, mark());
    const rec3 = freshRec(); watch(cdp, rec3);
    await bootOnce(page, rec3, url);
    out.postUpdateBoot = rec3;
    await ctx.close();
    srv.close();
  } else if (scenario === 'swcheck') {
    out.check = await swcheck(browser);
  }
  console.log(JSON.stringify(out, null, 1));
  await browser.close();
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
