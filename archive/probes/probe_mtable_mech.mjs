// mtable 引擎机制实验：rowspacing 语义、字号与应用 CSS 的影响。
// 解释 probe_matrix_height 中「应用内 24px vs 裸页 38.69px」之差。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 900, height: 900 } });
const page = await ctx.newPage();

const TABLE = (rs, extra = '') => `<math display="block" ${extra}><mrow><mo fence="true" stretchy="true">(</mo><mtable columnalign="center center" columnspacing="1em" rowspacing="${rs}"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable><mo fence="true" stretchy="true">)</mo></mrow></math>`;

await page.setContent(`<!DOCTYPE html><body style="font-size:16px;margin:0">
<div id="a">${TABLE('1.37em')}</div>
<div id="b">${TABLE('0em')}</div>
<div id="c">${TABLE('3em')}</div>
<div id="d" style="font-size:16px">${TABLE('1.37em')}</div>
</body>`);
await page.waitForTimeout(300);
const m1 = await page.evaluate(() => {
  const R = (n) => Math.round(n * 100) / 100;
  const out = {};
  for (const id of ['a', 'b', 'c', 'd']) {
    const host = document.querySelector('#' + id);
    const math = host.querySelector('math');
    const tab = host.querySelector('mtable');
    const rows = [...tab.querySelectorAll(':scope > mtr')];
    out[id] = {
      mathH: R(math.getBoundingClientRect().height),
      tableH: R(tab.getBoundingClientRect().height),
      rowTops: rows.map((r) => R(r.getBoundingClientRect().top)),
      mathFontSize: getComputedStyle(math).fontSize,
      mtdFontSize: getComputedStyle(tab.querySelector('mtd')).fontSize,
    };
  }
  return out;
});
console.log('BARE', JSON.stringify(m1, null, 1));

// 同页注入应用四样式表后再量 a
await page.addStyleTag({ url: 'http://localhost:8197/styles.css' }).catch((e) => console.log('styletag err', String(e).slice(0, 80)));
await page.waitForTimeout(300);
const m2 = await page.evaluate(() => {
  const R = (n) => Math.round(n * 100) / 100;
  const host = document.querySelector('#a');
  const math = host.querySelector('math');
  const tab = host.querySelector('mtable');
  const rows = [...tab.querySelectorAll(':scope > mtr')];
  return {
    mathH: R(math.getBoundingClientRect().height),
    tableH: R(tab.getBoundingClientRect().height),
    rowTops: rows.map((r) => R(r.getBoundingClientRect().top)),
    mathFontSize: getComputedStyle(math).fontSize,
    bodyFont: getComputedStyle(document.body).fontFamily.slice(0, 40),
    mathFont: getComputedStyle(math).fontFamily.slice(0, 40),
  };
});
console.log('WITH-APP-CSS(styles.css if exists)', JSON.stringify(m2, null, 1));

await browser.close();
console.log('PROBE-MTABLE-MECH DONE');
