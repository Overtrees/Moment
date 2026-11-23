// 批 7 专用探针：列表卡片键盘可达性（D-21 三处：图片卡/文本卡/
// 新建卡 role=group + tabIndex=0 + aria-label + Enter/Space 打开；
// 展开按钮上的 Enter 不得穿透到卡片打开）与封面取图口径
// （按 manifest attachments[id].type 判定 image/*、字节迟到时
// 5×300ms 重试内补出；非图片类型恒空封面），及 W-4 超宽头部
// 轴线（≥1280 头像左缘/搜索胶囊右缘与 .container 边框盒左右
// 缘差 ≤1px，1440/1920/1280 三宽量测）。
// 用法：node probe_list_cards.mjs <baseURL>；全过打印 ALL PASS。
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import json, zipfile, datetime, struct
now = datetime.datetime.now().astimezone()
ts = now.isoformat()
def att(i, title, fid):
    return {"id": f"lc{i}", "title": title, "pinned": False, "createdAt": ts, "updatedAt": ts,
            "doc": [{"id": f"a{i}", "type": "attachment", "fileId": fid, "status": "done", "image": True}]}
def txt(i, title, body):
    return {"id": f"lc{i}", "title": title, "pinned": False, "createdAt": ts, "updatedAt": ts,
            "doc": [{"id": f"t{i}", "type": "paragraph", "children": [{"text": body}]}]}
