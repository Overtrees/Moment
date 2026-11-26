// 专用探针：图片页（2026-11-24 由编辑页浮层改独立页面）。
// 守的行为：
//  ① 点图进页：编辑页点 image 块大图 → .img-page 在场、
//     .lightbox 不在场（浮层已退役）；页头标题 == 附件
//     清单真实文件名（big-photo.jpg）；Diag IMGPAGE
//     open 行带 name=big-photo.jpg 与 nat=3000x4000。
//  ② 尺寸 fit 口径（用户 2026-11-24 14:05 真机改判，
//     覆盖同日早先的「自然尺寸 1:1、可滚动」口径）：整
//     图 contain 适配进页头以下可用区——大图按比例缩
//     小到刚好放下、小图不放大，不变形不裁切，区内居
//     中，首屏完整可见、页面不需滚动。②守大竖图
//     3000x4000：渲染宽 == 可用区宽、高按比例且 ≤ 可
//     用区高、整图在视口内、居中、无滚动。
//  ③ 小图不放大：200x150 小图渲染 == 200x150；进页前
//     编辑页滚动位 y0（>0），返回后 scrollY ≈ y0（±2）
//     ——编辑状态/滚动按页面返回机制保留。
//  ④ gallery 入口：gallery File 项点按同样进页，标题
//     == gal-photo.png、大图 2400x1800 走同一 fit 口径。
//  ⑤ 根色口径：图片页根色与列表页根色同值（未设 /
//     rgb(242,242,247)，根页面色）；返回编辑页后根色
//     = 编辑 base（#FAFAFA）。
//  ⑥ URL 图入口（2026-11-24 扩围）：image 块 url 形
//     点按进页，标题 == i18n 兜底「图片」、渲染 == 自然
//     尺寸 30x20（小图不放大）。
//  ⑦ gallery Url 项入口（扩围）：标题兜底、渲染 ==
//     自然尺寸 40x24（小图不放大）。
//  ⑧ 附件图片文件行入口（扩围）：attachment 节点
//     image 标志 false 但 manifest type=image/png →
//     点按进页，标题 == att-photo.png、大图 1600x1200
//     走同一 fit 口径。
//  ⑨ 非图片附件行不接入图片页（负断言）：PDF 行点按
//     走系统分享链（2026-11-24 附件打开根治口径，与
//     probe_attachment_open 同口径）——canShare 先行、
//     navigator.share 被以该 PDF 的 File 调用、无新
//     标签打开、不进图片页、Diag ATT 行记录 shared。
//  ⑩ 大横图（image 块 fileId）：4000x1000 按宽适配、
//     fit 口径同 ②。
//  ⑪ 方形图（image 块 fileId）：2000x2000 按宽适配、
//     fit 口径同 ②。
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
import base64
uri30 = "data:image/png;base64," + base64.b64encode(png(30, 20)).decode()
uri40 = "data:image/png;base64," + base64.b64encode(png(40, 24)).decode()
doc.append({"id": "lbp-urlimg", "type": "image", "url": uri30, "children": []})
doc.append({"id": "lbp-galurl", "type": "gallery", "attrs": {"items": [{"url": uri40}]}, "children": []})
doc.append({"id": "lbp-attimg", "type": "attachment", "attrs": {"fileId": "attImg"}, "image": False, "children": []})
doc.append({"id": "lbp-attpdf", "type": "attachment", "attrs": {"fileId": "attPdf"}, "image": False, "children": []})
doc.append({"id": "lbp-wide", "type": "image", "attrs": {"fileId": "imgWide"}, "children": []})
doc.append({"id": "lbp-square", "type": "image", "attrs": {"fileId": "imgSquare"}, "children": []})
memo = {"id": "lbp-memo", "title": "图片页探针", "pinned": False,
        "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00",
        "doc": doc}
z = zipfile.ZipFile('/tmp/lbp_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memo]}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {
    "imgBig": {"name": "big-photo.jpg", "type": "image/png"},
    "imgSmall": {"name": "small.png", "type": "image/png"},
    "imgGal": {"name": "gal-photo.png", "type": "image/png"},
    "attImg": {"name": "att-photo.png", "type": "image/png"},
    "attPdf": {"name": "doc.pdf", "type": "application/pdf"},
    "imgWide": {"name": "wide-photo.jpg", "type": "image/png"},
    "imgSquare": {"name": "square.png", "type": "image/png"}}}))
