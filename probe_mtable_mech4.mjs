// mtable 机制实验四：页面级差异二分（视口 meta / 移动上下文）
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const T = `<math display="block"><mrow><mo fence="true" stretchy="true">(</mo><mtable columnalign="center center" columnspacing="1em" rowspacing="1.37em"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable><mo fence="true" stretchy="true">)</mo></mrow></math>`;
async function run(label, ctxOpts, html) {
  const ctx = await browser.newContext(ctxOpts);
  const page = await ctx.newPage();
  await page.setContent(html);
  await page.waitForTimeout(250);
  const h = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    return { mathH: R(document.querySelector('math').getBoundingClientRect().height), iw: window.innerWidth, dpr: window.devicePixelRatio };
  });
  console.log(label, JSON.stringify(h));
  await ctx.close();
}
const noMeta = `<!DOCTYPE html><body style="font-size:16px;margin:0">${T}</body>`;
const withMeta = `<!DOCTYPE html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="font-size:16px;margin:0">${T}</body>`;
await run('desktop 900 noMeta  ', { viewport: { width: 900, height: 900 } }, noMeta);
await run('desktop 900 withMeta', { viewport: { width: 900, height: 900 } }, withMeta);
await run('mobile 393 noMeta   ', { viewport: { width: 393, height: 852 }, hasTouch: true }, noMeta);
await run('mobile 393 withMeta ', { viewport: { width: 393, height: 852 }, hasTouch: true }, withMeta);
await browser.close();
console.log('MECH4 DONE');
