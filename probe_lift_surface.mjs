// 探针（Rust）：长按拾起「视觉面动态适配」验收（拾起重构，
// 用户口径 supersede 卡片交互专项的盒级等距内收）——拾起框
// 由块的真实视觉面动态生成：框 = 视觉面渲染矩形四边外扩
// LIFT_INSET(4px)、框半径 = 视觉面半径 + 4（同心嵌套）。
// 逐块型断言：① 框↔视觉面四边间隙 ∈[3,5] 且两两差 ≤1px
// ② 四角框半径 − 视觉面渲染半径 − 4 ≤1px ③ 偏心抓握点在
// 视觉面内局部比例不漂移 ④ 浮块跟指（视觉面中心）误差
// ≤2px ⑤ 占位文案状态感知：非编辑态为长按菜单引导文案、
// 编辑态回「点击添加图片」（图文卡/图片块/画廊空态）。
// 视觉面解析在探针侧独立复刻桥的通用规则（标记复合面
// [data-liftsurface] 并集 → 最大有面元素（排除应用铬件）
// → 单元自身），与桥实现互为校验。Chromium 口径。
// 视频块：无头 Chromium 原生媒体控件吞按压（事件不达
// DOM，A/B 实证为环境限制），量测前临时摘 controls 让
// 按压到达按压机，几何同路校验（见几何循环处注）。
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';
const url = process.argv[2] || 'http://localhost:8216/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const D = 4;
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

// ---------- 夹具（全块型 + 真实附件） ----------
execSync(`python3 - <<'PYEOF'
import json, zipfile, datetime, zlib, struct
def png(w, h, rgb):
    def chunk(typ, data):
        c = struct.pack('>I', len(data)) + typ + data
        c += struct.pack('>I', zlib.crc32(typ + data) & 0xffffffff)
        return c
    raw = b''
    row = bytes(rgb) * w
    for _ in range(h):
        raw += b'\\x00' + row
    return (b'\\x89PNG\\r\\n\\x1a\\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
now = datetime.datetime.now().astimezone(); ts = now.isoformat()
def para(bid, text): return {"id": bid, "type": "paragraph", "children": [{"text": text}]}
def typed(bid, ty, text, toptext=None, **extra):
    b = {"id": bid, "type": ty, "children": [{"text": text}]}
    if toptext is not None: b["text"] = toptext
    b.update(extra); return b
doc = [
    para("lm-para", "普通段落文本，用于量测文本块拾起几何。"),
    typed("lm-head", "heading", "二级标题文本", attrs={"level": 2}),
    typed("lm-todo", "todo", "待办事项文本", attrs={"checked": False}),
    typed("lm-quote", "quote", "引用文本内容，量测引用块。"),
    para("lm-list", "- 列表甲\\n- 列表乙\\n- 列表丙"),
    para("lm-md", "\`\`\`rust\\nlet x = 1;\\nlet y = 2;\\n\`\`\`"),
    para("lm-callout", "> [!NOTE]\\n> 标注正文内容，量测 Callout。"),
    typed("lm-img", "image", "", attrs={"fileId": "lmimg1"}),
    typed("lm-img0", "image", ""),
    typed("lm-gal", "gallery", "", attrs={"items": ["lmimg1", "lmimg2"]}),
    typed("lm-gal0", "gallery", "", attrs={"items": []}),
    typed("lm-itc", "imgTextCard", "", attrs={"fileId": "lmimg1"}, toptext="图文卡说明文字"),
    typed("lm-itc0", "imgTextCard", "", toptext="空图文卡说明文字"),
    typed("lm-itr", "imageTextRow", "", attrs={"fileId": "lmimg2"}, toptext="左图右字说明"),
    typed("lm-itr0", "imageTextRow", "", toptext="左图右字空说明"),
    typed("lm-mus", "musicCard", "", url="https://music.163.com/song?id=1", status="ready",
          meta={"title": "测试歌曲名", "cover": ""}),
    typed("lm-lnk", "link-card", "", url="https://example.com/article", status="ready",
          meta={"title": "示例文章标题", "description": "链接卡描述文字。", "siteName": "example.com", "image": ""}),
    typed("lm-lnk0", "link-card", "", url="https://example.org/page"),
    typed("lm-att", "attachment", "", attrs={"fileId": "lmpdf"}),
    typed("lm-atti", "attachment", "", attrs={"fileId": "lmimg2"}, image=True),
    typed("lm-vid", "video", "", url="https://example.com/movie.mp4"),
    typed("lm-div", "divider", ""),
]
memo = {"id": "lm01", "title": "拾起量测", "pinned": False, "createdAt": ts, "updatedAt": ts, "doc": doc}
data = {"version": 2, "exportedAt": ts, "memos": [memo], "avatars": {}}
man = {"version": 1, "attachments": {
    "lmimg1": {"name": "图一.png", "type": "image/png"},
    "lmimg2": {"name": "图二.png", "type": "image/png"},
    "lmpdf": {"name": "报告.pdf", "type": "application/pdf"}}}
z = zipfile.ZipFile('/tmp/lift_surface_fixture.zip', 'w')
z.writestr('memos.json', json.dumps(data, ensure_ascii=False))
z.writestr('manifest.json', json.dumps(man, ensure_ascii=False))
z.writestr('attachments/lmimg1', png(800, 500, (70, 120, 200)))
z.writestr('attachments/lmimg2', png(600, 600, (200, 120, 70)))
z.writestr('attachments/lmpdf', b'%PDF-1.4 fake fixture')
z.close()
print('lift_surface_fixture.zip ready')
PYEOF`);

