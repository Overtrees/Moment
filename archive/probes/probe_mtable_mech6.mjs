// mtable 机制实验六：验证 mtd padding 假设 + 修复后量测。
// 裸页三态：无 CSS / 仅 *{margin:0;padding:0} / 重置后补 mtd UA padding。
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const T = `<math display="block"><mrow><mo fence="true" stretchy="true">(</mo><mtable columnalign="center center" columnspacing="1em" rowspacing="1.37em"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable><mo fence="true" stretchy="true">)</mo></mrow></math>`;
const TF = `<math display="block"><mrow><mo fence="true" stretchy="true">(</mo><mtable columnalign="center center" columnspacing="1em" rowspacing="1.37em"><mtr><mtd><mfrac><mn>1</mn><mn>2</mn></mfrac></mtd><mtd><mfrac><mn>1</mn><mn>3</mn></mfrac></mtd></mtr><mtr><mtd><mfrac><mn>1</mn><mn>4</mn></mfrac></mtd><mtd><mfrac><mn>1</mn><mn>5</mn></mfrac></mtd></mtr></mtable><mo fence="true" stretchy="true">)</mo></mrow></math>`;
async function run(label, css) {
  const ctx = await browser.newContext({ viewport: { width: 900, height: 900 } });
  const page = await ctx.newPage();
  await page.setContent(`<!DOCTYPE html><body style="font-size:16px;margin:0"><div id="L">${T}</div><div id="F">${TF}</div></body>`);
  if (css) await page.addStyleTag({ content: css });
  await page.waitForTimeout(250);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const g = (id) => { const e = document.querySelector('#' + id + ' math'); const r = e.getBoundingClientRect(); return { h: R(r.height), w: R(r.width) }; };
    const mtd = document.querySelector('mtd');
    const cs = getComputedStyle(mtd);
    return { letters: g('L'), fracs: g('F'), mtdPadding: cs.paddingTop + '/' + cs.paddingLeft };
  });
  console.log(label.padEnd(34), JSON.stringify(m));
  await ctx.close();
}
await run('no css (UA default)', null);
await run('* {margin:0;padding:0}', '* { box-sizing: border-box; margin: 0; padding: 0; }');
await run('reset + mtd UA padding', '* { box-sizing: border-box; margin: 0; padding: 0; } mtd { padding: 0.5ex 0.4ex; }');
await run('reset + mtd block-only padding', '* { box-sizing: border-box; margin: 0; padding: 0; } mtd { padding: 0.5ex 0; }');
await browser.close();
console.log('MECH6 DONE');
