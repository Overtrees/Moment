// 交互/动画/点击态探针：原版 vs Rust 版同流程采样计算样式。
// 用法: node audit_interact.mjs <origBase> <rustBase>
import { chromium } from 'playwright-core';

const [origBase, rustBase] = process.argv.slice(2);
const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});

async function probe(page, label) {
  const out = { label };
  const sample = async (sel) => page.evaluate((s) => {
    const el = document.querySelector(s);
    if (!el) return null;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return {
      anim: cs.animationName, animDur: cs.animationDuration,
      trans: cs.transitionProperty, transDur: cs.transitionDuration,
      opacity: cs.opacity, transform: cs.transform,
      w: Math.round(r.width), h: Math.round(r.height),
      bottom: Math.round(innerHeight - r.bottom), top: Math.round(r.top),
      bg: cs.backgroundColor, radius: cs.borderRadius,
    };
  }, sel);

  // 编辑器菜单（•••）：真实鼠标点击（原版 fab 走 pointerdown）
  const fabBox = await page.evaluate(() => {
    const el = document.querySelectorAll('.editor-fab')[1];
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  });
  if (fabBox) await page.mouse.click(fabBox.x, fabBox.y);
  await page.waitForTimeout(400);
  out.menu = await sample('.editor-menu-panel');
  out.menuRows = await page.$$eval('.editor-menu-panel .menu-item, .editor-menu-panel button', (e) => e.length).catch(() => 0);
  // 菜单行按下态
  out.menuPress = await page.evaluate(() => {
    const el = document.querySelector('.editor-menu-panel .menu-item, .editor-menu-panel button');
    if (!el) return null;
    el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    const cs = getComputedStyle(el);
    const r = { bg: cs.backgroundColor, transform: cs.transform };
    el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
    return r;
  });
  if (fabBox) await page.mouse.click(fabBox.x, fabBox.y);
  await page.waitForTimeout(300);

  // 斜杠面板
  await page.evaluate(() => {
    const el = document.querySelector('.detail .ed-line, .editor-body [data-bid], .editor-body [data-blockid], .editor-body p');
    if (el) { el.focus(); const r = document.createRange(); r.selectNodeContents(el); r.collapse(false); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
  });
  await page.keyboard.press('Enter');
  await page.waitForTimeout(250);
  await page.keyboard.type('/');
  await page.waitForTimeout(600);
  out.slash = await sample('.slash-panel');
  out.slashRows = await page.$$eval('.slash-row', (e) => e.length).catch(() => 0);
  out.slashPress = await page.evaluate(() => {
    const el = document.querySelector('.slash-row');
    if (!el) return null;
    el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    const cs = getComputedStyle(el);
    const r = { bg: cs.backgroundColor, transform: cs.transform };
    el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
    return r;
  });
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);

  // fab 按下态
  out.fabPress = await page.evaluate(() => {
    const el = document.querySelector('.editor-fab');
    if (!el) return null;
    el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    const cs = getComputedStyle(el);
    const r = { bg: cs.backgroundColor, transform: cs.transform, opacity: cs.opacity };
    el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
    return r;
  });
  console.log(JSON.stringify(out, null, 1));
}

for (const [label, base, openEditor] of [['ORIG', origBase, 'orig'], ['RUST', rustBase, 'rust']]) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForTimeout(2800);
  if (openEditor === 'orig') {
    await page.click('text=周末看展记录');
  } else {
    await page.waitForSelector('.list-item', { timeout: 20000 });
    await page.click('.list-item:has-text("周末看展记录") .item-title-text');
  }
  await page.waitForTimeout(1500);
  await probe(page, label);
  await ctx.close();
}
await browser.close();