async function importZip(page, zip) {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.waitForTimeout(400);
}
async function openMemo(page, title) {
  const pt = await page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt);
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, title);
  if (!pt) throw new Error('card not found: ' + title);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1500);
}

// 页内工具（字符串注入，各 evaluate 自带）
const HELPERS = `
window.__findUnit = (bid) => {
  const body = document.querySelector('.editor-body');
  const units = [];
  const walk = (parent) => {
    for (const child of parent.children) {
      if (child.classList && child.classList.contains('editor-column')) { walk(child); continue; }
      units.push(child);
    }
  };
  walk(body);
  return units.find((u) => {
    const multi = u.getAttribute('data-bids');
    if (multi) return multi.split(',').includes(bid);
    const own = u.getAttribute('data-bid') || u.getAttribute('data-wrapbid');
    if (own) return own === bid;
    return u.querySelector('[data-bid]')?.getAttribute('data-bid') === bid;
  }) || null;
};
window.__cornersPx = (el) => {
  const cs = getComputedStyle(el);
  const parse = (v) => {
    const t = (v || '0px').trim().split(/\\s+/);
    return [parseFloat(t[0]) || 0, parseFloat(t.length > 1 ? t[1] : t[0]) || 0];
  };
  return [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map(parse);
};
window.__surfResolve = (unit) => {
  const R = (el) => { const r = el.getBoundingClientRect();
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height }; };
  const marked = unit.querySelectorAll('[data-liftsurface]');
  if (marked.length) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    marked.forEach((el) => { const r = R(el);
      x0 = Math.min(x0, r.left); y0 = Math.min(y0, r.top);
      x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom); });
    return { rect: { left: x0, top: y0, right: x1, bottom: y1, width: x1 - x0, height: y1 - y0 },
             corners: window.__cornersPx(marked[0]), via: 'marked' };
  }
  const ur = unit.getBoundingClientRect();
  const uArea = ur.width * ur.height;
  let best = null, bestArea = 0;
  const consider = (el) => {
    if (el.closest('.blk-more, .card-menu-panel')) return;
    const cs = getComputedStyle(el);
    if (cs.display === 'inline') return;
    const bg = cs.backgroundColor;
    const bf = (cs.backdropFilter || cs.getPropertyValue('-webkit-backdrop-filter') || '').trim();
    const hasFace = (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent')
      || (bf !== '' && bf !== 'none') || el.tagName === 'IMG' || el.tagName === 'VIDEO';
    if (!hasFace) return;
    const corners = [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius];
    if (!corners.some((c) => (c || '').split(/\\s+/).some((t) => parseFloat(t) > 0))) return;
    const r = el.getBoundingClientRect();
    const area = r.width * r.height;
    if (area < uArea * 0.15 || area <= bestArea) return;
    bestArea = area; best = el;
  };
  consider(unit);
  unit.querySelectorAll('*').forEach(consider);
  if (best) return { rect: R(best), corners: window.__cornersPx(best), via: 'heuristic' };
  return { rect: R(unit), corners: window.__cornersPx(unit), via: 'unit' };
};
window.__frameRect = (unit) => {
  const cs = getComputedStyle(unit, '::before');
  // ::before 定位相对内边距盒，须加回边框宽换算到边框盒
  // 坐标（.blk-quote 左边框 3px/上 1px，无此修正时框位
  // 系统性偏移 clientLeft×k——lm-quote 实测定位）。
  const fl = parseFloat(cs.left) + (unit.clientLeft || 0), ft = parseFloat(cs.top) + (unit.clientTop || 0);
  const fw = parseFloat(cs.width), fh = parseFloat(cs.height);
  if ([fl, ft, fw, fh].some((v) => Number.isNaN(v))) return null;
  const W = unit.offsetWidth, H = unit.offsetHeight;
  if (!W || !H) return null;
  const r = unit.getBoundingClientRect();
  const kx = r.width / W, ky = r.height / H;
  const parse = (v) => {
    const t = (v || '0px').trim().split(/\\s+/);
    return [(parseFloat(t[0]) || 0) * kx, (parseFloat(t.length > 1 ? t[1] : t[0]) || 0) * ky];
  };
  return {
    left: r.left + fl * kx, top: r.top + ft * ky,
    right: r.left + (fl + fw) * kx, bottom: r.top + (ft + fh) * ky,
    radii: [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map(parse),
    kx, ky,
  };
};
`;

