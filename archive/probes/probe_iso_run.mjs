import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
const srv = http.createServer((req, res) => {
  const f = req.url === '/isotest_setattr.js' ? '/tmp/isotest_setattr.js' : '/tmp/isotest2.html';
  res.setHeader('Content-Type', f.endsWith('.js') ? 'text/javascript' : 'text/html');
  res.end(fs.readFileSync(f));
}).listen(8123);
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const page = await (await browser.newContext()).newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
await page.goto('http://localhost:8123/isotest.html');
await page.waitForFunction(() => window.__out, null, { timeout: 8000, polling: 200 });
console.log((await page.evaluate(() => window.__out)).join('\n'));
await browser.close(); srv.close();
