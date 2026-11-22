// mtable 机制实验二：字体栈对行高的影响（应用内 12px pitch 之源）
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const page = await (await browser.newContext({ viewport: { width: 900, height: 900 } })).newPage();
const T = `<math display="block"><mrow><mo fence="true" stretchy="true">(</mo><mtable columnalign="center center" columnspacing="1em" rowspacing="1.37em"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable><mo fence="true" stretchy="true">)</mo></mrow></math>`;
await page.setContent(`<!DOCTYPE html><body style="font-size:16px;margin:0">
<div id="plain">${T}</div>
<div id="appstack" style="font-family:-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'PingFang SC', sans-serif">${T}</div>
<div id="sans" style="font-family:sans-serif">${T}</div>
<div id="serif" style="font-family:serif">${T}</div>
<div id="mathff" style="font-family:math">${T}</div>
</body>`);
await page.waitForTimeout(300);
const m = await page.evaluate(() => {
  const R = (n) => Math.round(n * 100) / 100;
  const out = {};
  for (const id of ['plain', 'appstack', 'sans', 'serif', 'mathff']) {
    const host = document.querySelector('#' + id);
    const math = host.querySelector('math');
    const mi = host.querySelector('mi');
    out[id] = {
      mathH: R(math.getBoundingClientRect().height),
      mathFF: getComputedStyle(math).fontFamily,
      miFF: getComputedStyle(mi).fontFamily,
      miH: R(mi.getBoundingClientRect().height),
    };
  }
  return out;
});
console.log(JSON.stringify(m, null, 1));
await browser.close();
console.log('MECH2 DONE');
