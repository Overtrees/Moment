// 导出顶栏量测探针（导出顶栏复刻线）：
// 应用内编辑页顶栏 vs 导出 HTML 渲染（screen/print）vs PDF 捕获文档
// vs 原版兜底页眉规格，浅/深 × 头像两态（恐龙/图片）逐元素对照。
// 用法：node probe_export_topbar.mjs [rustBase] [origBase] [outJson]
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const base = process.argv[2] || 'http://localhost:8199/';
const origBase = process.argv[3] || 'http://localhost:8097/';
const outPath = process.argv[4] || '/tmp/topbar_measure.json';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const COMMON_PROPS = ['background-color', 'border-radius', 'border-top-width', 'border-top-color', 'border-top-style', 'backdrop-filter', '-webkit-backdrop-filter', 'color', 'box-shadow'];

const MEASURE_FN = (COMMON) => {
  const q = (s, r) => (r || document).querySelector(s);
  const rect = (el) => { if (!el) return null; const r = el.getBoundingClientRect(); return { x: Math.round(r.x * 10) / 10, y: Math.round(r.y * 10) / 10, w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10 }; };
  const cs = (el, props) => { if (!el) return null; const s = getComputedStyle(el); const o = {}; for (const p of props) o[p] = s.getPropertyValue(p); return o; };
  const header = q('.mynote-export-header');
  const scope = header || document;
  const back = q('.editor-fab.left', scope) || q('.mynote-export-back', scope);
  const more = q('.editor-fab.right', scope) || q('.mynote-export-more', scope);
  const dock = q('.editor-title-dock', scope);
  const avatarBtn = q('.editor-avatar-button', scope) || q('.mynote-export-avatar', scope);
  const avatarImg = avatarBtn ? avatarBtn.querySelector('img') : null;
  const dinoSvg = avatarBtn ? avatarBtn.querySelector('svg') : null;
  const capsule = q('.editor-title-capsule', scope) || q('.mynote-export-title-pill', scope);
  const titleEl = q('#editor-title-text', scope) || q('.editor-title-input', scope) || q('.note-title', scope);
  const meta = q('.editor-title-meta', scope) || q('.mynote-export-meta', scope);
  const backSvg = back ? back.querySelector('svg') : null;
  const moreSvg = more ? more.querySelector('svg') : null;
  const rootStyle = document.documentElement.getAttribute('style') || '';
  const pinned = {};
  for (const n of ['--glass-control-bg', '--glass-control-border', '--glass-control-filter', '--text-main', '--text-secondary', '--color-icon-muted']) {
    pinned[n] = rootStyle.includes(n);
  }
  const computedVars = {};
  const rs = getComputedStyle(document.documentElement);
  for (const n of Object.keys(pinned)) computedVars[n] = rs.getPropertyValue(n).trim();
  return {
    path: header ? (dock ? 'chrome' : 'fallback') : 'app',
    headerRect: rect(header),
    htmlTheme: document.documentElement.getAttribute('data-export-theme'),
    colorScheme: rs.colorScheme,
    pinned,
    computedVars,
    bodyBg: getComputedStyle(document.body).backgroundColor,
    back: back ? { rect: rect(back), cs: cs(back, COMMON), cls: back.className,
      svg: backSvg ? { w: backSvg.getAttribute('width'), h: backSvg.getAttribute('height'), sw: backSvg.getAttribute('stroke-width'), pts: backSvg.querySelector('polyline') ? backSvg.querySelector('polyline').getAttribute('points') : null, rect: rect(backSvg) } : null } : null,
    more: more ? { rect: rect(more), cs: cs(more, COMMON), cls: more.className,
      svg: moreSvg ? { w: moreSvg.getAttribute('width'), h: moreSvg.getAttribute('height'), fill: moreSvg.getAttribute('fill'), circles: [...moreSvg.querySelectorAll('circle')].map(c => [c.getAttribute('cx'), c.getAttribute('cy'), c.getAttribute('r')]), rect: rect(moreSvg) } : null } : null,
    dock: dock ? { rect: rect(dock), cls: dock.className, cs: cs(dock, ['flex-direction', 'gap', 'align-items']) } : null,
    avatarBtn: avatarBtn ? { rect: rect(avatarBtn), cs: cs(avatarBtn, COMMON), cls: avatarBtn.className, tag: avatarBtn.tagName } : null,
    avatarImg: avatarImg ? { rect: rect(avatarImg), srcKind: (avatarImg.getAttribute('src') || '').slice(0, 40), complete: avatarImg.complete, natural: [avatarImg.naturalWidth, avatarImg.naturalHeight] } : null,
    dino: dinoSvg ? { rect: rect(dinoSvg), strokeAttr: dinoSvg.getAttribute('stroke'), sw: dinoSvg.getAttribute('stroke-width'), styleAttr: dinoSvg.getAttribute('style'), computedStroke: getComputedStyle(dinoSvg).stroke, w: dinoSvg.getAttribute('width'), h: dinoSvg.getAttribute('height') } : null,
    capsule: capsule ? { rect: rect(capsule), cs: cs(capsule, [...COMMON, 'padding-left', 'padding-right']), cls: capsule.className } : null,
    title: titleEl ? { text: titleEl.textContent, titleAttr: titleEl.getAttribute('title'), cs: cs(titleEl, ['font-size', 'font-weight', 'letter-spacing', 'color', 'line-height', 'text-align']), rect: rect(titleEl), cls: titleEl.className } : null,
    meta: meta ? { text: meta.textContent, cs: cs(meta, ['font-size', 'color', 'display', 'line-height']), rect: rect(meta) } : null,
  };
};

async function importAndOpen(page, zipPath) {
  const buf = fs.readFileSync(zipPath);
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'mix.zip', mimeType: 'application/zip', buffer: buf });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=mixfix1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(1200);
}

