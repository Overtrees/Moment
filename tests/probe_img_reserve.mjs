// 专用探针：D-22 续项图片几何预留（imgsize 共用机制）。
// 守的行为（用户 2026-11-24 立项：给图片预留尺寸使
// loading=lazy 真正生效 + 根治且 UIUX 统一）：
//  ① 长文档解码数：20 张附件图（1200x2000 高图，单盒
//     ≈602px、全文 ≈12,400px，使懒加载距离阈值在本
//     harness 的 ECT 口径下也能把解码数压到近视口量级）
//     长备忘开页
//     T+300ms 已解码数显著 <20（只近视口）；滚动到底后
//     全部解码（新构建）。基线构建（生产 91554d079d）
//     同夹具开页应 20/20（对照，批 11 已 proven）。
//  ② 布局位移：长文档尾地标段在「首屏渲染（预留已生
//     效、屏外图未载）」与「全部载入后回到顶部」两个时
//     点的文档内纵坐标差 ≤1px。
//  ③ 载入后几何回归：混合备忘 8 个呈现点（独立图高图
//     /URL 独立图/gallery File/gallery Url/附件图/图文
//     卡/图文行/MD 行内图）的载入后渲染宽高与基线构建
//     逐项一致（±1px）。
//  ④ 占位呈现统一：8 个呈现点 img 的 computed 背景色
//     逐项一致（--fill-subtle 令牌值）；URL 图在缓存命
//     中时（第二次进入、响应被挂起）占位盒几何 == 载
//     入后几何、背景/圆角与载入态同值。
//  ⑤ URL 尺寸缓存：首次载入后 localStorage
//     mynote_imgsize_v1 含该 URL 的 [w,h]；首次进入无
//     预留（响应挂起时盒高 ≈0）属预期、只记录。
// 用法：node probe_img_reserve.mjs [newBaseURL] [baseBaseURL]
//   默认 new=http://localhost:8116/ base=http://localhost:8117/
//   夹具 http 图由本探针在 8120 端口自带服务提供。
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';

