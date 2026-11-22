// 独立双栏模式 + 矮横屏开关可见性 双边探针
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function openEditor(page, url) {
  await page.goto(url, { waitUntil: 'load', timeout: 20000 });
  await page.waitForTimeout(2000);
  await page.locator('.container .list-item, .container .img-card').first().click({ timeout: 5000 });
  await page.waitForTimeout(1200);
}

// A) 1280x800 独立双栏：开菜单 → 找双栏开关 → 切换 → 度量两列
for (const [name, url] of [['RUST', 'http://localhost:8106/'], ['ORIG', 'http://localhost:8107/Moment.html']]) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  const page = await ctx.newPage();
  try {
    await openEditor(page, url);
    // 打开 ••• 菜单（右上 fab）
    await page.evaluate(() => {
      const btns = Array.from(document.querySelectorAll('button'));
      const more = btns.find((b) => b.className.includes('more-btn')) || document.querySelector('.editor-fab.right, .more-btn');
      if (more) more.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await page.waitForTimeout(700);
    const menu = await page.evaluate(() => {
      const t = document.querySelector('.editor-column-mode-toggle, .twopane-row, .menu-item');
      const all = Array.from(document.querySelectorAll('.editor-menu-panel *, .menu-item, button')).map((b) => (b.className + '|' + (b.textContent || '').trim().slice(0, 14)));
      const tog = document.querySelector('.editor-column-mode-toggle');
      return { togglePresent: !!tog, toggleDisplay: tog ? getComputedStyle(tog).display : '-', items: all.slice(0, 14) };
    });
    console.log(`1280x800 ${name} MENU ${JSON.stringify(menu)}`);
    // 点开关
    await page.evaluate(() => {
      const tog = document.querySelector('.editor-column-mode-toggle, .twopane-row');
      if (tog) tog.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await page.waitForTimeout(900);
    const cols = await page.evaluate(() => {
      const cs = Array.from(document.querySelectorAll('.editor-column'));
      return {
        n: cs.length,
        info: cs.map((c) => ({ h: c.clientHeight, sh: c.scrollHeight, oy: getComputedStyle(c).overflowY, ce: c.getAttribute('contenteditable') })),
        bodyDisplay: (() => { const b = document.querySelector('.editor-body'); return b ? getComputedStyle(b).display : '-'; })(),
      };
    });
    console.log(`1280x800 ${name} TWOPANE ${JSON.stringify(cols)}`);
  } catch (e) {
    console.log(`1280x800 ${name} FAIL ${String(e).slice(0, 140)}`);
  }
  await ctx.close();
}

// B) 800x500 矮横屏：双栏开关是否可见（原版媒体查询要求 h>=600 或 w>=1100）
for (const [name, url] of [['RUST', 'http://localhost:8106/'], ['ORIG', 'http://localhost:8107/Moment.html']]) {
  const ctx = await browser.newContext({ viewport: { width: 800, height: 500 }, hasTouch: true });
  const page = await ctx.newPage();
  try {
    await openEditor(page, url);
    await page.evaluate(() => {
      const more = document.querySelector('.more-btn') || Array.from(document.querySelectorAll('button')).find((b) => b.className.includes('more'));
      if (more) more.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await page.waitForTimeout(700);
    const vis = await page.evaluate(() => {
      const tog = document.querySelector('.editor-column-mode-toggle, .twopane-row');
      const body = document.querySelector('.editor-body');
      return {
        togglePresent: !!tog,
        toggleDisplay: tog ? getComputedStyle(tog).display : '-',
        editorCols: body ? getComputedStyle(body).columnCount : '-',
      };
    });
    console.log(`800x500 ${name} ${JSON.stringify(vis)}`);
  } catch (e) {
    console.log(`800x500 ${name} FAIL ${String(e).slice(0, 140)}`);
  }
  await ctx.close();
}
await browser.close();
console.log('DONE');
