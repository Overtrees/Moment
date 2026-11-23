// W-2/W-1 探针（audit_wide_list.md）：
// W-2 同年 >30 天分组标签应为「N月」、跨年为「YYYY年」，time_ago 不受影响；
// W-1 宽屏标签带 data-tag-index 且第 3 个被 CSS 隐藏、+N 计数正确，窄屏不受影响。
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const BASE = process.env.BASE || 'http://127.0.0.1:8096';
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const fails = [];
const ok = (cond, msg) => { console.log((cond ? 'PASS ' : 'FAIL ') + msg); if (!cond) fails.push(msg); };

function zipStore(entries) {
  const crcTable = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcTable[n] = c >>> 0; }
  const crc32 = (buf) => { let c = 0xFFFFFFFF; for (const b of buf) c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
  const locals = [], centrals = []; let off = 0;
  for (const [name, data] of entries) {
    const nb = Buffer.from(name), crc = crc32(data);
    const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(0x0800, 6);
    lh.writeUInt32LE(crc, 14); lh.writeUInt32LE(data.length, 18); lh.writeUInt32LE(data.length, 22); lh.writeUInt16LE(nb.length, 26);
    locals.push(lh, nb, data);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(0x0800, 8);
    ch.writeUInt32LE(crc, 16); ch.writeUInt32LE(data.length, 20); ch.writeUInt32LE(data.length, 24); ch.writeUInt16LE(nb.length, 28); ch.writeUInt32LE(off, 42);
    centrals.push(ch, nb); off += 30 + nb.length + data.length;
  }
  const cd = Buffer.concat(centrals); const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
  return Buffer.concat([...locals, cd, end]);
}
const para = (text) => ({ type: 'paragraph', children: [{ text }] });
const iso = (d) => d.toISOString();