memos = [
    att(1, "SVG封面卡", "att-svg1"),
    att(2, "BMP封面卡", "att-bmp1"),
    att(3, "PDF附件卡", "att-pdf1"),
    att(4, "迟到封面卡", "att-late1"),
    txt(5, "文本甲", "甲卡片正文"),
    txt(6, "文本乙", "乙卡片正文"),
    txt(7, "文本丙", "丙卡片正文"),
]
data = {"version": 2, "exportedAt": ts, "memos": memos, "avatars": {}}
man = {"version": 1, "attachments": {
    "att-svg1": {"name": "pic.svg", "type": "image/svg+xml"},
    "att-bmp1": {"name": "pic.bmp", "type": "image/bmp"},
    "att-pdf1": {"name": "doc.pdf", "type": "application/pdf"},
    "att-late1": {"name": "late.png", "type": "image/png"},
}}
svg = b'<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>'
row = bytes([0, 0, 255, 0])
bmp = b'BM' + struct.pack('<IHHI', 58, 0, 0, 54) + struct.pack('<IiiHHIIiiII', 40, 1, 1, 1, 24, 0, len(row), 2835, 2835, 0, 0) + row
pdf = b'%PDF-1.4\\n1 0 obj\\n<<>>\\nendobj\\n%%EOF'
import base64
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
z = zipfile.ZipFile('/tmp/list_cards.zip', 'w')
z.writestr('memos.json', json.dumps(data, ensure_ascii=False))
z.writestr('manifest.json', json.dumps(man, ensure_ascii=False))
z.writestr('attachments/att-svg1', svg)
z.writestr('attachments/att-bmp1', bmp)
z.writestr('attachments/att-pdf1', pdf)
z.writestr('attachments/att-late1', png)
z.close()
print('list_cards.zip ready')
PYEOF`);

const PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
let fails = 0;
const ok = (name, cond) => { console.log((cond ? '✓ ' : '✗ ') + name); if (!cond) fails++; };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });

// 导入夹具（设置 → 备份与恢复 → 选 zip → 确认）
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', '/tmp/list_cards.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 8000 });
await page.waitForSelector('.img-card', { timeout: 8000 });

// ---------- D-21 属性面 ----------
const cardAttrs = (sel) => page.$eval(sel, (e) => ({
  role: e.getAttribute('role'), tab: e.getAttribute('tabindex'), label: e.getAttribute('aria-label'),
})).catch(() => null);

const svgA = await cardAttrs('.img-card[aria-label="SVG封面卡，图片笔记，按回车或空格打开"]');
ok('图片卡 role=group/tabindex=0/aria-label 逐字', !!svgA && svgA.role === 'group' && svgA.tab === '0');
const txtA = await cardAttrs('.list-item[aria-label="文本甲，按回车或空格打开"]');
ok('文本卡 role=group/tabindex=0/aria-label 逐字', !!txtA && txtA.role === 'group' && txtA.tab === '0');
const newA = await cardAttrs('.list-item[aria-label="新建笔记，按回车或空格打开"]');
ok('新建卡 role=group/tabindex=0/aria-label 逐字', !!newA && newA.role === 'group' && newA.tab === '0');

// ---------- 封面：manifest type 判定 ----------
// 图片组默认折叠（只渲染首卡）：先展开，四卡全进 DOM。
await page.click('.img-card[aria-label="SVG封面卡，图片笔记，按回车或空格打开"] .expand-btn');
await page.waitForSelector('.img-card[aria-label="BMP封面卡，图片笔记，按回车或空格打开"]', { timeout: 5000 });
const coverOk = (label) => page.waitForFunction((l) => {
  const card = document.querySelector(`.img-card[aria-label="${l}"]`);
  const img = card && card.querySelector('img.img-cover');
  return !!img && img.naturalWidth > 0;
}, label, { timeout: 6000 }).then(() => true).catch(() => false);
ok('SVG 封面出图（type=image/svg+xml，非嗅探格式）', await coverOk('SVG封面卡，图片笔记，按回车或空格打开'));
ok('BMP 封面出图（type=image/bmp，非嗅探格式）', await coverOk('BMP封面卡，图片笔记，按回车或空格打开'));
await page.waitForTimeout(1500);
const pdfImg = await page.$$eval('.img-card[aria-label="PDF附件卡，图片笔记，按回车或空格打开"] img.img-cover', (els) => els.length);
ok('PDF 附件恒空封面（type 非 image/*）', pdfImg === 0);

// ---------- 键盘打开：文本卡 Enter ----------
await page.click('.list-item[aria-label="文本甲，按回车或空格打开"] .expand-btn'); // 展开文本组（三卡全显）
await page.waitForFunction(() => document.querySelectorAll('.list-item[aria-label$="，按回车或空格打开"]').length >= 4, null, { timeout: 5000 });
await page.$eval('.list-item[aria-label="文本乙，按回车或空格打开"]', (e) => e.focus());
await page.keyboard.press('Enter');
const openedByEnter = await page.waitForSelector('.editor-body [data-bid]', { timeout: 8000 }).then(() => true).catch(() => false);
ok('文本卡聚焦 + Enter 打开编辑器', openedByEnter);
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 8000 });

// ---------- 展开按钮 Enter 不穿透（守卫等价性） ----------
await page.click('.list-item[aria-label="文本甲，按回车或空格打开"] .expand-btn');
await page.waitForTimeout(300);
const collapseBtn = await page.evaluate(() => {
  const card = document.querySelector('.list-item[aria-label="文本丙，按回车或空格打开"]');
  const b = card && card.querySelector('.expand-btn');
  if (b && b.innerText.includes('收起')) { b.focus(); return true; }
  return false;
});
ok('展开态末卡收起按钮可聚焦', collapseBtn);
await page.keyboard.press('Enter');
await page.waitForTimeout(500);
const editorAbsent = await page.evaluate(() => !document.querySelector('.editor-body'));
const collapsedAgain = await page.evaluate(() => {
  const card = document.querySelector('.list-item[aria-label="文本甲，按回车或空格打开"]');
  const b = card && card.querySelector('.expand-btn');
  return !!b && b.innerText.includes('展开');
});
ok('收起按钮 Enter 只收起、不打开编辑器（目标守卫）', editorAbsent && collapsedAgain);

// ---------- 键盘打开：图片卡 Space ----------
// 先展开图片组（折叠态首卡的打开语义是展开组、非打开备忘）
await page.click('.img-card[aria-label="SVG封面卡，图片笔记，按回车或空格打开"] .expand-btn');
await page.waitForTimeout(300);
await page.$eval('.img-card[aria-label="SVG封面卡，图片笔记，按回车或空格打开"]', (e) => e.focus());
await page.keyboard.press('Space');
const openedBySpace = await page.waitForSelector('.editor-body [data-bid]', { timeout: 8000 }).then(() => true).catch(() => false);
ok('图片卡聚焦 + Space 打开编辑器', openedBySpace);
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 8000 });

// ---------- 键盘打开：新建卡 Enter ----------
await page.$eval('.list-item[aria-label="新建笔记，按回车或空格打开"]', (e) => e.focus());
await page.keyboard.press('Enter');
const openedNew = await page.waitForSelector('.editor-body [data-bid]', { timeout: 8000 }).then(() => true).catch(() => false);
ok('新建卡聚焦 + Enter 新建并打开编辑器', openedNew);
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 8000 });

// ---------- 封面重试：字节迟到 400ms 仍补出 ----------
await page.evaluate(async () => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  await new Promise((res, rej) => { const rq = db.transaction('attachments', 'readwrite').objectStore('attachments').delete('att-late1'); rq.onsuccess = () => res(); rq.onerror = () => rej(rq.error); });
});
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 8000 });
// 展开图片组使迟到卡挂载（挂载即启动重试循环，此时字节未到）
await page.click('.img-card[aria-label="SVG封面卡，图片笔记，按回车或空格打开"] .expand-btn');
await page.waitForSelector('.img-card[aria-label="迟到封面卡，图片笔记，按回车或空格打开"]', { timeout: 8000 });
await page.waitForTimeout(400);
await page.evaluate(async (b64) => {
  const bin = atob(b64); const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  await new Promise((res, rej) => { const rq = db.transaction('attachments', 'readwrite').objectStore('attachments').put(arr, 'att-late1'); rq.onsuccess = () => res(); rq.onerror = () => rej(rq.error); });
}, PNG_B64);
ok('封面字节迟到（400ms）经重试补出', await coverOk('迟到封面卡，图片笔记，按回车或空格打开'));

// ---------- W-4：超宽头部轴线 ----------
for (const w of [1440, 1920, 1280]) {
  await page.setViewportSize({ width: w, height: 900 });
  await page.waitForTimeout(450);
  const m = await page.evaluate(() => {
    const c = document.querySelector('.container').getBoundingClientRect();
    const av = document.querySelector('h1.page-title').firstElementChild.getBoundingClientRect();
    const s = document.querySelector('.glass-search-trigger').getBoundingClientRect();
    return { cl: c.left, cr: c.right, al: av.left, sr: s.right };
  });
  console.log(`W-4 @${w}: container=[${m.cl},${m.cr}] avatarLeft=${m.al} searchRight=${m.sr}`);
  ok(`W-4 @${w} 头像左缘与内容列左缘差 ≤1px`, Math.abs(m.al - m.cl) <= 1);
  ok(`W-4 @${w} 搜索右缘与内容列右缘差 ≤1px`, Math.abs(m.sr - m.cr) <= 1);
}

await browser.close();
console.log(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
