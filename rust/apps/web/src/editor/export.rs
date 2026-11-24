//! 导出：面板关闭生命周期（代际语义）、导出字数口径、
//! HTML/PDF 快照导出与语义 Markdown 导出。

use super::*;

/// 导出面板动画相位（export_anim 信号取值）：空闲 / 开场
/// 中（双 rAF 未落）/ 关闭中（220ms 计时未落）。回前台补
/// 完（settle_export_on_resume）据此区分挂起的是开还是
/// 关——export_closing 本身两义，单独看无法区分。
pub(super) const EXPORT_ANIM_IDLE: u8 = 0;
pub(super) const EXPORT_ANIM_OPENING: u8 = 1;
pub(super) const EXPORT_ANIM_CLOSING: u8 = 2;

/// 开场落定后的焦点 + Tab 陷阱安装脚本（open_export 的双
/// rAF 完成段与回前台补完共用同一份，保证两条路径终态一
/// 致）：聚焦第一个导出选项，装 document 级 Tab 循环监听
/// （面板离开 DOM 后自摘除）。
pub(super) const EXPORT_FOCUS_TRAP_JS: &str =
    "const b = document.querySelector('[data-export-format]'); if (b) b.focus({ preventScroll: true }); \
     if (window.__mnExportKeys) document.removeEventListener('keydown', window.__mnExportKeys, true); \
     window.__mnExportKeys = (e) => { \
       const panel = document.querySelector('.editor-export-panel'); \
       if (!panel) { document.removeEventListener('keydown', window.__mnExportKeys, true); window.__mnExportKeys = null; return; } \
       if (e.key !== 'Tab') return; \
       const btns = panel.querySelectorAll('button:not([disabled])'); \
       if (!btns.length) return; \
       const first = btns[0], last = btns[btns.length - 1], active = document.activeElement; \
       if (e.shiftKey && (active === first || !panel.contains(active))) { e.preventDefault(); last.focus(); } \
       else if (!e.shiftKey && (active === last || !panel.contains(active))) { e.preventDefault(); first.focus(); } \
     }; \
     document.addEventListener('keydown', window.__mnExportKeys, true); \
     dioxus.send(null);";

/// 导出面板关闭动画（原版 closeExportPanel 口径）：先置
/// closing 态让 CSS transition 播满 220ms 再卸载面板；
/// back_to_menu=false 时连菜单一起关，并把焦点还给 •••
/// 按钮（原版关后 trigger.focus）。
///
/// 生命周期红线：关闭**永不**被「已在关闭中」吞掉。原版
/// closeExportPanel 是 clearTimeout 后重排 220ms 的幂等重
/// 启语义；旧实现却拿 export_closing（进场动画的视觉态）
/// 作关闭门闩——开场置位后靠双 rAF 清除，rAF 饥饿（页面
/// 被遮挡/隐藏、合成器停摆）时该位永不清除，此后所有关
/// 闭路径（选格式、点遮罩、•••、Esc）全部早退，
/// show_export/menu_open 永置 true，透明 .menu-scrim 与
/// opacity-0 面板永久残留、整页点按被拒（云端 Chromium
/// 实证）。现改为代际语义：每次关闭递增 export_gen 并重
/// 排计时，旧计时回调按代际自动作废；开场的 rAF 回调同
/// 样按代际守卫，不得把关闭中的面板翻回可见。关闭的完
/// 成只依赖 setTimeout，不依赖 rAF。
///
/// 遮挡续修（两层）：setTimeout 在页面被挂起时（切页签
/// 看打印弹窗、WKWebView 打印表单呈现）与 rAF 一样会整
/// 体停摆——云端验收在最新构建上再复现：导出后约 74 秒
/// 「export panel closed」才随弹窗关闭出现；虚拟时间暂
/// 停探针定罪：计时未触发期间面板/遮罩残留且命中被拦
/// 截、回前台事件无人收尾。故①命中拦截在关闭发起瞬间
/// 即释放（渲染层据 export_anim/export_to_menu 给关闭中
/// 的面板与全关时的遮罩加 pointer-events:none，见
/// editor.rs 菜单遮罩渲染处），卸载动画照常走计时；②
/// 回前台由 settle_export_on_resume 按相位直接收尾，不
/// 等计时器。
pub(super) fn animate_export_close(
    mut show_export: Signal<bool>,
    mut export_closing: Signal<bool>,
    mut menu_open: Signal<bool>,
    mut export_gen: Signal<u32>,
    mut export_anim: Signal<u8>,
    mut export_to_menu: Signal<bool>,
    back_to_menu: bool,
) {
    if !*show_export.read() {
        if !back_to_menu {
            menu_open.set(false);
        }
        return;
    }
    let gen = *export_gen.read() + 1;
    export_gen.set(gen);
    export_closing.set(true);
    export_anim.set(EXPORT_ANIM_CLOSING);
    export_to_menu.set(back_to_menu);
    spawn(async move {
        let mut eval = document::eval("setTimeout(() => dioxus.send(null), 220);");
        let _ = eval.recv::<Value>().await;
        if *export_gen.read() != gen {
            // 已被更新的关闭/重开取代，本回调作废
            return;
        }
        show_export.set(false);
        export_closing.set(false);
        export_anim.set(EXPORT_ANIM_IDLE);
        diag::log("EDIT", "export panel closed");
        // 去向按完成时的信号现值结算而非发起时的参数：关闭
        // 在飞期间点按 ••• 可改道回菜单（editor.rs ••• 处理），
        // 本计时是当前代际的唯一完成者，读现值即采纳改道；
        // 未改道时现值恒等于发起参数，行为不变。
        if !*export_to_menu.read() {
            menu_open.set(false);
            let mut eval2 = document::eval(
                "const t = document.querySelector('.editor-fab.right'); if (t) t.focus({ preventScroll: true }); dioxus.send(null);",
            );
            let _ = eval2.recv::<Value>().await;
        }
    });
}

/// 回前台补完（遮挡续修）：编辑器的 __mnResume 监听在页
/// 面回到前台（visibilitychange 转 visible / pageshow /
/// focus）时调用。按 export_anim 相位直接收尾挂起的开/
/// 关：递增代际让仍挂着的计时/rAF 回调事后作废，关闭按
/// export_to_menu 记录的去向完成（全关连菜单一起关并把
/// 焦点还给 •••，与计时路径终态一致），开场则撤 closing
/// 并补装焦点/陷阱。空闲相位直接返回——本函数会在每次
/// 回前台时被调用，无挂起时无副作用、无日志。
///
/// 关闭中改道（第六批小修）：关闭在飞时点按 ••• 不重排
/// 关闭，只把 export_to_menu 置 true 改道回菜单——原版
/// toggleEditorMenu 与面板状态机解耦、点按永不被吞，合并
/// 架构的等价语义是关闭照常落定、终点落在菜单。计时完成
/// 与本补完都按 export_to_menu 现值结算去向，故改道对两
/// 条完成路径同时生效。
pub(super) fn settle_export_on_resume(
    mut show_export: Signal<bool>,
    mut export_closing: Signal<bool>,
    mut menu_open: Signal<bool>,
    mut export_gen: Signal<u32>,
    mut export_anim: Signal<u8>,
    export_to_menu: Signal<bool>,
) {
    // 先落局部变量：match 判别式直接读信号会让读借用活到
    // 整个 match 结束，臂内 set 触发可变借用冲突（E0502）
    let phase = *export_anim.read();
    match phase {
        EXPORT_ANIM_CLOSING => {
            let gen = *export_gen.read() + 1;
            export_gen.set(gen);
            let back_to_menu = *export_to_menu.read();
            show_export.set(false);
            export_closing.set(false);
            export_anim.set(EXPORT_ANIM_IDLE);
            diag::log("EDIT", "export panel closed on resume");
            if !back_to_menu {
                menu_open.set(false);
                spawn(async move {
                    let mut eval = document::eval(
                        "const t = document.querySelector('.editor-fab.right'); if (t) t.focus({ preventScroll: true }); dioxus.send(null);",
                    );
                    let _ = eval.recv::<Value>().await;
                });
            }
        }
        EXPORT_ANIM_OPENING => {
            let gen = *export_gen.read() + 1;
            export_gen.set(gen);
            export_closing.set(false);
            export_anim.set(EXPORT_ANIM_IDLE);
            diag::log("EDIT", "export open settled on resume");
            spawn(async move {
                let mut eval = document::eval(EXPORT_FOCUS_TRAP_JS);
                let _ = eval.recv::<Value>().await;
            });
        }
        _ => {}
    }
}

/// 打开导出面板（原版 openExportPanel 的面板侧口径）：
/// 挂载即 closing 态，双 rAF 后撤下让 CSS transition 弹
/// 簧入场；入场后聚焦第一个导出选项并装 Tab 焦点陷阱。
/// 菜单侧的 220ms 退场时序由 animate_menu_close 的
/// MenuAfter::Export 承接（原版 openExportPanel 先
/// closeEditorMenu、220ms 后才挂面板），本函数只管面
/// 板挂载后的开场，与 editor.rs 的菜单项共用同一份。
pub(super) fn begin_export_open(
    mut show_export: Signal<bool>,
    mut export_closing: Signal<bool>,
    mut export_gen: Signal<u32>,
    mut export_anim: Signal<u8>,
) {
    let gen = *export_gen.read() + 1;
    export_gen.set(gen);
    show_export.set(true);
    export_closing.set(true);
    export_anim.set(EXPORT_ANIM_OPENING);
    spawn(async move {
        // 双 rAF 为主触发；另加 setTimeout 兜底唤醒——只靠
        // rAF 时出现过唤醒丢失、面板永卡 closing 态（不可
        // 点、点击穿透到遮罩）的实证。两次 send 先到者生效，
        // 后到者对已释放的通道无副作用。
        let mut eval = document::eval(
            "requestAnimationFrame(() => requestAnimationFrame(() => dioxus.send(null))); setTimeout(() => dioxus.send(null), 150);",
        );
        let _ = eval.recv::<Value>().await;
        if *export_gen.read() != gen {
            // 开场期间已被关闭/重开取代：不得把关闭中的
            // 面板翻回可见，也不再装焦点/陷阱
            return;
        }
        export_closing.set(false);
        export_anim.set(EXPORT_ANIM_IDLE);
        diag::log("EDIT", "export panel opened");
        let mut eval2 = document::eval(EXPORT_FOCUS_TRAP_JS);
        let _ = eval2.recv::<Value>().await;
    });
}

