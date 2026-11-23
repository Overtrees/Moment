import { chromium } from 'playwright-core';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const browser = await chromium.launchPersistentContext('/tmp/mynote-test-profile', {
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  viewport: { width: 420, height: 900 },
  hasTouch: true,
  args: ['--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'],
});
const page = browser.pages()[0] || (await browser.newPage());
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await sleep(13000);

async function dumpSemantics(tag) {
  const data = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('flt-semantics, [role], [aria-label]').forEach((el) => {
      const r = el.getBoundingClientRect();
      const label = el.getAttribute('aria-label') || el.textContent || '';
      if (label && label.trim()) out.push({ label: label.trim().slice(0, 26), top: Math.round(r.top), height: Math.round(r.height) });
    });
    const sp = document.getElementById('spacer');
    return { items: out.slice(0, 40), y: Math.round(window.scrollY), spacer: sp ? sp.style.height : '?' };
  });
  console.log(`--- ${tag} scrollY=${data.y} spacer=${data.spacer}`);
  for (const it of data.items) console.log(`   top=${it.top} h=${it.height} ${it.label}`);
}

await page.evaluate(() => { const els=[...document.querySelectorAll("*")].filter(e=>e.textContent==="Enable accessibility"); if (els.length) els[0].click(); });
await sleep(2500);
await dumpSemantics("at top");
await page.evaluate(() => window.scrollTo(0, 100000000));
await sleep(1500);
await dumpSemantics('after scrollTo max #1');
await page.evaluate(() => window.scrollTo(0, 100000000));
await sleep(1500);
await dumpSemantics('after scrollTo max #2');
await page.screenshot({ path: '/tmp/v21/4-probe-bottom.png' });
await browser.close();
console.log('done');