const BLOCKS = ['lm-para', 'lm-head', 'lm-todo', 'lm-quote', 'lm-list', 'lm-md', 'lm-callout',
  'lm-img', 'lm-img0', 'lm-gal', 'lm-gal0', 'lm-itc', 'lm-itc0', 'lm-itr', 'lm-itr0',
  'lm-mus', 'lm-lnk', 'lm-lnk0', 'lm-att', 'lm-atti', 'lm-vid', 'lm-div'];

async function measureBlock(page, bid, grabFrac = null) {
  return page.evaluate(([b, gf]) => {
    const u = window.__findUnit(b);
    if (!u) return null;
    u.scrollIntoView({ block: 'center' });
    const pre = window.__surfResolve(u);
    const cx = gf ? pre.rect.left + pre.rect.width * gf[0] : pre.rect.left + pre.rect.width / 2;
    const cy = gf ? pre.rect.top + pre.rect.height * gf[1] : pre.rect.top + pre.rect.height / 2;
    return { pre, cx, cy };
  }, [bid, grabFrac]);
}
async function measureLifted(page, bid) {
  return page.evaluate((b) => {
    const u = window.__findUnit(b);
    if (!u || !u.classList.contains('mn-lifted')) return null;
    const post = window.__surfResolve(u);
    const frame = window.__frameRect(u);
    return { post, frame };
  }, bid);
}
function checkGeom(bid, pre, post, frame) {
  if (!post || !frame) { ok(`${bid} 拾起框可量`, false, 'no frame'); return; }
  const s = post.rect, f = frame;
  const gaps = [s.left - f.left, f.right - s.right, s.top - f.top, f.bottom - s.bottom];
  const spread = Math.max(...gaps) - Math.min(...gaps);
  ok(`${bid} 框↔视觉面四边间隙 = ${D}px（两两差 ≤1）`,
    gaps.every((g) => g >= D - 1 && g <= D + 1) && spread <= 1,
    `gaps=${gaps.map((g) => g.toFixed(2)).join('/')} via=${post.via} surf=${s.width.toFixed(0)}x${s.height.toFixed(0)}`);
  let radOk = true, radInfo = [];
  for (let i = 0; i < 4; i++) {
    const expX = post.corners[i][0] * frame.kx + D;
    const expY = post.corners[i][1] * frame.ky + D;
    const dx = Math.abs(frame.radii[i][0] - expX), dy = Math.abs(frame.radii[i][1] - expY);
    radInfo.push(`${dx.toFixed(1)}/${dy.toFixed(1)}`);
    if (dx > 1 || dy > 1) radOk = false;
  }
  ok(`${bid} 框半径 = 视觉面半径 + ${D}（同心，四角 ≤1px）`, radOk, 'Δ=' + radInfo.join(' '));
}