/// 原版导出字数与编辑页字数不同源：handleExportFormat 先
/// parseEditorDOM(实时 DOM) 再按同一公式数（editor.js:1319/1349）。
/// 链接卡元素没有 data-type（renderAtomicHTMLUnsafe 只给
/// data-url），parseEditorDOM 于是把它当 paragraph，textContent
/// （标题+副标题+图标+来源行）整段计入——混排夹具实测原版
/// 导出 252 = 模型口径 233 + 链接卡渲染文本 19。此函数在模型
/// 上复刻该口径：paragraph 按 orig_char_count，link-card 按
/// 原版渲染器的 textContent 逐字拼（字段以 editor.render.js
/// 的 link-card 分支为准）。
pub(super) fn export_char_count(doc: &[Node]) -> usize {
    let mut total = orig_char_count(doc);
    for node in doc {
        if node.block_type() == Some("link-card") {
            total += link_card_count_text(node)
                .replace('\n', "")
                .encode_utf16()
                .count();
        }
    }
    total
}

/// 原版链接卡渲染后的 textContent（计数专用，逐字对
/// editor.render.js link-card 分支）：无标题 → err 卡
/// （标题=主机名||URL、图标 🔗、来源行=完整 URL）；有标题 →
/// 标题 + 副标题（哔哩哔哩不显示）+ 类型图标 + 来源
/// （meta.source || 主机名）。
fn link_card_count_text(node: &Node) -> String {
    let url = node.extra.get("url").and_then(|v| v.as_str()).unwrap_or("");
    let meta = node.extra.get("meta").cloned().unwrap_or(Value::Null);
    let mget = |k: &str| meta.get(k).and_then(|v| v.as_str()).unwrap_or("");
    let title = mget("title");
    let host = crate::blocks::host_of(url);
    if title.is_empty() {
        let shown = if host.is_empty() { url } else { host.as_str() };
        return format!("{shown}🔗{url}");
    }
    let ty = mget("type");
    let is_bilibili = mget("source") == "哔哩哔哩"
        || (ty == "video" && (url.contains("bilibili") || url.contains("b23.tv")));
    let subtitle = if is_bilibili { "" } else { mget("subtitle") };
    let source = {
        let s = mget("source");
        if s.is_empty() { host.as_str() } else { s }
    };
    format!(
        "{title}{subtitle}{}{source}",
        crate::blocks::type_icon(if ty.is_empty() { None } else { Some(ty) })
    )
}

fn esc_html(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// 属性值转义（原版 escapeHTML 全集：& < > " '）。导出文档
/// 的 <html style="…"> 里钉着 --font-family-base 等变量，其值
/// 含引号（"SF Pro Display"）——只用 esc_html 时引号会提前
/// 终结属性：变量被截成尾随逗号的坏值，其后的变量整段丢失，
/// font 简写计算期失效，导出全文行高塌成 normal（混排夹具
/// 实测：每块 lh normal vs 原版 28px）。原版 toHTMLDocument
/// 对 style 属性走 escapeHTML（export.js:445），此处补齐。
fn esc_attr(s: &str) -> String {
    esc_html(s)
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

/// 导出 HTML：独立网页（原版导出面板的 HTML 路径），PDF 导出
/// 复用同一份 HTML 走打印窗。
/// 导出资产（原版 captureEditorSnapshot + captureEditorChrome +
/// collectStyleText + 主题变量的等价物，一次 eval 收齐）：
/// 样式表全文、正文实时 DOM 快照（所见即所得，含 md 预览渲染
/// 结果；checkbox 状态同步、双栏拍平、blob: 图片转 data: 内嵌，
/// 保证导出文档自包含）、页眉 chrome 快照（真实的返回钮/标题
/// 坞/更多钮克隆，剥编辑属性、meta 换成导出副行、高度实测）、
/// 当前主题模式与根元素全部 CSS 变量的解析值（导出文档里钉死，
/// 不依赖打开时的系统主题）。
pub(super) struct ExportAssets {
    pub(super) css: String,
    pub(super) snapshot_html: Option<String>,
    pub(super) chrome_html: Option<String>,
    pub(super) header_height: f64,
    pub(super) dark: bool,
    pub(super) vars: Vec<(String, String)>,
}

const EXPORT_ASSETS_JS: &str = r##"(async () => {
  let css = '';
  try {
    for (const sh of document.styleSheets) {
      try { for (const r of sh.cssRules) css += r.cssText + '\n'; } catch (e) {}
    }
  } catch (e) {}
  let dark = false;
  try { dark = !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches); } catch (e) {}
  const vars = {};
  try {
    const rs = window.getComputedStyle(document.documentElement);
    for (let i = 0; i < rs.length; i++) {
      const n = rs[i];
      if (n && n.indexOf('--') === 0) {
        const v = rs.getPropertyValue(n).trim();
        if (v) vars[n] = v;
      }
    }
  } catch (e) {}
  let snap = '';
  try {
    const bodyEl = document.querySelector('#editor-root .editor-body');
    if (bodyEl) {
      const clone = bodyEl.cloneNode(true);
      const oc = bodyEl.querySelectorAll('input[type="checkbox"]');
      const cc = clone.querySelectorAll('input[type="checkbox"]');
      for (let i = 0; i < oc.length && i < cc.length; i++) {
        if (oc[i].checked) cc[i].setAttribute('checked', ''); else cc[i].removeAttribute('checked');
      }
      const cols = clone.querySelectorAll('.editor-column');
      if (cols.length) {
        const kids = [];
        cols.forEach((col) => { while (col.childNodes.length) kids.push(col.removeChild(col.childNodes[0])); });
        while (clone.childNodes.length) clone.removeChild(clone.childNodes[0]);
        kids.forEach((k) => clone.appendChild(k));
      }
      clone.classList.remove('show-placeholder');
      clone.classList.remove('is-independent-scroll');
      clone.classList.remove('is-flow-columns');
      const imgs = Array.prototype.slice.call(clone.querySelectorAll('img'));
      await Promise.all(imgs.map(async (img) => {
        const src = img.getAttribute('src') || '';
        if (src.indexOf('blob:') === 0) {
          try {
            const b = await (await fetch(src)).blob();
            // 编辑器内的 blob 是无类型 Blob（idb::blob_url 未
            // 带 MIME），直转会得到 data:application/octet-stream，
            // 部分浏览器对 <img> 不嗅探则不渲染；按文件头嗅探
            // 出真实图片类型再转（原版 data URL 恒带真实类型）
            const buf = await b.arrayBuffer();
            const u8 = new Uint8Array(buf);
            let mime = b.type || '';
            if (!mime || mime === 'application/octet-stream') {
              if (u8[0] === 0x89 && u8[1] === 0x50) mime = 'image/png';
              else if (u8[0] === 0xFF && u8[1] === 0xD8) mime = 'image/jpeg';
              else if (u8[0] === 0x47 && u8[1] === 0x49 && u8[2] === 0x46) mime = 'image/gif';
              else if (u8[0] === 0x52 && u8[1] === 0x49 && u8[8] === 0x57) mime = 'image/webp';
              else if (u8[0] === 0x42 && u8[1] === 0x4D) mime = 'image/bmp';
            }
            const typed = mime && mime !== b.type ? new Blob([buf], { type: mime }) : b;
            const du = await new Promise((res) => { const r = new FileReader(); r.onload = () => res(String(r.result || '')); r.onerror = () => res(''); r.readAsDataURL(typed); });
            if (du) img.setAttribute('src', du);
          } catch (e) {}
        }
      }));
      snap = clone.innerHTML;
    }
  } catch (e) {}
  let chromeHtml = '';
  let headerHeight = 0;
  try {
    const back = document.querySelector('.editor-fab.left');
    const dock = document.querySelector('.editor-title-dock');
    const more = document.querySelector('.editor-fab.right');
    if (back && dock && more) {
      const cb = back.cloneNode(true);
      const cd = dock.cloneNode(true);
      const cm = more.cloneNode(true);
      [cb, cm].forEach((b) => { b.setAttribute('aria-hidden', 'true'); b.setAttribute('tabindex', '-1'); });
      const fi = cd.querySelector('#file-avatar');
      if (fi) fi.remove();
      const meta = cd.querySelector('.editor-title-meta');
      if (meta) { meta.textContent = __SUBTITLE_JSON__; meta.style.display = 'block'; }
      const ti = cd.querySelector('#editor-title-text');
      if (ti) {
        // 标题元素现为原生 input：导出快照是静态文档，
        // 克隆换成同类名的静态 div 承载显示文本（与原版
        // captureEditorChrome 的标题形态一致——innerText/
        // 打印/页眉量测都以文本节点为准）；文本取 live
        // 元素的实时 value（展示态即展示文本，截断态就
        // 是截断文本），全文仍只进 title 属性。
        const liveTi = document.querySelector('#editor-title-text');
        const snap = document.createElement('div');
        snap.id = 'editor-title-text';
        snap.className = 'editor-title-input';
        snap.textContent = liveTi ? liveTi.value : '';
        snap.setAttribute('title', __TITLE_JSON__);
        snap.style.cursor = 'default';
        ti.replaceWith(snap);
      }
      cd.querySelectorAll('button').forEach((b) => b.setAttribute('tabindex', '-1'));
      cd.style.flexDirection = 'column';
      cd.style.alignItems = 'center';
      cd.style.justifyContent = 'center';
      cd.style.flexWrap = 'nowrap';
      cd.style.gap = '6px';
      const holder = document.createElement('div');
      holder.appendChild(cb);
      holder.appendChild(cd);
      holder.appendChild(cm);
      chromeHtml = holder.innerHTML;
      const mh = (el, fb) => { if (!el) return fb; try { const r = el.getBoundingClientRect(); if (r && r.height > 0) return r.height; } catch (e) {} return fb; };
      let top = 7;
      try { const r = dock.getBoundingClientRect(); if (r && r.top > 0) top = r.top; } catch (e) {}
      const pill = cd.querySelector('.editor-title-capsule');
      headerHeight = Math.ceil(top + mh(dock.querySelector('.editor-avatar-button'), 72) + 6 + mh(pill, 66) + 6 + mh(dock.querySelector('.editor-title-meta'), 12) + 16);
    }
  } catch (e) {}
  dioxus.send(JSON.stringify({ css: css, dark: dark, vars: vars, snap: snap, chromeHtml: chromeHtml, headerHeight: headerHeight }));
})();"##;

