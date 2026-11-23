import { webkit } from 'playwright-core';
const browser = await webkit.launch();
const page = await browser.newPage();
await page.goto('http://localhost:8096/');
console.log('TITLE:', await page.title());
console.log('UA:', await page.evaluate(() => navigator.userAgent));
await browser.close();
console.log('DONE OK');
