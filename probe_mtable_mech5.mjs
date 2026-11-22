// mtable 机制实验五：把应用 index.html 的整段 <style> 注入裸页，
// 确认是否为 CSS 所致；若是，再按源文件四分（tokens/base/
// editor/panels 在构建时拼接，可从仓库 styles/ 逐份取）。
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const T = `<math display="block"><mrow><mo fence="true" stretchy="true">(</mo><mtable columnalign="center center" columnspacing="1em" rowspacing="1.37em"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable><mo fence="true" stretchy="true">)</mo></mrow></math>`;
const html = fs.readFileSync('rust/apps/web/dist/index.html', 'utf8');
const styleAll = html.match(/<style>([\s\S]*?)<\/style>/)?.[1] || '';
console.log('app style bytes:', styleAll.length);
async function measure(label, cssList) {
  const ctx = await browser.newContext({ viewport: { width: 900, height: 900 } });
  const page = await ctx.newPage();
  await page.setContent(`<!DOCTYPE html><body style="font-size:16px;margin:0">${T}</body>`);
  for (const css of cssList) await page.addStyleTag({ content: css });
  await page.waitForTimeout(250);
  const h = await page.evaluate(() => Math.round(document.querySelector('math').getBoundingClientRect().height * 100) / 100);
  console.log(label, h);
  await ctx.close();
}
await measure('bare            ', []);
await measure('app style (all) ', [styleAll]);
for (const f of ['tokens', 'base', 'editor', 'panels']) {
  const css = fs.readFileSync(`rust/apps/web/styles/${f}.css`, 'utf8');
  await measure(`${f.padEnd(16)}`, [css]);
}
await browser.close();
console.log('MECH5 DONE');