z.writestr('attachments/imgBig', png(3000, 4000))
z.writestr('attachments/imgSmall', png(200, 150))
z.writestr('attachments/imgGal', png(2400, 1800))
z.writestr('attachments/attImg', png(1600, 1200))
z.writestr('attachments/imgWide', png(4000, 1000))
z.writestr('attachments/imgSquare', png(2000, 2000))
z.writestr('attachments/attPdf', b'%PDF-1.4 probe')
z.close()
print('lbp_probe.zip ready')
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true, colorScheme: 'light' });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
// 分享链桩（⑨ 用，与 probe_attachment_open 同口径）：记录
// App 侧对 share/canShare/window.open 的调用；canShare=true。
await page.addInitScript(`
  window.__lbpShare = { share: [], canShare: [], open: [] };
  Object.defineProperty(navigator, 'share', { configurable: true, value: (data) => {
    window.__lbpShare.share.push({ title: data.title || null, files: (data.files || []).map(f => ({ name: f.name, type: f.type, size: f.size })) });
    return Promise.resolve();
  } });
  Object.defineProperty(navigator, 'canShare', { configurable: true, value: (data) => {
    window.__lbpShare.canShare.push({ nfiles: (data.files || []).length });
    return true;
  } });
  window.open = (url, target) => { window.__lbpShare.open.push({ url: String(url).slice(0, 80), target: target || null }); return null; };
`);

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
// fit 口径量测：img 渲染盒 + 可用区（.img-page-content
// 内容盒 = 边框盒减 padding）+ 文档滚动面，一次读齐。
const pageImgGeom = () => page.evaluate(() => {
  const img = document.querySelector('.img-page-img');
  const c = document.querySelector('.img-page-content');
  if (!img || !c) return null;
  const r = img.getBoundingClientRect();
  const cr = c.getBoundingClientRect();
  const cs = getComputedStyle(c);
  const padL = parseFloat(cs.paddingLeft), padR = parseFloat(cs.paddingRight);
  const padT = parseFloat(cs.paddingTop), padB = parseFloat(cs.paddingBottom);
  return {
    img: { x: r.x, y: r.y, w: r.width, h: r.height },
    avail: { x: cr.x + padL, y: cr.y + padT, w: cr.width - padL - padR, h: cr.height - padT - padB },
    scroll: {
      sh: document.documentElement.scrollHeight, ch: document.documentElement.clientHeight,
      sw: document.documentElement.scrollWidth, iw: window.innerWidth, ih: window.innerHeight,
    },
  };
});
// shrink-only contain 期望：缩放比 = min(1, 区宽/图宽, 区高/图高)
function fitExpect(natW, natH, aw, ah) {
  const s = Math.min(1, aw / natW, ah / natH);
  return { w: natW * s, h: natH * s };
}
async function checkFit(label, natW, natH) {
  const g = await pageImgGeom();
  ok(`${label} 几何可读`, !!g);
  if (!g) return;
  const exp = fitExpect(natW, natH, g.avail.w, g.avail.h);
  const dump = `img=${g.img.w.toFixed(1)}x${g.img.h.toFixed(1)}@${g.img.x.toFixed(1)},${g.img.y.toFixed(1)} exp=${exp.w.toFixed(1)}x${exp.h.toFixed(1)} avail=${g.avail.w.toFixed(1)}x${g.avail.h.toFixed(1)}`;
  ok(`${label} 渲染宽 == fit 期望（±1）`, Math.abs(g.img.w - exp.w) <= 1, dump);
  ok(`${label} 渲染高 == fit 期望（±1）`, Math.abs(g.img.h - exp.h) <= 1, dump);
  ok(`${label} 整图在视口内`,
    g.img.x >= -0.5 && g.img.y >= -0.5
      && g.img.x + g.img.w <= g.scroll.iw + 0.5 && g.img.y + g.img.h <= g.scroll.ih + 0.5, dump);
  ok(`${label} 区内居中（中心偏差 ≤2）`,
    Math.abs((g.img.x + g.img.w / 2) - (g.avail.x + g.avail.w / 2)) <= 2
      && Math.abs((g.img.y + g.img.h / 2) - (g.avail.y + g.avail.h / 2)) <= 2, dump);
  ok(`${label} 页面不需滚动`,
    g.scroll.sh <= g.scroll.ch + 1 && g.scroll.sw <= g.scroll.iw + 1,
    `sh=${g.scroll.sh} ch=${g.scroll.ch} sw=${g.scroll.sw} iw=${g.scroll.iw}`);
}
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

