// 专用探针：新建卡天气行（审计 WL-W-3 补回）验证。
// 数据源 = 和风天气（部署注入 key，原版仓库 key 为空——
// 无 key 时与原版同行为：不渲染天气行）；呈现链路由缓存
// 路径验证（缓存与网络回填共用同一渲染面）：
//  ① 无缓存时新建卡无 .newcard-weather（不占位、不报错）；
//  ② 种新鲜缓存（v6、30 分钟内）后重载：天气块出现，
//     温度「23°」、城市经 toCn 英转中（Shanghai → 上海）
//     且带状况文案；Diag 有 WEATHER cache hit 结果行；
//  ③ 过期缓存（>30 分钟）+ 无 key：整条链优雅失败，
//     天气行不出现、列表正常渲染、Diag 记失败原因行。
// 用法：node probe_weather.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);

// ① 无缓存：无天气行
ok('① 无缓存时无天气行', await page.locator('.newcard-weather').count() === 0);

// ② 新鲜缓存 → 天气行渲染（温度/城市英转中/状况）
await page.evaluate(() => {
  localStorage.setItem('weather_cache', JSON.stringify({
    temp: 23, city: 'Shanghai', condition: '晴', lat: 31.2, lng: 121.5,
    ts: Date.now(), v: 6,
  }));
});
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.newcard-weather', { timeout: 15000 });
const temp = await page.locator('.weather-temp').innerText();
const city = await page.locator('.weather-city').innerText();
ok('② 温度渲染', temp.trim() === '23°', temp.trim());
ok('② 城市英转中 + 状况', city.includes('上海') && city.includes('晴'), city.trim());
// cache hit 结果行在挂载后 1500ms 的拉取里落 Diag，且
// Diag 落盘有 1s 节流：轮询等行（判据不变）。
let diag = [];
for (let i = 0; i < 20; i++) {
  diag = await page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
  });
  if (diag.some((l) => String(l).includes('WEATHER') && String(l).includes('cache hit'))) break;
  await page.waitForTimeout(500);
}
ok('② Diag 有 WEATHER cache hit 行', diag.some((l) => String(l).includes('WEATHER') && String(l).includes('cache hit')));

// ③ 过期缓存 + 无 key：优雅失败、无天气行、列表正常
await page.evaluate(() => {
  localStorage.setItem('weather_cache', JSON.stringify({
    temp: 9, city: 'Beijing', condition: '阴', lat: 39.9, lng: 116.4,
    ts: Date.now() - 31 * 60 * 1000, v: 6,
  }));
});
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
// 拉取链最坏耗时 = 1500ms 延迟 + 5s 定位竞速 + 4s IP 请求
// + Diag 1s 节流落盘：轮询等失败原因行落盘（判据不变）。
let diag3 = [];
for (let i = 0; i < 40; i++) {
  diag3 = await page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
  });
  if (diag3.some((l) => String(l).includes('WEATHER') && (String(l).includes('no api key') || String(l).includes('locate failed')))) break;
  await page.waitForTimeout(500);
}
ok('③ Diag 记 WEATHER 失败原因', diag3.some((l) => String(l).includes('WEATHER') && (String(l).includes('no api key') || String(l).includes('locate failed'))));
ok('③ 过期缓存不渲染天气行', await page.locator('.newcard-weather').count() === 0);

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
