import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const u = new URL(process.env.https_proxy);
const proxy = { server: `http://${u.hostname}:${u.port}`, username: decodeURIComponent(u.username), password: decodeURIComponent(u.password) };
// 方式一：context 级代理
try {
  const b1 = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
  const c1 = await b1.newContext({ proxy });
  const p1 = await c1.newPage();
  const r1 = await p1.goto('https://mynote-rustweb.pages.dev/', { timeout: 20000 }).catch((e) => 'ERR ' + String(e).slice(0, 90));
  console.log('ctx-proxy:', r1 && r1.status ? r1.status() : r1);
  await b1.close();
} catch (e) { console.log('ctx-proxy throw', String(e).slice(0, 120)); }
// 方式二：launch 级 + --proxy-server 原始串（不带凭据，预期 407 或隧道失败，仅作对照）
try {
  const b2 = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'], proxy });
  const p2 = await b2.newPage();
  const r2 = await p2.goto('https://example.com/', { timeout: 20000 }).catch((e) => 'ERR ' + String(e).slice(0, 90));
  console.log('launch-proxy example:', r2 && r2.status ? r2.status() : r2);
  await b2.close();
} catch (e) { console.log('launch-proxy throw', String(e).slice(0, 120)); }