pub(super) async fn collect_export_assets(subtitle: &str, title: &str) -> ExportAssets {
    let js = EXPORT_ASSETS_JS
        .replace(
            "__SUBTITLE_JSON__",
            &serde_json::to_string(subtitle).unwrap_or_else(|_| "\"\"".to_string()),
        )
        .replace(
            "__TITLE_JSON__",
            &serde_json::to_string(title).unwrap_or_else(|_| "\"\"".to_string()),
        );
    let mut eval = document::eval(&js);
    let raw = eval.recv::<String>().await.unwrap_or_default();
    let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
    let vars = v
        .get("vars")
        .and_then(|m| m.as_object())
        .map(|m| {
            let mut pairs: Vec<(String, String)> = m
                .iter()
                .filter_map(|(k, val)| {
                    val.as_str().map(|s| (k.clone(), s.trim().to_string()))
                })
                .filter(|(k, val)| k.starts_with("--") && !val.is_empty())
                .collect();
            pairs.sort();
            pairs
        })
        .unwrap_or_default();
    let snap = v
        .get("snap")
        .and_then(|s| s.as_str())
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.to_string());
    let chrome = v
        .get("chromeHtml")
        .and_then(|s| s.as_str())
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.to_string());
    ExportAssets {
        css: v
            .get("css")
            .and_then(|s| s.as_str())
            .unwrap_or("")
            .to_string(),
        snapshot_html: snap,
        chrome_html: chrome,
        header_height: v.get("headerHeight").and_then(|n| n.as_f64()).unwrap_or(0.0),
        dark: v.get("dark").and_then(|b| b.as_bool()).unwrap_or(false),
        vars,
    }
}

/// 导出附件解析结果（原版 files 表的等价物）：导出文档/Markdown
/// 里的图片与附件都以 data: URL 自包含呈现。
pub(super) struct ExportFile {
    name: String,
    mime: String,
    data_url: String,
    size: usize,
}

/// 画廊条目（C-08：attrs.items 三形态——字符串=附件 id、
/// {fileId} 对象、{url} 对象，fileId 优先；与渲染侧
/// blocks::gallery_items 同口径。原版导出 galleryItems
/// 同此解析序。此前只收字符串/{fileId}，{url} 条目在
/// HTML/MD 导出中被整体丢弃。）
enum ExportGalleryItem {
    File(String),
    Url(String),
}

fn export_gallery_items(node: &Node) -> Vec<ExportGalleryItem> {
    fn item_of(it: &Value) -> Option<ExportGalleryItem> {
        if let Some(s) = it.as_str() {
            return if s.is_empty() {
                None
            } else {
                Some(ExportGalleryItem::File(s.to_string()))
            };
        }
        if let Some(s) = it.get("fileId").and_then(|v| v.as_str()) {
            if !s.is_empty() {
                return Some(ExportGalleryItem::File(s.to_string()));
            }
        }
        if let Some(s) = it.get("url").and_then(|v| v.as_str()) {
            if !s.is_empty() {
                return Some(ExportGalleryItem::Url(s.to_string()));
            }
        }
        None
    }
    if let Some(items) = node
        .extra
        .get("attrs")
        .and_then(|a| a.get("items"))
        .and_then(|v| v.as_array())
    {
        return items.iter().filter_map(item_of).collect();
    }
    // attrs.items 非数组时回退 children 的 fileId（与渲染侧同）
    node.children
        .as_ref()
        .map(|kids| {
            kids.iter()
                .filter_map(|k| crate::blocks::file_id(k))
                .map(ExportGalleryItem::File)
                .collect()
        })
        .unwrap_or_default()
}

/// 画廊条目中的附件 id（收集导出文件用；{url} 条目不产生文件）。
fn export_gallery_ids(node: &Node) -> Vec<String> {
    export_gallery_items(node)
        .into_iter()
        .filter_map(|i| match i {
            ExportGalleryItem::File(id) => Some(id),
            ExportGalleryItem::Url(_) => None,
        })
        .collect()
}