// ---------- 移动端 ----------
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
await importZip(page, '/tmp/lift_surface_fixture.zip');
await openMemo(page, '拾起量测');
await page.evaluate(HELPERS);
const cdp = await ctx.newCDPSession(page);
const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }],
});
const phText = (bid, sel) => page.evaluate(([b, s]) => {
  const u = window.__findUnit(b);
  const el = u ? u.querySelector(s) : null;
  return el ? el.textContent.trim() : null;
}, [bid, sel]);

// ⑤ 文案（非编辑态 = 引导文案）
const itc0Ph = await phText('lm-itc0', '.itc-placeholder');
ok('⑤ 图文卡空占位（非编辑态）= 长按菜单引导文案',
  !!itc0Ph && itc0Ph.includes('长按') && itc0Ph.includes('编辑') && !itc0Ph.includes('点击添加图片'), JSON.stringify(itc0Ph));
const img0Ph = await phText('lm-img0', '.atomic-placeholder');
ok('⑤ 图片块空占位（非编辑态）= 长按菜单引导文案',
  !!img0Ph && img0Ph.includes('长按') && img0Ph.includes('编辑') && !img0Ph.includes('点击添加图片'), JSON.stringify(img0Ph));
const gal0L = await phText('lm-gal0', '.gallery-empty-tile .gallery-empty-label');
ok('⑤ 画廊空态左格（非编辑态）= 长按编辑引导文案',
  !!gal0L && gal0L.includes('长按') && !gal0L.includes('点击'), JSON.stringify(gal0L));
const gal0R = await page.evaluate(() => {
  const u = window.__findUnit('lm-gal0');
  const els = u ? u.querySelectorAll('.gallery-empty-tile .gallery-empty-label') : [];
  return els.length > 1 ? els[1].textContent.trim() : null;
});
ok('⑤ 画廊空态右格仍为「多张图片」（描述文案不分态）', gal0R === '多张图片', JSON.stringify(gal0R));

// ①② 逐块型几何（触屏长按，抓视觉面中心）
// 视频块特例：无头 Chromium 的原生媒体控件会吞掉落在
// <video controls> 上的按压（触屏/鼠标同，事件不达
// DOM——A/B 实证：同元素 controls=false 时按压直达、
// 拾起与菜单皆正常，属测试环境限制非应用缺陷）。故量
// 测前临时摘除其 controls 属性，只为让按压到达应用按
// 压机；拾起几何机制与他块完全同路。
for (const bid of BLOCKS) {
  if (bid === 'lm-vid') {
    await page.evaluate(() => {
      const v = document.querySelector('[data-wrapbid="lm-vid"] video');
      if (v) v.controls = false;
    });
  }
  const m = await measureBlock(page, bid);
  if (!m) { ok(`${bid} 单元存在`, false); continue; }
  await page.waitForTimeout(420);
  const m2 = await measureBlock(page, bid);
  let lifted = false;
  for (let attempt = 0; attempt < 2 && !lifted; attempt++) {
    await touch('touchStart', m2.cx, m2.cy);
    await page.waitForTimeout(720);
    lifted = await page.evaluate((b) => {
      const u = window.__findUnit(b);
      return !!u && u.classList.contains('mn-lifted');
    }, bid);
    if (!lifted) { await touch('touchEnd', m2.cx, m2.cy); await page.waitForTimeout(400); }
  }
  if (!lifted) { ok(`${bid} 长按拾起`, false); await page.keyboard.press('Escape').catch(() => {}); continue; }
  await page.waitForTimeout(550);
  const post = await measureLifted(page, bid);
  checkGeom(bid, m2.pre, post ? post.post : null, post ? post.frame : null);
  await touch('touchCancel', m2.cx, m2.cy);
  await page.waitForTimeout(650);
  await page.keyboard.press('Escape').catch(() => {});
  await page.waitForTimeout(150);
}