// ① + ② 大图进页、标题、fit 适配（3000x4000 按宽放下、
// 整图首屏可见、不滚动）
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
  ok('① Diag IMGPAGE open 带 name=big-photo.jpg nat=3000x4000',
    /IMGPAGE open name=big-photo\.jpg nat=3000x4000/.test(diag), diag.slice(-200));
  const g0 = await pageImgGeom();
  ok('② 大竖图渲染宽 == 可用区宽（按宽适配，±1）',
    !!g0 && Math.abs(g0.img.w - g0.avail.w) <= 1,
    g0 ? `img.w=${g0.img.w.toFixed(1)} avail.w=${g0.avail.w.toFixed(1)}` : 'no-geom');
  await checkFit('② 大竖图 3000x4000', 3000, 4000);
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
  await checkFit('③ 小图 200x150', 200, 150);
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
  await checkFit('④ gallery 大图 2400x1800', 2400, 1800);
  await backFromImgPage();
  ok('④ 返回回编辑页', (await page.$('.detail')) !== null);
}

const rowZone = (wrapSel) => page.evaluate((sel) => {
  const el = document.querySelector(sel + ' .attachment-file');
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, wrapSel);
const scrollWrapIntoView = async (wrapSel, innerSel) => {
  await page.evaluate((args) => {
    const w = document.querySelector(args[0]);
    const el = args[1] ? (w ? w.querySelector(args[1]) : null) : w;
    if (el) el.scrollIntoView({ block: 'center' });
  }, [wrapSel, innerSel || '']);
  await page.waitForTimeout(500);
};

// ⑥ URL 图入口（扩围）：image 块 url 形进页、标题兜底、
// 渲染 == 自然尺寸
{
  await scrollWrapIntoView('[data-wrapbid="lbp-urlimg"]', 'img');
  const zone = await imgZone('[data-wrapbid="lbp-urlimg"]');
  ok('⑥ URL 图可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('⑥ 标题 == i18n 兜底「图片」（无 fileId）', (await pageTitle()) === '图片', await pageTitle());
  const rect = await pageImgRect();
  ok('⑥ URL 图渲染 == 自然尺寸 30x20',
    !!rect && rect.w === 30 && rect.h === 20, JSON.stringify(rect));
  await backFromImgPage();
  ok('⑥ 返回回编辑页', (await page.$('.detail')) !== null);
}

// ⑦ gallery Url 项入口（扩围）
{
  await scrollWrapIntoView('[data-wrapbid="lbp-galurl"]', 'img');
  const zone = await imgZone('[data-wrapbid="lbp-galurl"]');
  ok('⑦ gallery Url 图可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('⑦ 标题 == i18n 兜底「图片」', (await pageTitle()) === '图片', await pageTitle());
  const rect = await pageImgRect();
  ok('⑦ gallery Url 图渲染 == 自然尺寸 40x24',
    !!rect && rect.w === 40 && rect.h === 24, JSON.stringify(rect));
  await backFromImgPage();
  ok('⑦ 返回回编辑页', (await page.$('.detail')) !== null);
}

// ⑧ 附件图片文件行入口（扩围）：image 标志 false、文件
// 为图片类 → 进页、标题 == 清单文件名、大图走 fit 口径
{
  await scrollWrapIntoView('[data-wrapbid="lbp-attimg"]', '.attachment-file');
  const zone = await rowZone('[data-wrapbid="lbp-attimg"]');
  ok('⑧ 附件图片行可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('⑧ 标题 == 文件名 att-photo.png', (await pageTitle()) === 'att-photo.png', await pageTitle());
  await checkFit('⑧ 附件大图 1600x1200', 1600, 1200);
  await backFromImgPage();
  ok('⑧ 返回回编辑页', (await page.$('.detail')) !== null);
}

// ⑩ 大横图入口（image 块 fileId）：4000x1000 按宽适配
{
  await scrollWrapIntoView('[data-wrapbid="lbp-wide"]', 'img');
  const zone = await imgZone('[data-wrapbid="lbp-wide"]');
  ok('⑩ 大横图可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('⑩ 标题 == 文件名 wide-photo.jpg', (await pageTitle()) === 'wide-photo.jpg', await pageTitle());
  await checkFit('⑩ 大横图 4000x1000', 4000, 1000);
  await backFromImgPage();
  ok('⑩ 返回回编辑页', (await page.$('.detail')) !== null);
}

// ⑪ 方形图入口（image 块 fileId）：2000x2000 按宽适配
{
  await scrollWrapIntoView('[data-wrapbid="lbp-square"]', 'img');
  const zone = await imgZone('[data-wrapbid="lbp-square"]');
  ok('⑪ 方形图可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(400);
  ok('⑪ 标题 == 文件名 square.png', (await pageTitle()) === 'square.png', await pageTitle());
  await checkFit('⑪ 方形图 2000x2000', 2000, 2000);
  await backFromImgPage();
  ok('⑪ 返回回编辑页', (await page.$('.detail')) !== null);
}

// ⑨ 非图片附件行不接入图片页（负断言）：点按走分享链、
// 不开新标签、不进页（附件打开根治口径）
{
  await scrollWrapIntoView('[data-wrapbid="lbp-attpdf"]', '.attachment-file');
  const zone = await rowZone('[data-wrapbid="lbp-attpdf"]');
  ok('⑨ PDF 行可定位', !!zone);
  const popupP = page.waitForEvent('popup', { timeout: 3000 }).catch(() => null);
  await page.touchscreen.tap(zone.x, zone.y);
  // 分享在手势内同步发起，短轮询等桩记录落定
  let shareRec = null;
  for (let i = 0; i < 25 && !shareRec; i++) {
    shareRec = await page.evaluate(() => (window.__lbpShare && window.__lbpShare.share.length
      ? window.__lbpShare : null));
    if (!shareRec) await page.waitForTimeout(200);
  }
  ok('⑨ 点 PDF 行 → navigator.share 被调用一次', !!shareRec && shareRec.share.length === 1,
    JSON.stringify(shareRec && shareRec.share));
  const sh = shareRec && shareRec.share[0];
  ok('⑨ share 以该 PDF 的 File 调用（name/type/size）',
    !!sh && sh.files.length === 1 && sh.files[0].name === 'doc.pdf'
      && sh.files[0].type === 'application/pdf' && sh.files[0].size === 14,
    JSON.stringify(sh));
  ok('⑨ share title=文件名 doc.pdf', !!sh && sh.title === 'doc.pdf', sh && sh.title);
  ok('⑨ canShare 先行判定', !!shareRec && shareRec.canShare.length >= 1,
    `canShare=${shareRec && shareRec.canShare.length}`);
  ok('⑨ window.open 未被调用', !!shareRec && shareRec.open.length === 0,
    JSON.stringify(shareRec && shareRec.open));
  const popup = await popupP;
  ok('⑨ 无新标签打开', !popup);
  if (popup) await popup.close();
  await page.waitForTimeout(400);
  ok('⑨ 未进图片页', (await page.$('.img-page')) === null);
  ok('⑨ 仍在编辑页', (await page.$('.detail')) !== null);
  const dtxt = await waitDiag((t) => t.includes('attPdf') && t.includes('-> shared'));
  ok('⑨ Diag ATT 行记录 attPdf -> shared', dtxt.includes('-> shared'));
}

await browser.close();
console.log(`\nprobe_lightbox_page: ${pass} pass, ${fail} fail`);
if (fail === 0) console.log('ALL PASS');
process.exit(fail === 0 ? 0 : 1);
