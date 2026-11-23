import { webkit } from 'playwright-core';
import fs from 'node:fs';
const dir = process.env.HOME + '/.cache/ms-playwright';
let exe = null;
for (const d of fs.readdirSync(dir)) {
  if (d.startsWith('webkit')) {
    const p = dir + '/' + d + '/pw_run.sh';
    if (fs.existsSync(p)) exe = p;
  }
}
console.log('exe candidate:', exe);
try {
  const browser = await webkit.launch({ executablePath: exe || undefined, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.goto('http://localhost:8196/', { waitUntil: 'load' });
  console.log('webkit goto ok, title len:', (await page.content()).length);
  await browser.close();
  console.log('WEBKIT WORKS');
} catch (e) {
  console.log('WEBKIT FAIL:', String(e).slice(0, 300));
}