// ③ 偏心抓握（30%/35%）——空图片块、画廊、图文卡
for (const bid of ['lm-img0', 'lm-gal', 'lm-itc']) {
  const m = await measureBlock(page, bid, [0.3, 0.35]);
  if (!m) { ok(`${bid} 偏心抓握前置`, false); continue; }
  await page.waitForTimeout(420);
  const m2 = await measureBlock(page, bid, [0.3, 0.35]);
  await touch('touchStart', m2.cx, m2.cy);
  await page.waitForTimeout(720 + 550);
  const post = await measureLifted(page, bid);
  if (!post) { ok(`${bid} 偏心抓握拾起`, false); }
  else {
    const s = post.post.rect;
    const fx = (m2.cx - s.left) / s.width, fy = (m2.cy - s.top) / s.height;
    ok(`${bid} 偏心抓握点视觉面内比例不漂移`,
      Math.abs(fx - 0.3) <= 0.02 && Math.abs(fy - 0.35) <= 0.02,
      `frac=${fx.toFixed(3)},${fy.toFixed(3)} exp=0.300,0.350`);
    checkGeom(bid + '(偏心)', m2.pre, post.post, post.frame);
  }
  await touch('touchCancel', m2.cx, m2.cy);
  await page.waitForTimeout(650);
  await page.keyboard.press('Escape').catch(() => {});
  await page.waitForTimeout(150);
}

// ④ 跟指：图片块拾起后移动 5 点，视觉面中心误差 ≤2px
{
  const m = await measureBlock(page, 'lm-img');
  await page.waitForTimeout(420);
  const m2 = await measureBlock(page, 'lm-img');
  await touch('touchStart', m2.cx, m2.cy);
  await page.waitForTimeout(720);
  let followMax = 0;
  const c0 = { x: m2.pre.rect.left + m2.pre.rect.width / 2, y: m2.pre.rect.top + m2.pre.rect.height / 2 };
  for (let i = 1; i <= 5; i++) {
    const px = m2.cx + i * 8, py = m2.cy + i * 14;
    await touch('touchMove', px, py);
    await page.waitForTimeout(170);
    const post = await measureLifted(page, 'lm-img');
    if (!post) { followMax = 99; break; }
    const s = post.post.rect;
    followMax = Math.max(followMax,
      Math.abs(s.left + s.width / 2 - (c0.x + (px - m2.cx))),
      Math.abs(s.top + s.height / 2 - (c0.y + (py - m2.cy))));
  }
  ok('④ 图片块浮块跟指误差 ≤2px（视觉面中心，5 点）', followMax <= 2, 'max=' + followMax.toFixed(2));
  await touch('touchCancel', m2.cx, m2.cy);
  await page.waitForTimeout(650);
}

// ⑤ 文案（编辑态 = 点击添加图片）：经菜单「编辑」入态
async function menuEdit(bid) {
  const m = await measureBlock(page, bid);
  await page.waitForTimeout(420);
  const m2 = await measureBlock(page, bid);
  await touch('touchStart', m2.cx, m2.cy);
  await page.waitForTimeout(720);
  await touch('touchEnd', m2.cx, m2.cy);
  await page.waitForTimeout(400);
  const clicked = await page.evaluate(() => {
    const b = [...document.querySelectorAll('.card-menu-panel .menu-item')]
      .find((x) => !x.classList.contains('danger'));
    if (b) { b.click(); return true; }
    return false;
  });
  await page.waitForTimeout(500);
  return clicked;
}
const wrapHas = (bid, cls) => page.evaluate(([b, c]) => {
  const u = window.__findUnit(b);
  return !!u && u.classList.contains(c);
}, [bid, cls]);

ok('⑤ 菜单编辑可入态（图文卡）', await menuEdit('lm-itc0'));
ok('⑤ 图文卡进入编辑态（card-editing）', await wrapHas('lm-itc0', 'card-editing'));
const itc0Edit = await phText('lm-itc0', '.itc-placeholder');
ok('⑤ 图文卡空占位（编辑态）= 点击添加图片',
  !!itc0Edit && itc0Edit.includes('点击添加图片') && !itc0Edit.includes('长按'), JSON.stringify(itc0Edit));
