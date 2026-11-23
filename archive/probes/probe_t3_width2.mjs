// 标题三症重查 · 症2 补充：组字优先会话（新备忘聚焦后直接组字，
// 不先打字）+ 提交后同会话二次组字。逐帧采样同 probe_t3_width。
// 用法: node probe_t3_width2.mjs <rust|orig>
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const app = process.argv[2] || 'rust';
const RUST = 'http://localhost:8396/';
const ORIG = 'http://localhost:8397/Moment.html';
const SEL = app === 'rust' ? '#editor-title-text' : '.editor-title-input';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 200)));
const cdp = await ctx.newCDPSession(page);

const SAMPLER = (SEL) => {
  window.__frames = [];
  window.__fstop = false;
  const R = (v) => Math.round(v * 10) / 10;
  function sample() {
    const el = document.querySelector(SEL);
    if (el) {
      const scroller = el.parentElement;
      const capsule = scroller && scroller.parentElement;
      const cs = getComputedStyle(el);
      const csc = capsule ? getComputedStyle(capsule) : null;
      window.__frames.push({
        t: Math.round(performance.now()),
        len: (el.textContent || '').length,
        capW: capsule ? R(capsule.getBoundingClientRect().width) : null,
        fs: cs.fontSize, align: cs.textAlign,
        capPad: csc ? csc.paddingLeft + '/' + csc.paddingRight : null,
        elCls: el.getAttribute('class'), capCls: capsule ? capsule.getAttribute('class') : null,
        capStyle: capsule ? (capsule.getAttribute('style') || '').slice(0, 110) : null,
        scrStyle: scroller ? (scroller.getAttribute('style') || '').slice(0, 110) : null,
        elStyle: (el.getAttribute('style') || '').slice(0, 110),
        scrL: scroller ? scroller.scrollLeft : null,
      });
    }
    if (!window.__fstop) requestAnimationFrame(sample);
  }
  requestAnimationFrame(sample);
  return 'sampling';
};

async function mark(tag) {
  await page.evaluate((tag) => { window.__frames.push({ mark: tag, t: Math.round(performance.now()) }); }, tag);
}
async function titleCenter() {
  const box = await page.locator(SEL).boundingBox();
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

if (app === 'rust') {
  await page.goto(RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.click('.new-card-title');
} else {
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  await page.getByText('新建笔记', { exact: false }).first().click();
}
await page.waitForSelector(SEL, { timeout: 10000 });
await page.waitForTimeout(400);
console.log('SAMPLER', await page.evaluate(SAMPLER, SEL));
await page.waitForTimeout(1200);
const c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
await page.waitForTimeout(800);
await mark('Q1-focused');

// ---- 组字优先：直接长组字到 17 ----
const growth = ['w', 'we', 'wei', 'weis', 'weish', 'weishe', 'weishen', 'weishenm', 'weishenme', 'weishenmex', 'weishenmexu', 'weishenmexuy', 'weishenmexuya', 'weishenmexuyao', 'weishenmexuyaoz', 'weishenmexuyaozh', 'weishenmexuyaozhe'];
for (const s of growth) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(115);
}
await page.waitForTimeout(350);
await mark('Q2-composed-17');
try { await cdp.send('Input.imeCommitText', { text: '为什么需要这' }); }
catch (e) { await cdp.send('Input.insertText', { text: '为什么需要这' }); }
await page.waitForTimeout(500);
await mark('Q3-committed-6');

// ---- 同会话二次组字：从已提交 6 字续组到长 ----
const g2 = ['z', 'zh', 'zhe', 'zheg', 'zhege', 'zhegem', 'zhegemi', 'zhegemin', 'zhegeming', 'zhegemingz', 'zhegemingzi'];
for (const s of g2) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(115);
}
await page.waitForTimeout(350);
await mark('Q4-composed-2nd-total-17');
try { await cdp.send('Input.imeCommitText', { text: '这个名字' }); }
catch (e) { await cdp.send('Input.insertText', { text: '这个名字' }); }
await page.waitForTimeout(500);
await mark('Q5-committed-10');

await page.evaluate(() => { window.__fstop = true; });
const frames = await page.evaluate(() => window.__frames);
fs.writeFileSync(`/home/hatch/.tmp/t3_width2_${app}.json`, JSON.stringify(frames));
console.log('FRAMES', frames.length, 'saved', `/home/hatch/.tmp/t3_width2_${app}.json`);
await browser.close();