fn base64_encode(bytes: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0] as u32,
            *chunk.get(1).unwrap_or(&0) as u32,
            *chunk.get(2).unwrap_or(&0) as u32,
        ];
        let n = (b[0] << 16) | (b[1] << 8) | b[2];
        out.push(T[(n >> 18) as usize & 63] as char);
        out.push(T[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            T[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            T[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

/// 收集文档引用的全部附件并解析为 data: URL（IDB 字节 +
/// manifest 的 name/type）。缺失字节的附件不入表，渲染侧走
/// 原版的占位/纯文本口径。
pub(super) async fn collect_export_files(
    doc: &[Node],
    manifest_raw: &str,
) -> std::collections::HashMap<String, ExportFile> {
    let manifest: Value = serde_json::from_str(manifest_raw).unwrap_or(Value::Null);
    let mut ids: Vec<String> = Vec::new();
    let mut push_id = |id: Option<String>| {
        if let Some(id) = id {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
    };
    for node in doc {
        match node.node_type.as_deref().unwrap_or("") {
            "image" | "imgTextCard" | "imageTextRow" | "attachment" => {
                push_id(crate::blocks::file_id(node))
            }
            "gallery" => {
                for id in export_gallery_ids(node) {
                    push_id(Some(id));
                }
            }
            _ => {}
        }
    }
    let mut out = std::collections::HashMap::new();
    for id in ids {
        let entry = manifest
            .get("attachments")
            .and_then(|a| a.get(&id))
            .cloned()
            .unwrap_or(Value::Null);
        let name = entry
            .get("name")
            .and_then(|n| n.as_str())
            .unwrap_or(&id)
            .to_string();
        let mime = entry
            .get("type")
            .and_then(|n| n.as_str())
            .unwrap_or("application/octet-stream")
            .to_string();
        if let Some(bytes) = crate::idb::get_attachment(&id).await {
            let data_url = format!("data:{mime};base64,{}", base64_encode(&bytes));
            out.insert(
                id,
                ExportFile {
                    name,
                    mime,
                    data_url,
                    size: bytes.len(),
                },
            );
        }
    }
    out
}

/// 导出文档的兜底样式（原版 export.js fallbackStyles 逐字）。
const EXPORT_FALLBACK_CSS: &str = r#":root{color-scheme:light dark;--primary-bg:Canvas;--text-main:CanvasText;--text-secondary:GrayText;--border-color:GrayText;--glass-content-bg:Canvas;--glass-content-border:GrayText;--fill-subtle:Canvas;--code-bg:Canvas;--color-accent:LinkText;--md-text-muted:GrayText;--font-family-base:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;--font-family-mono:ui-monospace,Menlo,Consolas,monospace;--font-11:11px;--font-12:12px;--font-13:13px;--font-14:14px;--font-24:24px;--radius-10:10px;--radius-12:12px;--radius-14:14px;--radius-18:18px;--radius-22:22px;--radius-999:999px;--radius-circle:50%}
@media(prefers-color-scheme:dark){:root{--primary-bg:Canvas;--text-main:CanvasText;--text-secondary:GrayText;--glass-content-bg:Canvas;--glass-content-border:GrayText;--border-color:GrayText;--fill-subtle:Canvas;--code-bg:Canvas}}
*{box-sizing:border-box}html{background:var(--primary-bg);color:var(--text-main);font:16px/1.75 var(--font-family-base)}body{margin:0;background:var(--primary-bg);color:var(--text-main);overflow-wrap:anywhere}.editor-body{min-height:0}.editor-body p{margin:0 0 .65em}.editor-body h1,.editor-body h2,.editor-body h3,.editor-body h4{line-height:1.28;margin:1.25em 0 .4em}.editor-body blockquote{margin:.75em 0;padding:10px 14px;border-left:3px solid var(--color-accent);border-radius:var(--radius-10);background:var(--fill-subtle)}.editor-body pre{max-width:100%;overflow:auto;padding:12px 14px;border:1px solid var(--border-color);border-radius:var(--radius-12);background:var(--code-bg)}.editor-body .img-text-card,.editor-body .img-text-row,.editor-body .link-card-block,.editor-body .link-card-err,.editor-body .attachment-file{margin:8px 0;overflow:hidden;border:1px solid var(--glass-content-border);border-radius:var(--radius-22);background:var(--glass-content-bg)}.editor-body .itc-img-wrap img,.editor-body .lkc-cover img{display:block;width:100%;max-width:100%;height:auto;object-fit:cover}.editor-body .itc-text{padding:12px 14px;font-size:var(--font-14);white-space:pre-wrap}.editor-body .img-text-row{display:flex;min-height:181px;max-height:196px}.editor-body .itr-img{flex:0 0 50%;overflow:hidden}.editor-body .itr-img img{width:100%;height:100%;object-fit:cover}.editor-body .itr-text{flex:1;overflow:hidden;padding:10px 14px;font-size:var(--font-14);white-space:pre-wrap}.editor-body .atomic[data-type="gallery"]{margin:8px 36px}.editor-body .atomic[data-type="image"]{margin:8px 36px}.editor-body .atomic.attachment img{max-width:100%;border-radius:var(--radius-22)}.editor-body .attachment-file{display:flex;align-items:center;gap:10px;padding:16px 20px}.editor-body .att-name{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.editor-body .lkc-cover{width:100%;aspect-ratio:2.4/1;overflow:hidden}.editor-body .lkc-body{padding:10px 14px 12px}.editor-body .lkc-title{font-size:var(--font-14);font-weight:600;line-height:1.4}.editor-body .lkc-subtitle,.editor-body .lkc-source{font-size:var(--font-12);color:var(--text-secondary)}.editor-body .todo-checkbox{accent-color:var(--color-accent)}img{max-width:100%}@media print{body{print-color-adjust:exact;-webkit-print-color-adjust:exact}}"#;

/// 导出外壳/页眉/打印样式（原版 snapshotStyles 的固定部分）。
const EXPORT_SHELL_CSS: &str = r#".mynote-export-shell{box-sizing:border-box;width:min(100%,1120px);margin:0 auto;padding:24px 16px 40px;color:var(--text-main,CanvasText)}
.mynote-export-shell math{font-family:"STIX Two Math","Cambria Math","Latin Modern Math","Noto Sans Math",math,serif}
.mynote-export-header{position:relative;box-sizing:border-box;display:block;width:100vw;height:185px;margin:0 0 28px calc(50% - 50vw);padding:0}
.mynote-export-header>.editor-fab,.mynote-export-header>.editor-title-dock{position:absolute!important;top:calc(env(safe-area-inset-top) + 7px)!important}
.mynote-export-header>.editor-fab.left{left:16px!important}
.mynote-export-header>.editor-fab.right{right:16px!important}
.mynote-export-header>.editor-title-dock{left:62px!important;right:62px!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;flex-wrap:nowrap!important;gap:6px!important}
.mynote-export-header .editor-title-meta{display:block!important}
.mynote-export-header .editor-title-input,.mynote-export-header .editor-avatar-button{cursor:default!important}
.mynote-export-control{box-sizing:border-box;position:absolute;top:7px;display:grid;place-items:center;width:46px;height:46px;border:0.5px solid var(--glass-control-border,var(--border-color,rgba(0,0,0,.14)));border-radius:50%;background:var(--glass-control-bg,Canvas);color:var(--text-secondary,GrayText)}
.mynote-export-back{left:16px}.mynote-export-more{right:16px}
.mynote-export-dock{position:absolute;top:7px;left:62px;right:62px;display:flex;flex-direction:column;align-items:center;gap:6px}
.mynote-export-avatar{box-sizing:border-box;width:72px;height:72px;overflow:hidden;border:0.5px solid var(--glass-control-border,var(--border-color,rgba(0,0,0,.14)));border-radius:50%;background:var(--glass-control-bg,Canvas);display:flex;align-items:flex-end;justify-content:center}
.mynote-export-avatar img{display:block;width:100%;height:100%;object-fit:cover}
.mynote-export-avatar-fallback{display:flex;width:100%;height:100%;align-items:flex-end;justify-content:center;overflow:hidden}
.mynote-export-title-pill{box-sizing:border-box;display:flex;align-items:center;justify-content:center;min-width:66px;max-width:100%;height:66px;overflow:hidden;padding:0 20px;border:0.5px solid var(--glass-control-border,var(--border-color,rgba(0,0,0,.14)));border-radius:var(--radius-33,33px);background:var(--glass-control-bg,Canvas);backdrop-filter:var(--glass-control-filter);-webkit-backdrop-filter:var(--glass-control-filter)}
.mynote-export-title-pill .note-title{box-sizing:border-box;max-width:100%;margin:0;color:var(--text-main,CanvasText);font:600 14px/1.3 var(--font-family-base,-apple-system,BlinkMacSystemFont,sans-serif);letter-spacing:-.2px;text-align:center;overflow-wrap:anywhere}
.mynote-export-meta{width:100%;color:var(--text-secondary,GrayText);font:var(--font-10,10px)/1.2 var(--font-family-base,-apple-system,BlinkMacSystemFont,sans-serif);text-align:center;white-space:nowrap}
@media(max-width:560px){.mynote-export-shell{padding:18px 14px 32px}.mynote-export-header{margin-bottom:24px}}
.mynote-export-shell .editor-body{box-sizing:border-box;min-height:0;padding:4px 0;color:var(--text-main,CanvasText);font:var(--md-font-body,16px)/var(--md-line-height,1.75) var(--font-family-base,-apple-system,BlinkMacSystemFont,sans-serif);overflow-wrap:anywhere}
.mynote-export-shell .editor-body>*:first-child{margin-top:0}
.mynote-export-shell .editor-body>*:last-child{margin-bottom:0}
@page{size:auto;margin:16mm}
@media print{html,body{print-color-adjust:exact;-webkit-print-color-adjust:exact}body{padding:0}.mynote-export-shell{width:100%;max-width:none;margin:0;padding:0}.mynote-export-header{width:100%;height:185px;margin:0 0 22px;break-inside:avoid}.mynote-export-shell .editor-body{min-height:0}.note-title{break-after:avoid}}"#;

/// 无头像时的恐龙兜底（原版 dinosaurAvatarMarkup 逐字路径）。
fn export_avatar_fallback() -> String {
    const PATHS: [&str; 10] = [
        "M 90,460 L 90,170 C 90,110 140,70 210,70 L 380,95 C 440,95 470,130 470,185 C 470,225 450,240 410,245 C 350,250 280,230 210,265 C 190,275 190,295 210,310 C 270,350 350,380 410,360 C 435,350 440,325 410,315",
        "M 160,330 C 180,380 230,440 280,460",
        "M 240,365 C 220,400 240,440 310,460",
        "M 90,460 L 310,460",
        "M 415,135 C 425,140 435,150 435,160",
        "M 230,115 C 260,95 310,120 355,140",
        "M 255,140 C 255,170 290,195 320,185 C 345,175 350,150 335,135",
        "M 290,145 C 290,165 315,165 315,150",
        "M 250,243 L 255,265 L 265,243 M 275,245 L 282,270 L 292,245 M 302,246 L 310,273 L 320,247 M 330,248 L 340,275 L 350,248 M 360,249 L 370,274 L 380,248 M 390,248 L 400,270 L 408,246 M 415,244 L 425,263 L 432,240 M 438,235 L 448,252 L 452,228",
        "M 250,323 L 255,305 L 263,326 M 273,329 L 280,308 L 288,333 M 298,336 L 306,313 L 314,340 M 324,343 L 333,318 L 341,346 M 351,348 L 361,323 L 369,351 M 379,352 L 389,328 L 396,353 M 404,351 L 413,330 L 418,348",
    ];
    let paths: String = PATHS
        .iter()
        .map(|d| format!("<path d=\"{d}\"></path>"))
        .collect();
    format!("<span class=\"mynote-export-avatar-fallback\" aria-hidden=\"true\"><svg viewBox=\"0 0 512 512\" width=\"60\" height=\"60\" fill=\"none\" stroke=\"var(--color-icon-muted)\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"transform:translateY(10px)\">{paths}</svg></span>")
}

/// 导出 HTML 文档（原版 toHTMLDocument + visualSnapshotMarkup
/// 口径）：正文优先用实时 DOM 快照（所见即所得），快照缺失才
/// 退回 block_html 模型渲染；页眉优先用 chrome 快照（真实坞
/// 克隆 + 实测高度），缺失才用手工页眉；主题模式与全部 CSS
/// 变量解析值钉在 <html> 上（原版 exportThemeAttributes）；
/// body 带页面底色（原版 pageBackgroundColor，调用方已按
/// effective_bg 口径算好）。
pub(super) fn doc_to_html(
    title: &str,
    doc: &[Node],
    subtitle: &str,
    avatar_url: Option<&str>,
    page_bg: &str,
    assets: &ExportAssets,
    files: &std::collections::HashMap<String, ExportFile>,
) -> String {
    let name = {
        let t = title.trim();
        if t.is_empty() { "无标题" } else { t }
    };
    let content = match &assets.snapshot_html {
        Some(s) => s.clone(),
        None => {
            let mut c = String::new();
            for n in doc {
                block_html(n, files, &mut c);
            }
            c
        }
    };
    let header = match &assets.chrome_html {
        Some(chrome) => {
            let h = if assets.header_height > 0.0 {
                assets.header_height
            } else {
                185.0
            };
            format!(
                "<header class=\"mynote-export-header\" aria-label=\"笔记页眉\" style=\"height:{}px\">{}</header>",
                (h.max(160.0)) as i64,
                chrome
            )
        }
        None => {
            // C-30：页眉头像 src 过图片白名单，被拦回落
            // 默认头像（原版导出页眉同走 safeImageUrl 口径）
            let avatar_markup = match avatar_url {
                Some(u) => {
                    let safe = mynote_core::safe_image_url(u);
                    if safe.is_empty() {
                        export_avatar_fallback()
                    } else {
                        format!("<img src=\"{}\" alt=\"avatar\">", esc_html(&safe))
                    }
                }
                None => export_avatar_fallback(),
            };
            // 原版口径：String.length（UTF-16 单元数）判长标题
            let title_size = if name.encode_utf16().count() > 5 { "11px" } else { "14px" };
            format!(
                "<header class=\"mynote-export-header\" aria-label=\"笔记页眉\" style=\"height:185px\">\
                 <span class=\"mynote-export-control mynote-export-back\" aria-hidden=\"true\"><svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"15 18 9 12 15 6\"></polyline></svg></span>\
                 <div class=\"mynote-export-dock\"><div class=\"mynote-export-avatar\">{avatar_markup}</div>\
                 <div class=\"mynote-export-title-pill\"><h1 class=\"note-title\" style=\"font-size:{title_size}\">{}</h1></div>\
                 <div class=\"mynote-export-meta\">{}</div></div>\
                 <span class=\"mynote-export-control mynote-export-more\" aria-hidden=\"true\"><svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"currentColor\"><circle cx=\"5\" cy=\"12\" r=\"2\"></circle><circle cx=\"12\" cy=\"12\" r=\"2\"></circle><circle cx=\"19\" cy=\"12\" r=\"2\"></circle></svg></span></header>",
                esc_html(name),
                esc_html(subtitle)
            )
        }
    };
    let css = if assets.css.trim().is_empty() {
        format!("{EXPORT_FALLBACK_CSS}\n{EXPORT_SHELL_CSS}")
    } else {
        format!("{}\n{}", assets.css, EXPORT_SHELL_CSS)
    };
    let mode = if assets.dark { "dark" } else { "light" };
    let mut html_style = format!("color-scheme:{mode}");
    for (k, v) in &assets.vars {
        html_style.push_str(&format!(";{k}:{v}"));
    }
    let body_style = format!(
        " style=\"background-color:{};color:var(--text-main,CanvasText)\"",
        esc_attr(page_bg)
    );
    format!(
        "<!doctype html>\n<html lang=\"zh-CN\" data-export-theme=\"{mode}\" style=\"{}\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"color-scheme\" content=\"{mode}\"><title>{}</title><style>{}</style></head><body{}><main class=\"mynote-export-shell\">{}<div class=\"editor-body\">{}</div></main></body></html>",
        esc_attr(&html_style),
        esc_html(name),
        css,
        body_style,
        header,
        content
    )
}

/// 字节数格式（原版 formatBytes 口径）。
fn format_bytes(bytes: usize) -> String {
    let b = bytes as f64;
    if bytes < 1024 {
        format!("{bytes} B")
    } else if bytes < 1024 * 1024 {
        format!("{:.1} KB", b / 1024.0)
    } else {
        format!("{:.1} MB", b / (1024.0 * 1024.0))
    }
}

/// 导出图片元素（原版 imageElement 口径）：无可用文件时是
/// 「图片未能导出」占位。
fn export_img_html(
    file: Option<&ExportFile>,
    class: &str,
    out: &mut String,
) {
    match file {
        Some(f) => out.push_str(&format!(
            "<img class=\"{}\" src=\"{}\" alt=\"{}\">",
            class,
            f.data_url,
            esc_html(&f.name)
        )),
        None => out.push_str("<div class=\"media-placeholder\">图片未能导出</div>"),
    }
}

/// 链接/音乐卡（原版 renderLinkCard 口径）。
fn export_link_card_html(node: &Node, is_music: bool, out: &mut String) {
    let url = node
        .extra
        .get("url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    // C-30：统一走共享白名单（大小写不敏感 + 混淆防护），
    // 卡片场景再收紧为仅 http(s)——相对引用/mailto 不成卡链
    let url = {
        let s = mynote_core::safe_http_url(&url);
        let low = s.to_lowercase();
        if low.starts_with("http://") || low.starts_with("https://") {
            s
        } else {
            String::new()
        }
    };
    let meta = node.extra.get("meta").cloned().unwrap_or(Value::Null);
    let mget = |k: &str| {
        meta.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string()
    };
    let title = {
        let t = mget("title");
        if !t.is_empty() {
            t
        } else {
            let n = mget("name");
            if !n.is_empty() {
                n
            } else if !url.is_empty() {
                url.clone()
            } else if is_music {
                "音乐链接".to_string()
            } else {
                "网页链接".to_string()
            }
        }
    };
    let subtitle = mget("subtitle");
    let source = mget("source");
    // C-30：封面走共享图片白名单并以净化值作 src（此前
    // 前缀口径放行 data:image/svg+xml 等，与原版不符）
    let cover = mynote_core::safe_image_url(&mget("cover"));
    let cover_ok = !cover.is_empty();
    let label = if is_music { "🎵" } else { "🔗" };
    let mut card = String::from("<span class=\"lkc-card\">");
    if cover_ok {
        card.push_str(&format!(
            "<span class=\"lkc-cover\"><img class=\"lkc-cover-image\" src=\"{}\" alt=\"\"></span>",
            esc_html(&cover)
        ));
    }
    card.push_str(&format!(
        "<span class=\"lkc-body{}\"><span class=\"lkc-title\">{}</span>",
        if cover_ok { " has-cover" } else { "" },
        esc_html(&title)
    ));
    if !subtitle.is_empty() {
        card.push_str(&format!(
            "<span class=\"lkc-subtitle\">{}</span>",
            esc_html(&subtitle)
        ));
    }
    card.push_str(&format!(
        "<span class=\"lkc-source\"><span class=\"lkc-source-icon\">{label}</span>"
    ));
    if !source.is_empty() {
        card.push_str(&format!(
            "<span class=\"lkc-source-dot\"></span><span class=\"lkc-source-text\">{}</span>",
            esc_html(&source)
        ));
    }
    card.push_str("</span></span></span>");
    out.push_str(&format!(
        "<div class=\"note-media note-link-card{}\">{}</div>",
        if is_music { " note-music-card" } else { "" },
        if url.is_empty() {
            card.clone()
        } else {
            format!(
                "<a class=\"lkc-link\" href=\"{}\" target=\"_blank\" rel=\"noopener noreferrer\">{}</a>",
                esc_html(&url),
                card
            )
        }
    ));
}

fn block_html(
    node: &Node,
    files: &std::collections::HashMap<String, ExportFile>,
    out: &mut String,
) {
    let ty = node.node_type.as_deref().unwrap_or("paragraph");
    let inner = inlines_to_html(node.children.as_deref().unwrap_or(&[]));
    match ty {
        "heading" => {
            // 审计 E-16：原版 renderBlock 结构——
            // div.note-text.note-heading 包 hN，level 钳
            // 1..6、缺省 2（导出局部钳制，不动编辑器
            // heading_level 的 C-03 无上限口径）；内容
            // renderInline ≈ 行内标记渲染，沿用
            // inlines_to_html(children)。
            let lv = crate::blocks::heading_level(node).clamp(1, 6);
            out.push_str(&format!(
                "<div class=\"note-text note-heading\"><h{lv}>{inner}</h{lv}></div>"
            ));
        }
        "quote" => {
            // 审计 E-16：原版 quote 走 div.note-text 包
            // blockquote，内容为纯文本转义（不带行内
            // 标记）、\n→<br>。
            let t = esc_html(&node.plain_text()).replace('\n', "<br>");
            out.push_str(&format!(
                "<div class=\"note-text\"><blockquote>{t}</blockquote></div>"
            ));
        }
        "callout" => {
            // 审计 E-16：原版 renderBlock 中 callout 与
            // code_block/列表同组走 note-markdown 臂
            // （export.js 显式 case，非 default 兜底、
            // 亦非 quote 的 blockquote 形态）。
            out.push_str(&format!(
                "<div class=\"note-text note-markdown\">{inner}</div>"
            ));
        }
        "todo" => {
            // 审计 E-16：原版 renderBlock 结构——
            // div.note-text.note-todo[.is-checked] 包
            // span.todo-checkbox[.is-checked]（勾选含
            // ✓）+ span.todo-text（纯文本转义、\n→<br>）。
            let c = crate::blocks::todo_checked(node);
            let t = esc_html(&node.plain_text()).replace('\n', "<br>");
            out.push_str(&format!(
                "<div class=\"note-text note-todo{}\"><span class=\"todo-checkbox{}\" aria-hidden=\"true\">{}</span><span class=\"todo-text\">{}</span></div>",
                if c { " is-checked" } else { "" },
                if c { " is-checked" } else { "" },
                if c { "✓" } else { "" },
                t
            ));
        }
        "paragraph" => {
            // 审计 E-16：原版 div.note-text.note-paragraph
            // 包 renderMarkdownBlock(节点文本)。Rust 无
            // marked 等价的字符串渲染器，内容沿用
            // inlines_to_html(children)——此为渲染器差
            // 非结构差（定论见 scope_batch6_rest E-16）。
            out.push_str(&format!(
                "<div class=\"note-text note-paragraph\">{inner}</div>"
            ));
        }
        "image" => {
            let f = crate::blocks::file_id(node).and_then(|id| files.get(&id));
            out.push_str("<figure class=\"note-media note-image\">");
            export_img_html(f, "standalone-image", out);
            out.push_str("</figure>");
        }
        "gallery" => {
            let items = export_gallery_items(node);
            out.push_str("<div class=\"note-media gallery-grid\" aria-label=\"图片画廊\">");
            if items.is_empty() {
                out.push_str("<div class=\"media-placeholder\">空画廊</div>");
            } else {
                for item in &items {
                    match item {
                        ExportGalleryItem::File(id) => {
                            export_img_html(files.get(id), "gallery-image", out)
                        }
                        // C-08/C-30：{url} 条目按原版 imageHtml
                        // 口径——过图片白名单，非空直出 img，
                        // 被拦出「图片未能导出」占位
                        ExportGalleryItem::Url(u) => {
                            let safe = mynote_core::safe_image_url(u);
                            if safe.is_empty() {
                                out.push_str(
                                    "<div class=\"media-placeholder\">图片未能导出</div>",
                                );
                            } else {
                                out.push_str(&format!(
                                    "<img class=\"gallery-image\" src=\"{}\" alt=\"图片\">",
                                    esc_html(&safe)
                                ));
                            }
                        }
                    }
                }
            }
            out.push_str("</div>");
        }
        "attachment" => {
            let f = crate::blocks::file_id(node).and_then(|id| files.get(&id));
            match f {
                Some(file) if file.mime.starts_with("image/") => {
                    out.push_str("<figure class=\"note-media note-attachment-image\">");
                    export_img_html(Some(file), "standalone-image", out);
                    out.push_str("</figure>");
                }
                _ => {
                    let name = f
                        .map(|x| x.name.clone())
                        .or_else(|| {
                            node.extra
                                .get("name")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string())
                        })
                        .unwrap_or_else(|| "附件".to_string());
                    let meta = f.map(|x| {
                        if x.size > 0 {
                            format!("{} · {}", x.mime, format_bytes(x.size))
                        } else {
                            x.mime.clone()
                        }
                    });
                    let card = format!(
                        "<span class=\"attachment-icon\">📎</span><span class=\"attachment-info\"><span class=\"attachment-name\">{}</span>{}</span><span class=\"attachment-hint\">下载附件</span>",
                        esc_html(&name),
                        meta.map(|m| format!(
                            "<span class=\"attachment-meta\">{}</span>",
                            esc_html(&m)
                        ))
                        .unwrap_or_default()
                    );
                    out.push_str("<div class=\"note-media attachment-card\">");
                    match f {
                        Some(file) => out.push_str(&format!(
                            "<a href=\"{}\" download=\"{}\">{}</a>",
                            file.data_url,
                            esc_html(&file.name),
                            card
                        )),
                        None => out.push_str(&format!(
                            "<span class=\"attachment-card-inner\">{}</span>",
                            card
                        )),
                    }
                    out.push_str("</div>");
                }
            }
        }
        "imgTextCard" => {
            let f = crate::blocks::file_id(node).and_then(|id| files.get(&id));
            let text = node.plain_text();
            out.push_str("<figure class=\"note-media img-text-card\">");
            export_img_html(f, "itc-image", out);
            out.push_str(&format!(
                "<figcaption class=\"itc-text\">{}</figcaption></figure>",
                if text.is_empty() {
                    "<span class=\"muted\">点击查看完整文本</span>".to_string()
                } else {
                    esc_html(&text)
                }
            ));
        }
        "imageTextRow" => {
            let f = crate::blocks::file_id(node).and_then(|id| files.get(&id));
            let text = node.plain_text();
            out.push_str("<figure class=\"note-media img-text-row\"><div class=\"itr-img\">");
            export_img_html(f, "itr-image", out);
            out.push_str(&format!(
                "</div><figcaption class=\"itr-text\">{}</figcaption></figure>",
                if text.is_empty() {
                    "<span class=\"muted\">点击查看完整文本</span>".to_string()
                } else {
                    esc_html(&text)
                }
            ));
        }
        "link-card" => export_link_card_html(node, false, out),
        "musicCard" => export_link_card_html(node, true, out),
        "codeBlock" => {
            out.push_str(&format!("<pre>{}</pre>", esc_html(&node.plain_text())));
        }
        "divider" => out.push_str("<div class=\"note-text\"><hr></div>"),
        "decorative_divider" => {
            let t = node
                .extra
                .get("attrs")
                .and_then(|a| a.get("text"))
                .and_then(|v| v.as_str())
                .map(|v| v.to_string())
                .unwrap_or_else(|| {
                    let raw = node.plain_text();
                    raw.trim_start_matches('-').trim_end_matches('-').trim().to_string()
                });
            out.push_str(&format!(
                "<div class=\"note-text note-decorative-divider\"><hr><span>{}</span></div>",
                esc_html(&t)
            ));
        }
        "bulleted-list" | "numbered-list" => {
            let tag = if ty == "numbered-list" { "ol" } else { "ul" };
            // E-17 ①：start>1 出 <ol start="N">（原版 marked
            // 口径：start=1 时只出 <ol>、不带属性）。
            let start = list_start(node);
            if tag == "ol" && start > 1 {
                out.push_str(&format!("<ol start=\"{start}\">"));
            } else {
                out.push_str(&format!("<{tag}>"));
            }
            if let Some(items) = &node.children {
                for it in items {
                    out.push_str(&format!(
                        "<li>{}</li>",
                        inlines_to_html(it.children.as_deref().unwrap_or(&[]))
                    ));
                }
            }
            out.push_str(&format!("</{tag}>"));
        }
        _ => {
            if !inner.is_empty() {
                out.push_str(&format!("<p>{inner}</p>"));
            }
        }
    }
}

/// 语义 Markdown 导出（原版 export.js toSemanticMarkdown 口径：
/// 标题行转义、块间 \n\n 连接、尾部单个 \n；图片/附件用解析
/// 后的 data: URL，缺失时走原版占位口径）。
pub(super) fn memo_to_markdown(
    title: &str,
    doc: &[Node],
    files: &std::collections::HashMap<String, ExportFile>,
    manifest_raw: &str,
) -> String {
    let manifest: Value = serde_json::from_str(manifest_raw).unwrap_or(Value::Null);
    let att_name = |fid: &str| -> Option<String> {
        manifest
            .get("attachments")
            .and_then(|a| a.get(fid))
            .and_then(|e| e.get("name"))
            .and_then(|n| n.as_str())
            .map(|s| s.to_string())
    };
    let mut blocks: Vec<String> = Vec::new();
    for node in doc {
        let s = block_md_str(node, files, &att_name);
        if !s.is_empty() {
            blocks.push(s);
        }
    }
    let heading = title.trim();
    if !heading.is_empty() {
        let h = heading.replace(['\r', '\n'], " ");
        let mut esc = String::new();
        for c in h.chars() {
            if "\\`*_{}[]()#+.!|>~-".contains(c) {
                esc.push('\\');
            }
            esc.push(c);
        }
        blocks.insert(0, format!("# {esc}"));
    }
    let mut out = blocks.join("\n\n");
    while out.ends_with([' ', '\n', '\t', '\r']) {
        out.pop();
    }
    out.push('\n');
    out
}

/// Markdown 图片 alt 转义（原版 markdownAlt）。
fn md_alt(value: &str) -> String {
    value
        .replace(['\r', '\n'], " ")
        .replace('\\', "\\\\")
        .replace('[', "\\[")
        .replace(']', "\\]")
        .trim()
        .to_string()
}

/// Markdown 链接 URL 处理（原版 markdownUrl：空白转 %20，
/// ()<> 百分号编码）。
fn md_url(value: &str) -> String {
    let mut out = String::new();
    for c in value.chars() {
        match c {
            c if c.is_whitespace() => out.push_str("%20"),
            '(' => out.push_str("%28"),
            ')' => out.push_str("%29"),
            '<' => out.push_str("%3C"),
            '>' => out.push_str("%3E"),
            _ => out.push(c),
        }
    }
    out
}

/// 单个附件的 Markdown 图片式（原版 imageMarkdown：有 URL 出
/// 图片式，无 URL 出 [图片：名]/[图片] 占位）。
fn md_image(
    file: Option<&ExportFile>,
    fallback_name: Option<String>,
) -> String {
    match file {
        Some(f) => format!("![{}]({})", md_alt(&f.name), md_url(&f.data_url)),
        None => match fallback_name {
            Some(n) if !n.is_empty() => format!("[图片：{}]", n),
            _ => "[图片]".to_string(),
        },
    }
}

fn block_md_str(
    node: &Node,
    files: &std::collections::HashMap<String, ExportFile>,
    att_name: &dyn Fn(&str) -> Option<String>,
) -> String {
    let ty = node.node_type.as_deref().unwrap_or("paragraph");
    let text = node.plain_text();
    match ty {
        "heading" => {
            let lv = crate::blocks::heading_level(node).clamp(1, 6);
            format!("{} {}", "#".repeat(lv as usize), text)
        }
        "todo" => {
            let checked = crate::blocks::todo_checked(node);
            format!("- [{}] {}", if checked { "x" } else { " " }, text)
        }
        "quote" => text
            .split('\n')
            .map(|l| format!("> {l}"))
            .collect::<Vec<_>>()
            .join("\n"),
        "divider" => "---".to_string(),
        "decorative_divider" => {
            let t = node
                .extra
                .get("attrs")
                .and_then(|a| a.get("text"))
                .and_then(|v| v.as_str())
                .map(|v| v.to_string());
            match t {
                Some(t) if !t.is_empty() => format!("---{t}---"),
                _ => {
                    if text.is_empty() {
                        "---".to_string()
                    } else {
                        text
                    }
                }
            }
        }
        "bulleted-list" | "numbered-list" => {
            let mut out = String::new();
            list_md(node, ty == "numbered-list", 0, &mut out);
            while out.ends_with('\n') {
                out.pop();
            }
            out
        }
        "image" => {
            let fid = crate::blocks::file_id(node);
            let f = fid.as_ref().and_then(|id| files.get(id));
            md_image(f, fid.as_ref().and_then(|id| att_name(id)))
        }
        "gallery" => export_gallery_items(node)
            .iter()
            .map(|item| match item {
                ExportGalleryItem::File(id) => md_image(files.get(id), att_name(id)),
                // C-08/C-30：{url} 条目按原版 imageMarkdown
                // 口径——过图片白名单，非空出 ![图片](url)，
                // 被拦出 [图片：图片]（无名条目的字面输出）
                ExportGalleryItem::Url(u) => {
                    let safe = mynote_core::safe_image_url(u);
                    if safe.is_empty() {
                        "[图片：图片]".to_string()
                    } else {
                        format!("![图片]({})", md_url(&safe))
                    }
                }
            })
            .collect::<Vec<_>>()
            .join("\n"),
        "attachment" => {
            let fid = crate::blocks::file_id(node);
            let f = fid.as_ref().and_then(|id| files.get(id));
            match f {
                Some(file) if file.mime.starts_with("image/") => {
                    md_image(Some(file), None)
                }
                _ => {
                    let name = f
                        .map(|x| x.name.clone())
                        .or_else(|| fid.as_ref().and_then(|id| att_name(id)))
                        .or_else(|| {
                            node.extra
                                .get("name")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string())
                        })
                        .unwrap_or_else(|| "附件".to_string());
                    format!("📎 {name}")
                }
            }
        }
        "imgTextCard" | "imageTextRow" => {
            let fid = crate::blocks::file_id(node);
            let f = fid.as_ref().and_then(|id| files.get(id));
            let img = md_image(f, fid.as_ref().and_then(|id| att_name(id)));
            let caption = text.trim();
            if caption.is_empty() {
                img
            } else {
                format!("{img}\n\n说明：{caption}")
            }
        }
        "link-card" | "musicCard" => {
            let url = node
                .extra
                .get("url")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_string();
            if !(url.starts_with("http://") || url.starts_with("https://")) {
                return text;
            }
            let label = node
                .extra
                .get("meta")
                .and_then(|m| m.get("title").or_else(|| m.get("name")))
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .unwrap_or(&url)
                .replace('\\', "\\\\")
                .replace('[', "\\[")
                .replace(']', "\\]");
            format!("[{}]({})", label, md_url(&url))
        }
        // paragraph（含存 md 源码的代码/列表/标注段）与
        // code_block/callout 类型：原版均是正文原样
        _ => text,
    }
}

/// 列表项自身行内内容的 Markdown 源形（审计 E-17 ②③）。
/// 原版列表块存全量源文本、导出直出（export.js
/// blockToMarkdown 对 ordered/unordered_list 返回原文），故
/// 本项文本须是源形：行内标记按字面包裹对折回（口径同 core
/// inline_editor 的字面折叠规范，其规格源出原版 use-slash
/// 行内命令包裹对）——粗 **、斜 *、删 ~~、码 `（文本含
/// 反引号时升级双反引号定界、首尾贴反引号/空格时内衬空格）、
/// 链接 [文字](url)（url 含 ) 或空白时尖角形、链接文字转义
/// \ [ ] 且换行折空格）；高亮 == 本就以字面存于文本、原样
/// 透传；下划线在原版无字面包裹对，折纯文本（同该规范的
/// 已知口径差）。子列表不在本行内——由 list_md 递归单独
/// 成行（③：plain_text 全递归会把子项文本拼进父项行尾，
/// 造成重复）。
fn list_item_md(item: &Node) -> String {
    let mut out = String::new();
    if item.text.is_some() {
        md_inline_node(item, false, &mut out);
    }
    if let Some(kids) = &item.children {
        for k in kids {
            if matches!(
                k.node_type.as_deref(),
                Some("bulleted-list") | Some("numbered-list")
            ) {
                continue;
            }
            md_inline_node(k, false, &mut out);
        }
    }
    out
}

/// 行内节点 → Markdown 源形（单节点递归，`in_link` 时文本
/// 按链接文字口径转义）。
fn md_inline_node(node: &Node, in_link: bool, out: &mut String) {
    if node.block_type() == Some("link") {
        let url = node.extra.get("url").and_then(|v| v.as_str()).unwrap_or("");
        out.push('[');
        if let Some(kids) = &node.children {
            for k in kids {
                md_inline_node(k, true, out);
            }
        }
        out.push_str("](");
        if url.contains([')', ' ', '\t', '\n']) {
            out.push('<');
            out.push_str(url);
            out.push('>');
        } else {
            out.push_str(url);
        }
        out.push(')');
        return;
    }
    if let Some(text) = &node.text {
        if text.is_empty() {
            return;
        }
        let body = if in_link {
            md_link_text(text)
        } else {
            text.clone()
        };
        let (open, close) = md_wraps(node, &body);
        out.push_str(&open);
        out.push_str(&body);
        out.push_str(&close);
        return;
    }
    if let Some(kids) = &node.children {
        for k in kids {
            md_inline_node(k, in_link, out);
        }
    }
}

/// 标记折字面的规范包裹对（顺序 粗→斜→删→码，闭序镜像；
/// 下划线除外——原版无字面包裹对）。
fn md_wraps(node: &Node, text: &str) -> (String, String) {
    let mark = |k: &str| node.extra.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
    let mut open = String::new();
    let mut close = String::new();
    if mark("bold") {
        open.push_str("**");
        close.insert_str(0, "**");
    }
    if mark("italic") {
        open.push('*');
        close.insert(0, '*');
    }
    if mark("strikethrough") {
        open.push_str("~~");
        close.insert_str(0, "~~");
    }
    if mark("code") {
        if text.contains('`') {
            let pad = text.starts_with(['`', ' ']) || text.ends_with(['`', ' ']);
            if pad {
                open.push_str("`` ");
                close.insert_str(0, " ``");
            } else {
                open.push_str("``");
                close.insert_str(0, "``");
            }
        } else {
            open.push('`');
            close.insert(0, '`');
        }
    }
    (open, close)
}

/// 链接文字的字面转义（原版 inline_link 口径）：`\`、`[`、
/// `]` 反斜杠转义，换行折成空格。
fn md_link_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '\\' | '[' | ']' => {
                out.push('\\');
                out.push(c);
            }
            '\n' | '\r' => out.push(' '),
            _ => out.push(c),
        }
    }
    out
}

/// 真实列表节点的 Markdown（嵌套按深度缩进）。有序编号以
/// 本节点 attrs.start 为初始计数（E-17 ①；嵌套子列表递归
/// 时各用自身 start），无 start 按 1。
fn list_md(node: &Node, ordered: bool, depth: usize, out: &mut String) {
    if let Some(items) = &node.children {
        let start = list_start(node);
        for (i, item) in items.iter().enumerate() {
            let mark = if ordered {
                format!("{}.", start + i as u64)
            } else {
                "-".to_string()
            };
            out.push_str(&format!(
                "{}{} {}\n",
                "  ".repeat(depth),
                mark,
                list_item_md(item)
            ));
            if let Some(subs) = &item.children {
                for s in subs {
                    match s.node_type.as_deref() {
                        Some("bulleted-list") => list_md(s, false, depth + 1, out),
                        Some("numbered-list") => list_md(s, true, depth + 1, out),
                        _ => {}
                    }
                }
            }
        }
    }
}

/// 导出文件名（原版 toFilename 口径：非法字符转 _、去尾部
/// 点/空格、截 80 字、空则「笔记」）。
pub(super) fn export_filename(title: &str, ext: &str) -> String {
    let mut base: String = title
        .trim()
        .chars()
        .map(|c| {
            if matches!(c, '\\' | '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|')
                || (c as u32) < 0x20
            {
                '_'
            } else {
                c
            }
        })
        .collect();
    while base.ends_with(['.', ' ']) {
        base.pop();
    }
    // 审计 E-13：截断按 UTF-16 码元累计至 80（原版 JS
    // slice(0, 80) 口径），非 Unicode 标量计数；跨界的
    // 星平面字符整字丢弃（JS 会留下孤代理半字，Rust
    // String 无法表示、文件名落盘时亦被系统替换，
    // 无实际差）。
    let mut units = 0usize;
    let mut truncated = String::new();
    for c in base.chars() {
        let w = c.len_utf16();
        if units + w > 80 {
            break;
        }
        units += w;
        truncated.push(c);
    }
    let base = truncated;
    let base = if base.is_empty() {
        "笔记".to_string()
    } else {
        base
    };
    format!("{base}.{ext}")
}

/// 浏览器下载一段文本（原版下载口径：a[download] 挂进 body
/// 再 click、随后移除，object URL 延迟 1s 才撤销——游离锚点
/// 的 click 在 Safari 上可能不触发下载，同步撤销也会掐断
/// 刚启动的下载）。
pub(super) fn download_text(filename: &str, text: &str, mime: &str) {
    let Some(window) = web_sys::window() else {
        return;
    };
    let Some(document) = window.document() else {
        return;
    };
    let parts = js_sys::Array::new();
    parts.push(&wasm_bindgen::JsValue::from_str(text));
    let opts = web_sys::BlobPropertyBag::new();
    opts.set_type(mime);
    let Ok(blob) = web_sys::Blob::new_with_str_sequence_and_options(&parts, &opts) else {
        return;
    };
    let Ok(url) = web_sys::Url::create_object_url_with_blob(&blob) else {
        return;
    };
    if let Ok(a) = document.create_element("a") {
        if let Ok(a) = a.dyn_into::<web_sys::HtmlAnchorElement>() {
            a.set_href(&url);
            a.set_download(filename);
            let _ = a.set_attribute("style", "display:none");
            if let Some(body) = document.body() {
                let _ = body.append_child(&a);
            }
            a.click();
            a.remove();
            let revoke = wasm_bindgen::closure::Closure::once_into_js(move || {
                let _ = web_sys::Url::revoke_object_url(&url);
            });
            let _ = window.set_timeout_with_callback_and_timeout_and_arguments_0(
                revoke.unchecked_ref(),
                1000,
            );
        }
    }
}

/// 编辑器副行时间格式（对齐原版 timeAgo 今日形态：24h 设备
/// H:mm，否则上午/下午 h:mm）。
pub(crate) fn time_label(ms: i64) -> String {
    let d = js_sys::Date::new(&wasm_bindgen::JsValue::from_f64(ms as f64));
    let h = d.get_hours();
    let m = d.get_minutes();
    if crate::list::is_24h() {
        return format!("{h}:{m:02}");
    }
    let (ap, h12) = if h < 12 {
        ("上午", if h == 0 { 12 } else { h })
    } else {
        ("下午", if h == 12 { 12 } else { h - 12 })
    };
    format!("{ap} {h12}:{m:02}")
}

#[cfg(test)]
mod tests {
    use super::export_filename;

    fn base_of(title: &str) -> String {
        export_filename(title, "md")
            .trim_end_matches(".md")
            .to_string()
    }

    /// E-13：截断以 UTF-16 码元计——纯 BMP 长标题截到
    /// 恰 80 码元（与 JS slice(0, 80) 一致）。
    #[test]
    fn filename_truncates_at_80_utf16_units_bmp() {
        let base = base_of(&"题".repeat(100));
        assert_eq!(base.encode_utf16().count(), 80);
    }

    /// E-13：星平面字符每字 2 码元——79 码元后跟一个
    /// emoji 时整字丢弃（79 码元收口），不留半字、
    /// 不越界；恰满 80 码元时收全。
    #[test]
    fn filename_truncates_at_80_utf16_units_astral() {
        let t = format!("{}{}", "a".repeat(79), "😀".repeat(10));
        let base = base_of(&t);
        assert_eq!(base.encode_utf16().count(), 79);
        assert!(!base.contains('😀'));
        let t2 = format!("{}{}", "a".repeat(78), "😀".repeat(10));
        let base2 = base_of(&t2);
        assert_eq!(base2.encode_utf16().count(), 80);
        assert_eq!(base2.matches('😀').count(), 1);
    }

    /// 既有口径不回归：非法字符转 _、空名回退。
    #[test]
    fn filename_sanitize_and_fallback_unchanged() {
        assert_eq!(base_of("a/b:c"), "a_b_c");
        assert_eq!(base_of("   "), "笔记");
    }

    /// E-16：快照缺失时 block_html 兜底四臂 + callout
    /// 与原版 renderBlock 结构同构。
    #[test]
    fn fallback_block_html_matches_render_block() {
        use super::{doc_to_html, ExportAssets};
        use mynote_core::Node;
        let doc: Vec<Node> = serde_json::from_str(
            r#"[
              {"type":"paragraph","children":[{"text":"正文"}]},
              {"type":"heading","attrs":{"level":3},"children":[{"text":"标题"}]},
              {"type":"heading","attrs":{"level":9},"children":[{"text":"超界"}]},
              {"type":"quote","children":[{"text":"引\n言"}]},
              {"type":"todo","attrs":{"checked":true},"children":[{"text":"待办"}]},
              {"type":"todo","attrs":{"checked":false},"children":[{"text":"未办"}]},
              {"type":"callout","children":[{"text":"提示"}]}
            ]"#,
        )
        .unwrap();
        let assets = ExportAssets {
            css: String::new(),
            snapshot_html: None,
            chrome_html: None,
            header_height: 0.0,
            dark: false,
            vars: Vec::new(),
        };
        let html = doc_to_html(
            "t",
            &doc,
            "",
            None,
            "",
            &assets,
            &std::collections::HashMap::new(),
        );
        assert!(html.contains(
            "<div class=\"note-text note-paragraph\">正文</div>"
        ));
        assert!(html.contains(
            "<div class=\"note-text note-heading\"><h3>标题</h3></div>"
        ));
        // level 钳 1..6（原版 renderBlock 口径）
        assert!(html.contains("<h6>超界</h6>"));
        assert!(html.contains(
            "<div class=\"note-text\"><blockquote>引<br>言</blockquote></div>"
        ));
        assert!(html.contains(
            "<div class=\"note-text note-todo is-checked\"><span class=\"todo-checkbox is-checked\" aria-hidden=\"true\">✓</span><span class=\"todo-text\">待办</span></div>"
        ));
        assert!(html.contains(
            "<div class=\"note-text note-todo\"><span class=\"todo-checkbox\" aria-hidden=\"true\"></span><span class=\"todo-text\">未办</span></div>"
        ));
        assert!(html.contains(
            "<div class=\"note-text note-markdown\">提示</div>"
        ));
    }

    /// E-17 ②③：真实列表节点导出——与 measure_e17_list_export
    /// 同夹具（有序三项 + 无序父项含加粗/链接、二级嵌套两子项、
    /// 次项）。行内标记须按源文本口径保留（原版列表块存全量
    /// 源文本、blockToMarkdown 直出），嵌套子项只在自身行出现、
    /// 不得拼进父项行尾。本夹具的 numbered-list 无 attrs.start
    /// → 按 1 起编（① 的 start 承载见
    /// list_export_honors_attrs_start）。
    #[test]
    fn list_export_keeps_inline_marks_and_nested_items_on_own_lines() {
        use super::memo_to_markdown;
        use mynote_core::Node;
        let doc: Vec<Node> = serde_json::from_str(
            r#"[
              {"type":"numbered-list","id":"la","children":[
                {"type":"list-item","id":"la1","children":[{"text":"甲项"}]},
                {"type":"list-item","id":"la2","children":[{"text":"乙项"}]},
                {"type":"list-item","id":"la3","children":[{"text":"丙项"}]}
              ]},
              {"type":"bulleted-list","id":"lb","children":[
                {"type":"list-item","id":"lb1","children":[
                  {"text":"父项"},
                  {"text":"粗体","bold":true},
                  {"text":"与"},
                  {"type":"link","url":"https://example.com","children":[{"text":"链接"}]},
                  {"type":"bulleted-list","id":"lb1s","children":[
                    {"type":"list-item","id":"lb1s1","children":[{"text":"子项一"}]},
                    {"type":"list-item","id":"lb1s2","children":[{"text":"子项二"}]}
                  ]}
                ]},
                {"type":"list-item","id":"lb2","children":[{"text":"次项"}]}
              ]}
            ]"#,
        )
        .unwrap();
        let md = memo_to_markdown(
            "列表实测",
            &doc,
            &std::collections::HashMap::new(),
            "{}",
        );
        assert_eq!(
            md,
            "# 列表实测\n\n1. 甲项\n2. 乙项\n3. 丙项\n\n- 父项**粗体**与[链接](https://example.com)\n  - 子项一\n  - 子项二\n- 次项\n"
        );
    }

    /// E-17 ①：attrs.start 全链——存储 JSON 带 start=3 的
    /// numbered-list（measure 夹具有序三项）导出逐字 3/4/5；
    /// 序列化往返 start 不丢；无 start 的存量节点序列化不
    /// 冒出 start 字段（字节不变）、导出按 1 起编；嵌套子
    /// 列表各用自身 start。
    #[test]
    fn list_export_honors_attrs_start() {
        use super::memo_to_markdown;
        use mynote_core::Node;
        let raw = r#"[
          {"type":"numbered-list","id":"la","attrs":{"start":3},"children":[
            {"type":"list-item","id":"la1","children":[{"text":"甲项"}]},
            {"type":"list-item","id":"la2","children":[{"text":"乙项"}]},
            {"type":"list-item","id":"la3","children":[{"text":"丙项"}]}
          ]},
          {"type":"numbered-list","id":"ln","children":[
            {"type":"list-item","id":"ln1","children":[
              {"text":"外层"},
              {"type":"numbered-list","id":"ln1s","attrs":{"start":5},"children":[
                {"type":"list-item","id":"ln1s1","children":[{"text":"内一"}]},
                {"type":"list-item","id":"ln1s2","children":[{"text":"内二"}]}
              ]}
            ]}
          ]}
        ]"#;
        let doc: Vec<Node> = serde_json::from_str(raw).unwrap();
        // 存储往返：start 字段逐字保留
        let back = serde_json::to_string(&doc).unwrap();
        assert!(back.contains(r#""start":3"#), "roundtrip lost start: {back}");
        assert!(back.contains(r#""start":5"#), "roundtrip lost nested start: {back}");
        let md = memo_to_markdown(
            "列表实测",
            &doc,
            &std::collections::HashMap::new(),
            "{}",
        );
        assert_eq!(
            md,
            "# 列表实测\n\n3. 甲项\n4. 乙项\n5. 丙项\n\n1. 外层\n  5. 内一\n  6. 内二\n"
        );
        // 无 start 存量节点：序列化不回写多余字段、导出按 1
        let plain: Vec<Node> = serde_json::from_str(
            r#"[{"type":"numbered-list","id":"lx","children":[
              {"type":"list-item","id":"lx1","children":[{"text":"首项"}]}
            ]}]"#,
        )
        .unwrap();
        let back2 = serde_json::to_string(&plain).unwrap();
        assert!(!back2.contains("start"), "phantom start written: {back2}");
        assert!(!back2.contains("attrs"), "phantom attrs written: {back2}");
        let md2 = memo_to_markdown("", &plain, &std::collections::HashMap::new(), "{}");
        assert_eq!(md2, "1. 首项\n");
    }

    /// E-17 ① HTML 导出：start>1 出 <ol start="N">（marked
    /// 口径），start=1/缺失只出 <ol>。
    #[test]
    fn list_html_export_honors_attrs_start() {
        use super::{doc_to_html, ExportAssets};
        use mynote_core::Node;
        let doc: Vec<Node> = serde_json::from_str(
            r#"[
              {"type":"numbered-list","id":"la","attrs":{"start":3},"children":[
                {"type":"list-item","id":"la1","children":[{"text":"甲项"}]}
              ]},
              {"type":"numbered-list","id":"lb","children":[
                {"type":"list-item","id":"lb1","children":[{"text":"首项"}]}
              ]}
            ]"#,
        )
        .unwrap();
        let assets = ExportAssets {
            css: String::new(),
            snapshot_html: None,
            chrome_html: None,
            header_height: 0.0,
            dark: false,
            vars: Vec::new(),
        };
        let html = doc_to_html(
            "t",
            &doc,
            "",
            None,
            "",
            &assets,
            &std::collections::HashMap::new(),
        );
        assert!(html.contains("<ol start=\"3\">"), "missing start attr: {html}");
        assert!(html.contains("<ol><li>首项</li></ol>"), "start=1 must stay bare: {html}");
    }

    /// E-17 ② 补充：列表项内其余行内标记的源形折回——斜 *、
    /// 删 ~~、行内码 `（与 core 字面折叠规范同口径）；链接
    /// url 含 ) 时用尖角形（原版 inline_link 插入口径）。
    #[test]
    fn list_export_folds_other_inline_marks() {
        use super::memo_to_markdown;
        use mynote_core::Node;
        let doc: Vec<Node> = serde_json::from_str(
            r#"[
              {"type":"bulleted-list","id":"lb","children":[
                {"type":"list-item","id":"lb1","children":[
                  {"text":"斜","italic":true},
                  {"text":"删","strikethrough":true},
                  {"text":"码","code":true},
                  {"type":"link","url":"https://example.com/a(b)","children":[{"text":"链"}]}
                ]}
              ]}
            ]"#,
        )
        .unwrap();
        let md = memo_to_markdown(
            "",
            &doc,
            &std::collections::HashMap::new(),
            "{}",
        );
        assert_eq!(
            md,
            "- *斜*~~删~~`码`[链](<https://example.com/a(b)>)\n"
        );
    }
}

