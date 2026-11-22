// 标题点按落点组合探针（回归门）：
// A16 新建长标题(截断态)tap50 → 期望映射位(调优口径，见下)
// A8  新建短标题(未截断)tap50 → 期望点按处
// B16 重开长标题 tap30 → 期望映射位(调优口径)
// B8  重开短标题 tap50 → 期望点按处
// D16 程序聚焦长标题 → 期望文末(非点按口径不变)
// C16 长标题不失焦、编辑态内 tap50 → 期望点按处(解释验收观察)
// 【2026-11-22 调优，用户拍板，有意偏离原版】截断长标题点按
// 聚焦由「一律文末」改为「尊重落点」：点按先落在截断串(前 10
// 字+省略号)内，映射到全文字位——可见前缀内同位、省略号后→
// 全文末尾。期望映射位按点按前截断串字形边界实测推导(±1 字
// 容差)；探针标题均为 BMP 字符，UTF-16 单位 == 字符数。
// 用法：node probe_title_reopen2.mjs [base]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8231/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

const tapTitle = async (frac) => {
  const box = await page.locator('.editor-title-capsule').boundingBox();
  await page.touchscreen.tap(box.x + box.width * frac, box.y + box.height / 2);
  await page.waitForTimeout(900);
};
const titleText = () => page.evaluate(() => document.getElementById('editor-title-text').textContent);
const blurTitle = async () => { await page.touchscreen.tap(196, 500); await page.waitForTimeout(600); };
const newMemo = async () => {
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.click('.list-item:has-text("新建") .item-title-text');
  await page.waitForSelector('#editor-title-text', { timeout: 10000 });
  await page.waitForTimeout(800);
};
const backToList = async () => {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(600);
};
const openByTitle = async (frag) => {
  // 折叠日期组（总数>2）只渲染首卡、点首卡是展开：目标不可见时先展开
  for (let i = 0; i < 4; i++) {
    const el = page.locator(`.list-item:has-text("${frag}") .item-title-text`).first();
    if (await el.isVisible().catch(() => false)) {
      await el.click();
      // 折叠组首卡首击只展开不打开：编辑器没出现就再点一次
      if (await page.locator('#editor-title-text').isVisible().catch(() => false)) break;
      await page.waitForTimeout(700);
      if (await page.locator('#editor-title-text').isVisible().catch(() => false)) break;
      await el.click();
      break;
    }
    const dump = await page.evaluate(() => [...document.querySelectorAll('.list-item')].map((e, k) => k + ':' + (e.innerText || '').replace(/\n/g, '/').slice(0, 30)).join(' | '));
    console.log(`  [openByTitle ${frag} try${i}] list:`, dump);
    // 点「今天」组首卡展开（避开新建卡：取带时间戳的卡）
    await page.evaluate(() => {
      const items = [...document.querySelectorAll('.list-item')];
      const card = items.find((e) => /上午|下午|晚上|凌晨/.test(e.innerText || '')) || items[1];
      card && card.querySelector('.item-title-text')?.click();
    });
    await page.waitForTimeout(700);
    if (await page.locator('#editor-title-text').isVisible().catch(() => false)) {
      // 展开误入某篇编辑页：返回列表重试
      await page.click('.editor-fab.left');
      await page.waitForSelector('.list-item', { timeout: 10000 });
      await page.waitForTimeout(600);
    }
  }
  await page.waitForSelector('#editor-title-text', { timeout: 10000 });
  await page.waitForTimeout(900);
};
const setTitle = async (t) => {
  await tapTitle(0.5);
  await page.evaluate(() => document.execCommand('selectAll', false, null));
  await page.keyboard.type(t, { delay: 25 });
  await page.waitForTimeout(400);
  await blurTitle();
};
// 截断串字形边界实测：给定胶囊宽度比例 frac，推导浏览器应落的
// 截断串字界 c（最近边界）与点按坐标；expected(fullLen) 给出
// 映射后的全文字位期望。
const truncMap = async (frac) => {
  const info = await page.evaluate(() => {
    const el = document.getElementById('editor-title-text');
    const cap = document.querySelector('.editor-title-capsule');
    const node = el.firstChild;
    const text = el.textContent;
    const xs = [];
    for (let i = 0; i <= text.length; i++) {
      const r = document.createRange();
      if (i < text.length) { r.setStart(node, i); r.setEnd(node, i + 1); xs.push(r.getBoundingClientRect().left); }
      else { r.setStart(node, i - 1); r.setEnd(node, i); xs.push(r.getBoundingClientRect().right); }
    }
    const cr = cap.getBoundingClientRect();
    const er = el.getBoundingClientRect();
    // 点按 y 取标题文本行中心：胶囊中心落在标题与副标题之间，
    // 不是文本点按（命中测试与浏览器落点都以文本行为准）。
    return { text, xs, capX: cr.x, capW: cr.width, titleY: er.y + er.height / 2 };
  });
  const tapX = info.capX + info.capW * frac;
  let c = 0, best = Infinity;
  info.xs.forEach((x, i) => { const d = Math.abs(x - tapX); if (d < best) { best = d; c = i; } });
  return {
    tapX, y: info.titleY, truncLen: info.text.length, c,
    expected: (fullLen) => (c <= info.text.length - 1 ? c : fullLen),
  };
};
const tapAt = async (m) => { await page.touchscreen.tap(m.tapX, m.y); await page.waitForTimeout(900); };

