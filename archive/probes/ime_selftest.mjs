// 自测：iPhone UA 下组合输入渲染（编辑器侧下划线应为关）+ 提交文本精确。
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://127.0.0.1:8094/';
const exe = process.env.CHROME;
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({
  viewport: { width: 900, height: 700 },
  userAgent:
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
});
await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(url).origin });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(9000);
await page.mouse.click(150, 200); // 打开种子笔记
await page.waitForTimeout(1800);
await page.mouse.click(430, 107); // 第一段末尾放光标
await page.waitForTimeout(600);

const cdp = await ctx.newCDPSession(page);
async function compose(text) {
  await cdp.send('Input.imeSetComposition', { text, selectionStart: text.length, selectionEnd: text.length });
  await page.waitForTimeout(120);
}
for (const s of ['z', 'ze', 'zei', 'zei s', 'zei shen', 'zei shen mi']) await compose(s);
await page.screenshot({ path: '/tmp/selftest-composing.png' }); // 组合中途截图
await cdp.send('Input.insertText', { text: '这神秘' });
await page.waitForTimeout(400);
await page.keyboard.press('Control+a');
await page.waitForTimeout(200);
await page.keyboard.press('Control+c');
await page.waitForTimeout(300);
const clip = await page.evaluate(() => navigator.clipboard.readText().catch(() => 'CLIP-FAIL'));
console.log('FIRST_PARA_OK:', clip.includes('这神秘') && !clip.includes('zei'));
console.log('ERRORS:', errors.length ? errors.join(' | ') : 'none');
await browser.close();
