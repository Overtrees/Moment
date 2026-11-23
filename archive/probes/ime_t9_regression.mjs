// T9 式组合输入回归：整段重写组合区多次，最后提交汉字，校验文档文本无乱码。
// 用法: node ime_t9_regression.mjs <url>
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://127.0.0.1:8093/';
const exe = process.env.CHROME;
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 900, height: 700 } });
await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(url).origin });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(9000);

// 打开种子笔记（点标题文字，已知好坐标）
await page.mouse.click(150, 200);
await page.waitForTimeout(1800);
// 点第一段末尾放光标
await page.mouse.click(430, 107);
await page.waitForTimeout(600);
// 先直输一个标记，确认焦点在编辑器里
await page.keyboard.type('~', { delay: 30 });
await page.waitForTimeout(200);

const cdp = await ctx.newCDPSession(page);
async function compose(text) {
  await cdp.send('Input.imeSetComposition', {
    text,
    selectionStart: text.length,
    selectionEnd: text.length,
  });
  await page.waitForTimeout(120);
}
async function commit(text) {
  await cdp.send('Input.insertText', { text });
  await page.waitForTimeout(150);
}

// 第一轮：T9 式逐键整段重写 m -> mi -> min -> ming -> mingn -> mingni，提交「明」
for (const s of ['m', 'mi', 'min', 'ming', 'mingn', 'mingni']) await compose(s);
await commit('明');
// 英文直输
await page.keyboard.type('ok', { delay: 60 });
// 第二轮：重分段（组合串中途整体变样） n -> ni -> ning -> 提交「宁」
for (const s of ['n', 'ni', 'nin', 'ning']) await compose(s);
await commit('宁');
await page.waitForTimeout(500);

await page.screenshot({ path: '/tmp/ime-t9.png' });

// 全选复制读回文档文本
await page.keyboard.press('Control+a');
await page.waitForTimeout(200);
await page.keyboard.press('Control+c');
await page.waitForTimeout(300);
const clip = await page.evaluate(() => navigator.clipboard.readText().catch(() => 'CLIP-FAIL'));
console.log('CLIPBOARD:', JSON.stringify(clip));
console.log('ERRORS:', errors.length ? errors.join(' | ') : 'none');
await browser.close();