const newBase = process.argv[2] || 'http://localhost:8116/';
const baseBase = process.argv[3] || 'http://localhost:8117/';
const FXPORT = 8120;
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import json, struct, zlib, os
def png(w, h, rgb=(0, 0, 0)):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    row = b'\\x00' + bytes(rgb) * w
    return (b'\\x89PNG\\r\\n\\x1a\\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(row * h)) + chunk(b'IEND', b''))
os.makedirs('/tmp/d22fx', exist_ok=True)
open('/tmp/d22fx/wide.png', 'wb').write(png(1600, 400, (200, 30, 30)))
open('/tmp/d22fx/gal.png', 'wb').write(png(640, 480, (30, 200, 30)))
open('/tmp/d22fx/md.png', 'wb').write(png(500, 250, (30, 30, 200)))
atts = {}
docA = []
for i in range(20):
    fid = f"d22a{i:02d}"
    docA.append({"id": f"a-img{i}", "type": "image", "attrs": {"fileId": fid}, "children": []})
    atts[fid] = {"name": f"a{i:02d}.png", "type": "image/png"}
docA.append({"id": "a-land", "type": "paragraph", "children": [{"text": "D22-LANDMARK 尾段"}]})
memoA = {"id": "d22-long", "title": "D22长文档", "pinned": False,
         "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00", "doc": docA}
import base64
md_data = "data:image/png;base64," + base64.b64encode(png(640, 400, (120, 120, 0))).decode()
docB = [
    {"id": "b-tall", "type": "image", "attrs": {"fileId": "bTall"}, "children": []},
    {"id": "b-url", "type": "image", "url": "http://localhost:8120/wide.png", "children": []},
    {"id": "b-gal", "type": "gallery", "attrs": {"items": [{"fileId": "bGalF"}, {"url": "http://localhost:8120/gal.png"}]}, "children": []},
    {"id": "b-att", "type": "attachment", "attrs": {"fileId": "bAtt"}, "image": True, "children": []},
    {"id": "b-itc", "type": "imgTextCard", "attrs": {"fileId": "bItc"}, "children": [{"text": "图文卡文本"}]},
    {"id": "b-itr", "type": "imageTextRow", "attrs": {"fileId": "bItr"}, "children": [{"text": "图文行文本"}]},
    {"id": "b-md", "type": "paragraph", "children": [{"text": "MD 图一 ![d](" + md_data + ") 图二 ![h](http://localhost:8120/md.png) 完"}]},
]
atts.update({
    "bTall": {"name": "tall.png", "type": "image/png"},
    "bGalF": {"name": "galf.png", "type": "image/png"},
    "bAtt": {"name": "att.png", "type": "image/png"},
    "bItc": {"name": "itc.png", "type": "image/png"},
    "bItr": {"name": "itr.png", "type": "image/png"},
})
memoB = {"id": "d22-mix", "title": "D22混合", "pinned": False,
         "createdAt": "2026-11-22T11:00:00+08:00", "updatedAt": "2026-11-22T11:00:00+08:00", "doc": docB}
z = __import__('zipfile').ZipFile('/tmp/d22_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memoA, memoB]}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": atts}))
for i in range(20):
    z.writestr(f"attachments/d22a{i:02d}", png(1200, 2000))
z.writestr('attachments/bTall', png(900, 2000))
z.writestr('attachments/bGalF', png(800, 600))
z.writestr('attachments/bAtt', png(1024, 768))
z.writestr('attachments/bItc', png(1200, 800))
z.writestr('attachments/bItr', png(1200, 800))
z.close()
print('d22_probe.zip ready')
PYEOF`);

// 夹具 http 图服务（探针自带）
const fxServer = http.createServer((req, res) => {
  const name = req.url.replace(/^\//, '');
  const path = '/tmp/d22fx/' + name;
  if (fs.existsSync(path)) {
    // 应用以 COEP require-corp 跨源隔离提供（serve_headers 与生产
    // 同口径）；图床须回 CORP cross-origin 才可被 <img> 跨源载入。
    res.writeHead(200, {
      'Content-Type': 'image/png',
      'Cross-Origin-Resource-Policy': 'cross-origin',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(fs.readFileSync(path));
  } else {
    res.writeHead(404); res.end();
  }
});
await new Promise((r) => fxServer.listen(FXPORT, r));

let pass = 0, fail = 0;
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ok', name); }
  else { fail++; console.log('  FAIL', name, extra); }
}

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function importAndOpen(base, title) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'light' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('h1.page-title', { timeout: 15000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/tmp/d22_probe.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { polling: 200, timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes(t));
    if (el) el.click();
  }, title);
  await page.waitForSelector('.detail', { timeout: 8000 });
  await page.waitForTimeout(600);
  return { ctx, page };
}

const decodedCount = (page) => page.evaluate(() =>
  [...document.querySelectorAll('.editor-body img')].filter((i) => i.naturalWidth > 0).length);
const imgCount = (page) => page.evaluate(() =>
  document.querySelectorAll('.editor-body img').length);
const landmarkTop = (page) => page.evaluate(() => {
  const el = [...document.querySelectorAll('.editor-body *')]
    .find((e) => e.children.length === 0 && e.textContent.includes('D22-LANDMARK'));
  if (!el) return null;
  return el.getBoundingClientRect().top + window.scrollY;
});

// ── ①② 新构建：长文档解码数 + 地标位移 ──
{
  const { ctx, page } = await importAndOpen(newBase, 'D22长文档');
  await page.waitForTimeout(300);
  const total = await imgCount(page);
  const dec0 = await decodedCount(page);
  console.log(`  [new] 长文档 img 总数=${total} T+300ms 已解码=${dec0}`);
  ok('① 新构建长文档开页解码显著 <20', total === 20 && dec0 < 20 && dec0 <= 12, `total=${total} decoded=${dec0}`);
  const l0 = await landmarkTop(page);
  // 滚动到底（分步触发 lazy）再回顶部
  await page.evaluate(async () => {
    const H = document.documentElement.scrollHeight;
    for (let y = 0; y <= H; y += 600) {
      window.scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 220));
    }
    window.scrollTo(0, document.documentElement.scrollHeight);
  });
  await page.waitForTimeout(900);
  const decAll = await decodedCount(page);
  ok('① 滚动到底后全部解码', decAll === 20, `decoded=${decAll}`);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(400);
  const l1 = await landmarkTop(page);
  console.log(`  [new] 地标 top 首屏=${l0} 全载后=${l1}`);
  ok('② 地标位移 ≤1px', l0 !== null && l1 !== null && Math.abs(l1 - l0) <= 1, `l0=${l0} l1=${l1}`);
  await ctx.close();
}

// ── ③④ 新构建：混合备忘各呈现点几何 + 占位样式 ──
const SITES = [
  ['独立图(高图)', '.atomic[data-type="image"] img'],
  ['URL独立图', null], // 第二个 .atomic[data-type=image]（url 形）在 evaluate 内按序取
  ['gallery File', '.gallery-grid img >> nth=0'],
  ['gallery Url', '.gallery-grid img >> nth=1'],
  ['附件图', '.atomic.attachment img'],
  ['图文卡', '.itc-img-wrap img'],
  ['图文行', '.itr-img img'],
  ['MD行内(data)', '.md-preview-inline img, .markdown-render img >> nth=0'],
  ['MD行内(http)', '.md-preview-inline img, .markdown-render img >> nth=1'],
];
async function siteGeoms(page) {
  return page.evaluate(() => {
    const grab = (el) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      return {
        w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10,
        bg: cs.backgroundColor, radius: cs.borderTopLeftRadius,
        nat: el.naturalWidth + 'x' + el.naturalHeight,
      };
    };
    const standalone = document.querySelectorAll('.atomic[data-type="image"] > img');
    const gal = document.querySelectorAll('.gallery-grid img');
    const md = document.querySelectorAll('.md-preview-inline img, .markdown-render img');
    return {
      '独立图(高图)': grab(standalone[0]),
      'URL独立图': grab(standalone[1]),
      'gallery File': grab(gal[0]),
      'gallery Url': grab(gal[1]),
      '附件图': grab(document.querySelector('.atomic.attachment img')),
      '图文卡': grab(document.querySelector('.itc-img-wrap img')),
      '图文行': grab(document.querySelector('.itr-img img')),
      'MD行内(data)': grab(md[0]),
      'MD行内(http)': grab(md[1]),
    };
  });
}
let newGeoms = null;
{
  const { ctx, page } = await importAndOpen(newBase, 'D22混合');
  // 等全部图载入（滚动一遍确保 lazy 触发）
  await page.evaluate(async () => {
    const H = document.documentElement.scrollHeight;
    for (let y = 0; y <= H; y += 500) {
      window.scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 200));
    }
    window.scrollTo(0, 0);
  });
  await page.waitForFunction(
    () => [...document.querySelectorAll('.editor-body img')].every((i) => i.naturalWidth > 0),
    null, { polling: 250, timeout: 20000 }).catch(() => console.log('  [new] 混合备忘有图未载入（继续量测）'));
  await page.waitForTimeout(400);
  newGeoms = await siteGeoms(page);
  console.log('  [new] 混合几何:', JSON.stringify(newGeoms, null, 1));
  const bgs = new Set(Object.values(newGeoms).filter(Boolean).map((g) => g.bg));
  ok('④ 各呈现点占位背景逐项一致（fill-subtle 令牌）',
    bgs.size === 1 && bgs.has('rgba(0, 0, 0, 0.03)'), JSON.stringify([...bgs]));
  await ctx.close();
}

// ── ⑤④ 新构建：URL 缓存首访/再访（挂起响应量占位）──
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'light' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
  let release;
  let gate = new Promise((r) => { release = r; });
  await page.route('**/wide.png', async (route) => { await gate; await route.continue(); });
  // 首访：走导入流程（新上下文）
  await page.goto(newBase, { waitUntil: 'load' });
  await page.waitForSelector('h1.page-title', { timeout: 15000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/tmp/d22_probe.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { polling: 200, timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes('D22混合'));
    if (el) el.click();
  });
  await page.waitForSelector('.detail', { timeout: 8000 });
  await page.waitForTimeout(700);
  const urlGeom = () => page.evaluate(() => {
    const imgs = document.querySelectorAll('.atomic[data-type="image"] > img');
    const el = imgs[1];
    if (!el) return null;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return { w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10, bg: cs.backgroundColor, radius: cs.borderTopLeftRadius, nat: el.naturalWidth };
  });
  const first = await urlGeom();
  console.log('  [new] URL 图首访挂起态:', JSON.stringify(first));
  console.log('  [new] （首访无预留属预期，盒高应 ≈0）');
  release();
  await page.waitForFunction(() => {
    const imgs = document.querySelectorAll('.atomic[data-type="image"] > img');
    return imgs[1] && imgs[1].naturalWidth > 0;
  }, null, { polling: 200, timeout: 15000 });
  await page.waitForTimeout(300);
  const cacheRaw = await page.evaluate(() => localStorage.getItem('mynote_imgsize_v1') || '');
  let cacheHit = false;
  try {
    const m = JSON.parse(cacheRaw);
    cacheHit = Array.isArray(m['http://localhost:8120/wide.png'])
      && m['http://localhost:8120/wide.png'][0] === 1600
      && m['http://localhost:8120/wide.png'][1] === 400;
  } catch (e) { /* 解析失败即未命中 */ }
  ok('⑤ URL 尺寸已回填 localStorage 缓存', cacheHit, cacheRaw.slice(0, 200));
  const loaded = await urlGeom();
  // 再访：整页重载后重开（缓存仍在），响应再次挂起
  gate = new Promise((r) => { release = r; });
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 15000 });
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes('D22混合'));
    if (el) el.click();
  });
  await page.waitForSelector('.detail', { timeout: 8000 });
  await page.waitForTimeout(700);
  const reserved = await urlGeom();
  console.log('  [new] URL 图再访挂起态（应已预留）:', JSON.stringify(reserved), '载入态:', JSON.stringify(loaded));
  ok('④ 再访占位盒几何 == 载入后几何（±1）',
    reserved && loaded && Math.abs(reserved.w - loaded.w) <= 1 && Math.abs(reserved.h - loaded.h) <= 1,
    `reserved=${JSON.stringify(reserved)} loaded=${JSON.stringify(loaded)}`);
  ok('④ 再访占位背景/圆角与载入态同值',
    reserved && loaded && reserved.bg === loaded.bg && reserved.radius === loaded.radius,
    `reserved bg=${reserved?.bg} radius=${reserved?.radius} / loaded bg=${loaded?.bg} radius=${loaded?.radius}`);
  release();
  await ctx.close();
}

// ── ③ 基线构建：混合几何对照 + 长文档解码对照 ──
{
  const { ctx, page } = await importAndOpen(baseBase, 'D22混合');
  await page.evaluate(async () => {
    const H = document.documentElement.scrollHeight;
    for (let y = 0; y <= H; y += 500) {
      window.scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 200));
    }
    window.scrollTo(0, 0);
  });
  await page.waitForFunction(
    () => [...document.querySelectorAll('.editor-body img')].every((i) => i.naturalWidth > 0),
    null, { polling: 250, timeout: 20000 }).catch(() => console.log('  [base] 混合备忘有图未载入（继续量测）'));
  await page.waitForTimeout(400);
  const baseGeoms = await siteGeoms(page);
  console.log('  [base] 混合几何:', JSON.stringify(baseGeoms, null, 1));
  for (const [name] of SITES) {
    const n = newGeoms?.[name];
    const b = baseGeoms?.[name];
    ok(`③ 载入后几何一致：${name}`,
      !!n && !!b && Math.abs(n.w - b.w) <= 1 && Math.abs(n.h - b.h) <= 1,
      `new=${JSON.stringify(n)} base=${JSON.stringify(b)}`);
  }
  await ctx.close();
}
{
  const { ctx, page } = await importAndOpen(baseBase, 'D22长文档');
  await page.waitForTimeout(300);
  const dec0 = await decodedCount(page);
  console.log(`  [base] 长文档 T+300ms 已解码=${dec0}（对照基线）`);
  ok('① 基线长文档开页解码 20/20（对照成立）', dec0 === 20, `decoded=${dec0}`);
  await ctx.close();
}

await browser.close();
fxServer.close();
console.log(fail === 0 ? `ALL PASS (${pass})` : `FAILURES: ${fail} (pass ${pass})`);
process.exit(fail === 0 ? 0 : 1);