await page.goto(BASE, { waitUntil: 'load' });
let fails = 0;
const ok = (cond, name, extra = '') => { console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : '')); if (!cond) fails++; };

// A16 + B16 + D16：长标题（截断态）
await newMemo();
await setTitle('长标题验收甲乙丙丁戊己庚辛壬癸子丑'); // 17 字
let m = await truncMap(0.5);
await tapAt(m);
let fullLen = (await titleText()).length;
await page.keyboard.type('X', { delay: 30 });
await page.waitForTimeout(300);
let t = await titleText();
ok(Math.abs(t.indexOf('X') - m.expected(fullLen)) <= 1, 'A16 新建长标题 tap50 落映射位(调优)', `X@${t.indexOf('X')} 期望≈${m.expected(fullLen)} (截断位 ${m.c}/${m.truncLen})`);
await blurTitle();
await backToList();
await openByTitle('长标题验收');
m = await truncMap(0.3);
await tapAt(m);
fullLen = (await titleText()).length;
await page.keyboard.type('Y', { delay: 30 });
await page.waitForTimeout(300);
t = await titleText();
ok(Math.abs(t.indexOf('Y') - m.expected(fullLen)) <= 1, 'B16 重开长标题 tap30 落映射位(调优)', `Y@${t.indexOf('Y')} 期望≈${m.expected(fullLen)} (截断位 ${m.c}/${m.truncLen})`);
await blurTitle();
// D16：程序聚焦（非点按）→ 文末口径不变
await page.evaluate(() => document.getElementById('editor-title-text').focus());
await page.waitForTimeout(800);
await page.keyboard.type('W', { delay: 30 });
await page.waitForTimeout(300);
t = await titleText();
ok(t.indexOf('W') === t.length - 1, 'D16 程序聚焦长标题落文末(非点按口径不变)', `W@${t.indexOf('W')}/${t.length}`);
await blurTitle();
await backToList();

// A8 + B8：短标题 8 字
await newMemo();
await setTitle('短标题甲乙丙丁'); // 7 字
await tapTitle(0.5);
await page.keyboard.type('X', { delay: 30 });
await page.waitForTimeout(300);
t = await titleText();
ok(t.indexOf('X') > 0 && t.indexOf('X') < t.length - 1, 'A8 新建短标题 tap50 落点按处', `X@${t.indexOf('X')}/${t.length} text=${t}`);
await blurTitle();
await backToList();
await openByTitle('短标题');
await tapTitle(0.5);
await page.keyboard.type('Y', { delay: 30 });
await page.waitForTimeout(300);
t = await titleText();
ok(t.indexOf('Y') > 0 && t.indexOf('Y') < t.length - 1, 'B8 重开短标题 tap50 落点按处', `Y@${t.indexOf('Y')}/${t.length} text=${t}`);
await blurTitle();
await backToList();

// C16：长标题编辑态内（不失焦）tap —— 验收「新建正确」观察的解释项
await newMemo();
await tapTitle(0.5);
await page.keyboard.type('编辑态长标题甲乙丙丁戊己庚辛', { delay: 25 }); // 15 字，仍聚焦
await page.waitForTimeout(400);
await tapTitle(0.5); // 已聚焦状态下再 tap（不触发 focus/截断替换）
await page.keyboard.type('Z', { delay: 30 });
await page.waitForTimeout(300);
t = await titleText();
console.log(`C16 编辑态内 tap50: Z@${t.indexOf('Z')}/${t.length} text=${t}`);

ok(errors.length === 0, '无 pageerror', errors.slice(0, 2).join('; '));
await browser.close();
console.log(fails === 0 ? 'ALL PASS' : `FAILS: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