const INIT = () => {
  window.__exportHtml = null;
  window.__seq = [];
  window.__blobs = [];
  const oc = URL.createObjectURL.bind(URL);
  URL.createObjectURL = (b) => { try { window.__blobs.push(b); } catch (e) {} return oc(b); };
  window.open = () => {
    window.__seq.push('open');
    return {
      closed: false,
      focus() {},
      print() { window.__seq.push('print'); },
      document: {
        open() { window.__seq.push('doc.open'); },
        write(s) { window.__seq.push('write'); window.__exportHtml = s; },
        close() { window.__seq.push('doc.close'); },
        images: [],
      },
    };
  };
};

async function doExport(page, format) {
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(400);
  await page.click(`[data-export-format="${format}"]`);
  await page.waitForTimeout(2000);
}

function headerSlice(html) {
  if (!html) return null;
  const m = html.match(/<header[\s\S]*?<\/header>/);
  return m ? m[0] : null;
}

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const results = {};

for (const scheme of ['light', 'dark']) {
  for (const av of ['dino', 'img']) {
    const label = `${scheme}/${av}`;
    const zipPath = av === 'img' ? '/tmp/mix-avatar.zip' : process.env.HOME + '/workspace/Mynote/fixtures/mix-layout.zip';
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: scheme, acceptDownloads: true });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => console.log(`[${label}] pageerror:`, String(e).slice(0, 200)));
    await page.addInitScript(INIT);
    await importAndOpen(page, zipPath);
    const app = await page.evaluate(MEASURE_FN, COMMON_PROPS);
    await doExport(page, 'html');
    const htmlStr = await page.evaluate(async () => {
      const b = window.__blobs[window.__blobs.length - 1];
      return b ? await b.text() : null;
    });
    await doExport(page, 'pdf');
    const pdfStr = await page.evaluate(() => window.__exportHtml);
    const entry = { app, htmlLen: htmlStr ? htmlStr.length : 0, pdfLen: pdfStr ? pdfStr.length : 0,
      headerSameHtmlPdf: headerSlice(htmlStr) === headerSlice(pdfStr) && !!headerSlice(htmlStr),
      htmlHeader: headerSlice(htmlStr) ? headerSlice(htmlStr).slice(0, 400) : null };
    // render exported html doc: screen 1280, print 1280, screen 393
    const p2 = await ctx.newPage();
    await p2.setContent(htmlStr, { waitUntil: 'load' });
    await p2.waitForTimeout(400);
    entry.expScreen = await p2.evaluate(MEASURE_FN, COMMON_PROPS);
    await p2.emulateMedia({ media: 'print' });
    await p2.waitForTimeout(200);
    entry.expPrint = await p2.evaluate(MEASURE_FN, COMMON_PROPS);
    await p2.emulateMedia({ media: 'screen' });
    await p2.setViewportSize({ width: 393, height: 852 });
    await p2.waitForTimeout(300);
    entry.expScreen393 = await p2.evaluate(MEASURE_FN, COMMON_PROPS);
    await p2.close();
    results[label] = entry;
    console.log(`[${label}] done: app.path=${app.path} exp.path=${entry.expScreen.path} headerSame=${entry.headerSameHtmlPdf} htmlLen=${entry.htmlLen}`);
    await ctx.close();
  }
}

// ---------- 原版兜底页眉规格（toHTMLDocument 无 chrome 快照路径） ----------
for (const scheme of ['light', 'dark']) {
  for (const av of ['dino', 'img']) {
    const label = `orig-fallback/${scheme}/${av}`;
    try {
      const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: scheme });
      const opage = await ctx.newPage();
      await opage.goto(origBase + 'Moment.html', { waitUntil: 'load', timeout: 20000 });
      await opage.waitForFunction(() => !!window.MynoteEditorExport, null, { timeout: 12000 });
      const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      const origHtml = await opage.evaluate(({ scheme, av, PNG }) => {
        const vars = {};
        const rs = getComputedStyle(document.documentElement);
        for (let i = 0; i < rs.length; i++) {
          const n = rs[i];
          if (n && n.indexOf('--') === 0) { const v = rs.getPropertyValue(n).trim(); if (v) vars[n] = v; }
        }
        const doc = [
          { id: 'a1', type: 'paragraph', children: [{ text: '正文一段。' }] },
          { id: 'a2', type: 'paragraph', children: [{ text: '正文二段。' }] },
        ];
        return window.MynoteEditorExport.toHTMLDocument(doc, '混排验收长标题一二三四五', {}, null, {
          subtitle: '11月21日 · 100字', theme: scheme, themeVariables: vars,
          pageBackgroundColor: '', pageTextColor: '', avatarUrl: av === 'img' ? PNG : '',
        });
      }, { scheme, av, PNG });
      await opage.close();
      const p2 = await ctx.newPage();
      await p2.setContent(origHtml, { waitUntil: 'load' });
      await p2.waitForTimeout(300);
      const scr = await p2.evaluate(MEASURE_FN, COMMON_PROPS);
      await p2.emulateMedia({ media: 'print' });
      await p2.waitForTimeout(200);
      const prt = await p2.evaluate(MEASURE_FN, COMMON_PROPS);
      results[label] = { expScreen: scr, expPrint: prt, htmlLen: origHtml.length };
      console.log(`[${label}] done path=${scr.path}`);
      await ctx.close();
    } catch (e) {
      console.log(`[${label}] SKIP: ${String(e).slice(0, 160)}`);
      results[label] = { error: String(e).slice(0, 200) };
    }
  }
}

await browser.close();
fs.writeFileSync(outPath, JSON.stringify(results, null, 1));
console.log('WROTE ' + outPath);