async function importFixture(page, memos) {
  const zip = zipStore([
    ['memos.json', Buffer.from(JSON.stringify({ version: 2, memos, files: {} }))],
    ['manifest.json', Buffer.from(JSON.stringify({ version: 1, attachments: {} }))],
  ]);
  await page.goto(BASE + '/', { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'w.zip', mimeType: 'application/zip', buffer: zip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.textContent.includes('已导入'), null, { timeout: 20000, polling: 300 });
  await page.goto(BASE + '/', { waitUntil: 'load' });
  await page.waitForSelector('.section-header', { timeout: 20000 });
  await page.waitForTimeout(800);
}

const now = new Date();
const d60 = new Date(now.getTime() - 60 * 864e5);
const crossYear = new Date(now.getFullYear() - 1, 11, 15, 12, 0, 0);
const expectOld = d60.getFullYear() === now.getFullYear() ? `${d60.getMonth() + 1}月` : `${d60.getFullYear()}年`;
const memos = [
  { id: 'w2-today', title: 'W2今天备忘', doc: [para('今天的内容')], pinned: false, createdAt: iso(now), updatedAt: iso(now) },
  { id: 'w2-old', title: 'W2同年旧备忘', doc: [para('两个月前的内容')], pinned: false, createdAt: iso(d60), updatedAt: iso(d60) },
  { id: 'w2-cross', title: 'W2跨年备忘', doc: [para('去年的内容')], pinned: false, createdAt: iso(crossYear), updatedAt: iso(crossYear) },
  { id: 'w1-tags', title: 'W1标签备忘', doc: [para('#alpha #beta #gamma #delta 标签正文')], pinned: false, createdAt: iso(now), updatedAt: iso(now) },
];

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
// ---- W-2（窄视口即可，分组口径与视口无关）----
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await importFixture(page, memos);
  const groups = await page.evaluate(() => {
    const out = {};
    document.querySelectorAll('.section-header').forEach((h) => {
      const wrap = h.parentElement;
      out[h.textContent.trim()] = wrap ? wrap.textContent : '';
    });
    return out;
  });
  console.log('groups:', Object.keys(groups).join(' | '));
  ok(groups['今天']?.includes('W2今天备忘'), 'W-2 今天组含今天的备忘');
  ok(groups[expectOld]?.includes('W2同年旧备忘'), `W-2 同年旧备忘归「${expectOld}」组`);
  ok(groups[`${now.getFullYear()}年`]?.includes('W2跨年备忘') || groups[`${now.getFullYear() - 1}年`]?.includes('W2跨年备忘'), 'W-2 跨年备忘归「YYYY年」组');
  ok(!groups[`${now.getFullYear()}年`]?.includes('W2同年旧备忘'), 'W-2 同年旧备忘不落本年「YYYY年」组');
  // time_ago 口径：同年旧卡面时间 M/D，跨年 Y/M/D
  const times = await page.evaluate(() => {
    const res = {};
    document.querySelectorAll('.list-item, .img-card').forEach((card) => {
      const t = card.textContent;
      for (const key of ['W2同年旧备忘', 'W2跨年备忘']) if (t.includes(key)) res[key] = t;
    });
    return res;
  });
  const md = `${d60.getMonth() + 1}/${d60.getDate()}`;
  const ymd = `${crossYear.getFullYear()}/${crossYear.getMonth() + 1}/${crossYear.getDate()}`;
  ok((times['W2同年旧备忘'] || '').includes(md), `W-2 time_ago 同年显示 ${md}`);
  ok((times['W2跨年备忘'] || '').includes(ymd), `W-2 time_ago 跨年显示 ${ymd}`);
  await ctx.close();
}
// ---- W-1 宽屏 ----
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, hasTouch: true });
  const page = await ctx.newPage();
  await importFixture(page, memos);
  const r = await page.evaluate(() => {
    const cards = [...document.querySelectorAll('.list-item, .img-card')];
    const card = cards.find((c) => c.textContent.includes('W1标签备忘'));
    if (!card) return { found: false };
    const tags = [...card.querySelectorAll('.item-tag:not(.item-tag-more)')].map((s) => ({
      idx: s.getAttribute('data-tag-index'), text: s.textContent.trim(), display: getComputedStyle(s).display,
    }));
    const more = card.querySelector('.item-tag-more');
    return { found: true, tags, more: more ? more.textContent.trim() : null };
  });
  console.log('wide tags:', JSON.stringify(r));
  ok(r.found, 'W-1 宽屏找到标签卡');
  ok(r.tags?.length === 3, 'W-1 标签渲染 3 个（摘要截断口径）');
  ok(r.tags?.every((t, i) => t.idx === String(i)), 'W-1 每标签带 data-tag-index=序号');
  ok(r.tags?.[2]?.display === 'none', 'W-1 宽屏第 3 标签 display=none');
  ok(r.tags?.[0]?.display !== 'none' && r.tags?.[1]?.display !== 'none', 'W-1 宽屏前 2 标签可见');
  ok(r.more === '+1', 'W-1 「+N」计数为 +1（3−2）');
  await ctx.close();
}
// ---- W-1 窄屏 ----
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await importFixture(page, memos);
  const r = await page.evaluate(() => {
    const cards = [...document.querySelectorAll('.list-item, .img-card')];
    const card = cards.find((c) => c.textContent.includes('W1标签备忘'));
    if (!card) return { found: false };
    const tags = [...card.querySelectorAll('.item-tag:not(.item-tag-more)')].map((s) => getComputedStyle(s).display);
    return { found: true, tags };
  });
  console.log('narrow tags:', JSON.stringify(r));
  ok(r.found && r.tags.length === 3 && r.tags.every((d) => d !== 'none'), 'W-1 窄屏 3 标签全可见（不受宽屏规则影响）');
  await ctx.close();
}
await browser.close();
console.log(fails.length ? `\n${fails.length} FAIL` : '\nALL PASS');
process.exit(fails.length ? 1 : 0);
