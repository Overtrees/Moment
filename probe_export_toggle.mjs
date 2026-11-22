// 探针：第六批小修 A/B 验收
// A：导出面板关闭中点按 ••• 不吞击——关闭在飞时点 ••• 改道
//   回菜单（关闭照常落定、终点落在菜单），对照组（不点）全关。
// B：导出 HTML 含 math 字体栈规则且公式节点在（导出壳补栈）。
// 用法: node probe_export_toggle.mjs <base>
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8241/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
};

// ---------- 夹具 zip（同 smoke-rustweb-export 的内存构造） ----------
const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xFFFFFFFF; for (const b of buf) c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zipStore(files) {
  const enc = new TextEncoder();
  const chunks = []; const central = []; let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name); const data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
    const crc = crc32(data); const size = data.length;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
    lh.setUint32(14, crc, true); lh.setUint32(18, size, true); lh.setUint32(22, size, true);
    lh.setUint16(26, name.length, true);
    chunks.push(Buffer.from(lh.buffer), Buffer.from(name), Buffer.from(data));
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, 0x0800, true);
    ch.setUint32(16, crc, true); ch.setUint32(20, size, true); ch.setUint32(24, size, true);
    ch.setUint16(28, name.length, true); ch.setUint32(42, offset, true);
    central.push(Buffer.from(ch.buffer), Buffer.from(name));
    offset += 30 + name.length + size;
  }
  const cdSize = central.reduce((a, c) => a + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}
const ts = new Date().toISOString();
const para = (bid, text) => ({ id: bid, type: 'paragraph', children: [{ text }] });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'tog1', title: '改道测试', pinned: false, createdAt: ts, updatedAt: ts,
      doc: [para('t1', '改道探针正文。'), para('t2', '$$E=mc^2$$')] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

async function importAndOpen(page) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  const hasMemo = await page.evaluate(() => document.body.innerText.includes('改道测试'));
  if (!hasMemo) {
    await page.$eval('h1.page-title', (e) => e.click());
    await page.waitForSelector('.page-content', { timeout: 8000 });
    await page.click('.set-row:has-text("备份与恢复")');
    await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
    await page.setInputFiles('#file-import', { name: 'tog.zip', mimeType: 'application/zip', buffer: fixtureZip });
    await page.waitForSelector('.backup-modal', { timeout: 8000 });
    await page.click('.backup-modal .backup-btn.primary');
    await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  }
  await page.goto(base + '?open=tog1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(700);
}

async function openExportPanel(page) {
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(600);
}

const state = () => ({
  panel: !!document.querySelector('.editor-export-panel'),
  menu: !!document.querySelector('.editor-menu-panel'),
  scrim: !!document.querySelector('.menu-scrim'),
});

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

// ================= A1：关闭中点 ••• → 改道回菜单 =================
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importAndOpen(page);
  await openExportPanel(page);
  await page.mouse.click(40, 620); // 点遮罩发起全关
  await page.click('.editor-fab.right'); // 220ms 内立刻点 •••
  await page.waitForTimeout(700);
  const st = await page.evaluate(state);
  const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
  ok('A1 面板已卸载', !st.panel);
  ok('A1 菜单已打开（改道落点）', st.menu, `scrim=${st.scrim}`);
  ok('A1 Diag 有改道记录', diag.includes('export close diverted to menu'));
  ok('A1 无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ================= A2：对照——关闭不点 ••• → 全关 =================
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importAndOpen(page);
  await openExportPanel(page);
  await page.mouse.click(40, 620);
  await page.waitForTimeout(700);
  const st = await page.evaluate(state);
  ok('A2 面板已卸载', !st.panel);
  ok('A2 菜单未打开（全关）', !st.menu && !st.scrim);
  ok('A2 无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ================= B：导出 HTML 含 math 字体栈 + 公式节点 =================
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importAndOpen(page);
  await page.evaluate(() => {
    window.__blobs = [];
    const raw = URL.createObjectURL.bind(URL);
    URL.createObjectURL = (b) => { window.__blobs.push(b); return raw(b); };
  });
  await openExportPanel(page);
  await page.click('[data-export-format="html"]');
  await page.waitForFunction(() => (window.__blobs || []).some((b) => b.type.includes('text/html')), null, { timeout: 10000 });
  const html = await page.evaluate(async () => {
    const b = window.__blobs.find((x) => x.type.includes('text/html'));
    return b ? await b.text() : '';
  });
  ok('B 导出 HTML 含 STIX 字体栈规则', html.includes('"STIX Two Math","Cambria Math","Latin Modern Math","Noto Sans Math",math,serif'));
  ok('B 导出 HTML 含 <math> 节点', html.includes('<math'));
  ok('B 无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

await browser.close();
console.log(failures === 0 ? 'ALL PASS' : `FAILURES: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
