// 专用探针：图片页（2026-11-24 由编辑页浮层改独立页面）。
// 守的行为：
//  ① 点图进页：编辑页点 image 块大图 → .img-page 在场、
//     .lightbox 不在场（浮层已退役）；页头标题 == 附件
//     清单真实文件名（big-photo.jpg）；Diag IMGPAGE
//     open 行带 name=big-photo.jpg 与 nat=1200x1600。
//  ② 原尺寸渲染：大图渲染宽高 == 自然尺寸 1200x1600
//     （不设 max、不缩放）；页面可纵向滚（scrollHeight
//     > clientHeight 且 scrollTo 后 scrollY > 0）；超宽
//     图可横向滚（scrollWidth > innerWidth）。
//  ③ 小图不放大：200x150 小图渲染 == 200x150；进页前
//     编辑页滚动位 y0（>0），返回后 scrollY ≈ y0（±2）
//     ——编辑状态/滚动按页面返回机制保留。
//  ④ gallery 入口：gallery File 项点按同样进页，标题
//     == gal-photo.png、渲染 == 800x600。
//  ⑤ 根色口径：图片页根色与列表页根色同值（未设 /
//     rgb(242,242,247)，根页面色）；返回编辑页后根色
//     = 编辑 base（#FAFAFA）。
// 夹具 PNG 以 zlib 手工构造（IHDR 指定宽高、IDAT 零行），
// 不依赖 PIL。用法: node probe_lightbox_page.mjs [baseURL]
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const url = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import json, struct, zlib, zipfile

def png(w, h):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    raw = (b'\\x00' + b'\\x00' * (w * 3)) * h
    return (b'\\x89PNG\\r\\n\\x1a\\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

doc = [{"id": "lbp-big", "type": "image", "attrs": {"fileId": "imgBig"}, "children": []}]
for i in range(1, 31):
    doc.append({"id": f"lbp-f{i}", "type": "paragraph", "children": [{"text": f"填充段落 {i:02d}，用于撑起可滚动的长文档。"}]})
doc.append({"id": "lbp-small", "type": "image", "attrs": {"fileId": "imgSmall"}, "children": []})
doc.append({"id": "lbp-gal", "type": "gallery", "attrs": {"items": [{"fileId": "imgGal"}]}, "children": []})
memo = {"id": "lbp-memo", "title": "图片页探针", "pinned": False,
        "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00",
        "doc": doc}
z = zipfile.ZipFile('/tmp/lbp_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memo]}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {
    "imgBig": {"name": "big-photo.jpg", "type": "image/png"},
    "imgSmall": {"name": "small.png", "type": "image/png"},
    "imgGal": {"name": "gal-photo.png", "type": "image/png"}}}))
z.writestr('attachments/imgBig', png(1200, 1600))
z.writestr('attachments/imgSmall', png(200, 150))
z.writestr('attachments/imgGal', png(800, 600))
z.close()
print('lbp_probe.zip ready')
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true, colorScheme: 'light' });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

let pass = 0, fail = 0;
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ok', name); }
  else { fail++; console.log('  FAIL', name, extra); }
}

const rootState = () => page.evaluate(() => {
  const cs = getComputedStyle(document.documentElement);
  return { varBg: cs.getPropertyValue('--mn-root-bg').trim(), htmlBg: cs.backgroundColor };
});
const diagText = () => page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
async function waitDiag(pred, timeoutMs = 8000) {
  const t0 = Date.now();
  let txt = await diagText();
  while (!pred(txt) && Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(200);
    txt = await diagText();
  }
  return txt;
}
const imgZone = (wrapSel) => page.evaluate((sel) => {
  const w = document.querySelector(sel);
  const el = w ? w.querySelector('img') : null;
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, wrapSel);
const pageTitle = () => page.evaluate(() => {
  const t = document.querySelector('.img-page .page-title');
  return t ? t.textContent.trim() : '';
});
const pageImgRect = () => page.evaluate(() => {
  const img = document.querySelector('.img-page-img');
  if (!img) return null;
  const r = img.getBoundingClientRect();
  return { w: Math.round(r.width), h: Math.round(r.height) };
});
async function backFromImgPage() {
  await page.click('.img-page .editor-fab.left');
  await page.waitForSelector('.detail', { timeout: 8000 });
  await page.waitForTimeout(400);
}

// 导入夹具（与 probe_root_dim 的 importZip 同流程）
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('h1.page-title', { timeout: 8000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', '/tmp/lbp_probe.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { polling: 200, timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });

// ⑤ 基线：列表页根色（与图片页同值判据的对照值）
const listRoot = await rootState();
ok('⑤ 列表基线根色：未设 / rgb(242, 242, 247)',
  listRoot.varBg === '' && listRoot.htmlBg === 'rgb(242, 242, 247)', JSON.stringify(listRoot));

// 打开夹具备忘（身份打印留证，防测错篇）
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
    .find((e) => e.textContent.includes('图片页探针'));
  if (el) el.click();
});
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(800);
const edTitle = await page.evaluate(() => document.querySelector('.detail') ? 'in-editor' : 'missing');
ok('打开夹具备忘「图片页探针」进入编辑页', edTitle === 'in-editor');

