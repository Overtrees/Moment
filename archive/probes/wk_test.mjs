import { webkit } from 'playwright-core';
try {
  const b = await webkit.launch({ args: ['--no-sandbox'] });
  const p = await (await b.newContext({ viewport: { width: 393, height: 852 } })).newPage();
  await p.goto('http://localhost:8096/', { waitUntil: 'load' });
  await p.waitForTimeout(1500);
  console.log('WEBKIT OK, title=', await p.title(), 'ua=', await p.evaluate(() => navigator.userAgent));
  await b.close();
} catch (e) { console.log('WEBKIT FAIL', String(e).split('\n').slice(0, 4).join(' | ')); }