// 点卡外（段落）退出 → 文案复原
{
  const m = await measureBlock(page, 'lm-para');
  await touch('touchStart', m.cx, m.cy);
  await touch('touchEnd', m.cx, m.cy);
  await page.waitForTimeout(500);
}
ok('⑤ 点卡外退出编辑态', !(await wrapHas('lm-itc0', 'card-editing')));
const itc0Back = await phText('lm-itc0', '.itc-placeholder');
ok('⑤ 退出后图文卡占位复原引导文案', !!itc0Back && itc0Back.includes('长按'), JSON.stringify(itc0Back));

ok('⑤ 菜单编辑可入态（图片块）', await menuEdit('lm-img0'));
const img0Edit = await phText('lm-img0', '.atomic-placeholder');
ok('⑤ 图片块空占位（编辑态）= 点击添加图片',
  !!img0Edit && img0Edit.includes('点击添加图片') && !img0Edit.includes('长按'), JSON.stringify(img0Edit));
await page.keyboard.press('Escape').catch(() => {});
await page.waitForTimeout(300);

ok('⑤ 菜单编辑可入态（画廊）', await menuEdit('lm-gal0'));
const gal0Edit = await phText('lm-gal0', '.gallery-empty-tile .gallery-empty-label');
ok('⑤ 画廊空态左格（编辑态）= 点击添加',
  !!gal0Edit && gal0Edit.includes('点击添加') && !gal0Edit.includes('长按'), JSON.stringify(gal0Edit));
await page.keyboard.press('Escape').catch(() => {});
await page.waitForTimeout(300);
await ctx.close();

// ---------- 桌面端（子集：右键菜单不测，几何走鼠标拾起） ----------
const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const p2 = await ctx2.newPage();
p2.on('pageerror', (e) => console.log('PAGEERROR(d)', String(e).slice(0, 200)));
await importZip(p2, '/tmp/lift_surface_fixture.zip');
await openMemo(p2, '拾起量测');
await p2.evaluate(HELPERS);
for (const [bid, kind] of [['lm-gal', 'atomic'], ['lm-img0', 'atomic'], ['lm-itc', 'atomic'], ['lm-para', 'text']]) {
  const m = await p2.evaluate((b) => {
    const u = window.__findUnit(b);
    if (!u) return null;
    u.scrollIntoView({ block: 'center' });
    const pre = window.__surfResolve(u);
    return { pre, cx: pre.rect.left + pre.rect.width / 2, cy: pre.rect.top + pre.rect.height / 2 };
  }, bid);
  if (!m) { ok(`${bid} 桌面单元存在`, false); continue; }
  await p2.waitForTimeout(420);
  const m2 = await p2.evaluate((b) => {
    const u = window.__findUnit(b);
    if (!u) return null;
    const pre = window.__surfResolve(u);
    return { pre, cx: pre.rect.left + pre.rect.width / 2, cy: pre.rect.top + pre.rect.height / 2 };
  }, bid);
  await p2.mouse.move(m2.cx, m2.cy);
  await p2.mouse.down();
  if (kind === 'atomic') {
    // 原子块：移动 ≥6px 拾起
    await p2.mouse.move(m2.cx + 12, m2.cy + 12, { steps: 3 });
    await p2.waitForTimeout(500);
  } else {
    // 文本块：静止 hold 280ms 拾起（移动会转拖选、压机作废）
    await p2.waitForTimeout(560);
  }
  await p2.waitForTimeout(350);
  const post = await p2.evaluate((b) => {
    const u = window.__findUnit(b);
    if (!u || !u.classList.contains('mn-lifted')) return null;
    return { post: window.__surfResolve(u), frame: window.__frameRect(u) };
  }, bid);
  if (!post) ok(`${bid} 桌面拾起`, false);
  else checkGeom(bid + '(桌面)', m2.pre, post.post, post.frame);
  await p2.mouse.up();
  await p2.waitForTimeout(900);
  await p2.keyboard.press('Escape').catch(() => {});
  await p2.waitForTimeout(200);
}
await ctx2.close();

await browser.close();
L(fails === 0 ? 'LIFT SURFACE ALL PASS' : `LIFT SURFACE ${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