// ① + ② 大图进页、标题、自然尺寸、可滚
{
  const zone = await imgZone('[data-wrapbid="lbp-big"]');
  ok('① 大图可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('① 进图片页：.img-page 在场、.lightbox 不在场',
    (await page.$('.img-page')) !== null && (await page.$('.lightbox')) === null);
  ok('① 标题 == 文件名 big-photo.jpg', (await pageTitle()) === 'big-photo.jpg', await pageTitle());
  const diag = await waitDiag((t) => t.includes('IMGPAGE open'));
  ok('① Diag IMGPAGE open 带 name=big-photo.jpg nat=1200x1600',
    /IMGPAGE open name=big-photo\.jpg nat=1200x1600/.test(diag), diag.slice(-200));
  const rect = await pageImgRect();
  ok('② 大图渲染 == 自然尺寸 1200x1600（不缩放）',
    !!rect && rect.w === 1200 && rect.h === 1600, JSON.stringify(rect));
  const scrollInfo = await page.evaluate(() => ({
    sh: document.documentElement.scrollHeight,
    ch: document.documentElement.clientHeight,
    sw: document.documentElement.scrollWidth,
    iw: window.innerWidth,
  }));
  ok('② 页面可纵向滚（scrollHeight > clientHeight）', scrollInfo.sh > scrollInfo.ch, JSON.stringify(scrollInfo));
  await page.evaluate(() => window.scrollTo(0, 500));
  await page.waitForTimeout(300);
  const sy = await page.evaluate(() => window.scrollY);
  ok('② 纵向滚动位移 > 0（scrollY = 500）', sy === 500, String(sy));
  ok('② 超宽图横向可滚（scrollWidth > innerWidth）', scrollInfo.sw > scrollInfo.iw, JSON.stringify(scrollInfo));
  const pgRoot = await rootState();
  ok('⑤ 图片页根色与列表页同值（根页面色）',
    pgRoot.varBg === listRoot.varBg && pgRoot.htmlBg === listRoot.htmlBg, JSON.stringify(pgRoot));
  await backFromImgPage();
  const edRoot = await rootState();
  ok('⑤ 返回编辑页根色 = 编辑 base（#FAFAFA / rgb(250, 250, 250)）',
    edRoot.varBg.toLowerCase() === '#fafafa' && edRoot.htmlBg === 'rgb(250, 250, 250)', JSON.stringify(edRoot));
}

// ③ 小图不放大 + 返回保滚动位
{
  await page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="lbp-small"]');
    const el = w ? w.querySelector('img') : null;
    if (el) el.scrollIntoView({ block: 'center' });
  });
  await page.waitForTimeout(500);
  const y0 = await page.evaluate(() => window.scrollY);
  ok('③ 进页前编辑页已滚（y0 > 0）', y0 > 0, String(y0));
  const zone = await imgZone('[data-wrapbid="lbp-small"]');
  ok('③ 小图可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('③ 标题 == 文件名 small.png', (await pageTitle()) === 'small.png', await pageTitle());
  const rect = await pageImgRect();
  ok('③ 小图渲染 == 自然尺寸 200x150（不放大）',
    !!rect && rect.w === 200 && rect.h === 150, JSON.stringify(rect));
  await backFromImgPage();
  const y1 = await page.evaluate(() => window.scrollY);
  ok('③ 返回后编辑页滚动位保留（scrollY ≈ y0 ±2）', Math.abs(y1 - y0) <= 2, `y0=${y0} y1=${y1}`);
}

// ④ gallery 入口
{
  await page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="lbp-gal"]');
    const el = w ? w.querySelector('img') : null;
    if (el) el.scrollIntoView({ block: 'center' });
  });
  await page.waitForTimeout(500);
  const zone = await imgZone('[data-wrapbid="lbp-gal"]');
  ok('④ gallery 图可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('④ 标题 == 文件名 gal-photo.png', (await pageTitle()) === 'gal-photo.png', await pageTitle());
  const rect = await pageImgRect();
  ok('④ gallery 图渲染 == 自然尺寸 800x600',
    !!rect && rect.w === 800 && rect.h === 600, JSON.stringify(rect));
  await backFromImgPage();
  ok('④ 返回回编辑页', (await page.$('.detail')) !== null);
}

await browser.close();
console.log(`\nprobe_lightbox_page: ${pass} pass, ${fail} fail`);
if (fail === 0) console.log('ALL PASS');
process.exit(fail === 0 ? 0 : 1);
