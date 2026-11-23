// WebKit 启动冒烟：launch → 打开页面 → 读 title/UA
import { webkit } from 'playwright-core';
const url = process.argv[2] || 'http://localhost:8122/';
const browser = await webkit.launch();
console.log('LAUNCH OK');
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto(url, { waitUntil: 'load', timeout: 30000 });
const title = await page.title();
const ua = await page.evaluate(() => navigator.userAgent);
const hasBody = await page.evaluate(() => !!document.querySelector('.list-item, .page-title, body'));
console.log('TITLE', JSON.stringify(title));
console.log('UA', ua);
console.log('LOADED', hasBody);
await browser.close();
console.log('WKTEST PASS');
