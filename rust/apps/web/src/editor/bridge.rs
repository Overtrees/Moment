//! JS 桥：EDITOR_JS（contenteditable 事件采集、光标数学、
//! 全局监听登记册 __mnBridgeCleanup）与编辑器卸载的同步
//! 清理接线（sync_editor_cleanup）。

use super::*;

pub(super) const EDITOR_JS: &str = r#"
  const root = document.getElementById('editor-root');
  if (!root || root.__mnBound) return null;
  root.__mnBound = true;

  // 桥的全局登记册（页面副作用审计·泄漏 2 根治）：本桥除
  // root 元素级监听外，还挂 document/window/visualViewport
  // 级监听与 20s 同步定时器。root.__mnBound 是元素级守卫，
  // 跨挂载（新 root）不防重复装——旧实现全部匿名登记、无任
  // 何恢复路径，进出编辑页 N 次净计数线性累积（实测
  // visibilitychange 1→2→3、selectionchange 2→4→6、
  // setInterval 1→2→3），残留处理器还会对已摘除 root 周期
  // 性跑 collectSync 向死通道发送。故全部全局登记改走
  // onGlobal 记入 bridgeDisposers，并安装幂等清理
  // window.__mnBridgeCleanup：挂载入口先调上一代清理（任意
  // 时刻至多一套全局监听存活），编辑器卸载时 Rust 侧
  // sync_editor_cleanup 同步直调本清理——监听/定时器摘除、
  // 桥的 window 入口（__mnInline 等）一并置 null。
  if (typeof window.__mnBridgeCleanup === 'function') window.__mnBridgeCleanup();
  const bridgeDisposers = [];
  const onGlobal = (target, type, fn, opts) => {
    target.addEventListener(type, fn, opts);
    bridgeDisposers.push(() => target.removeEventListener(type, fn, opts));
  };
  window.__mnBridgeCleanup = () => {
    window.__mnBridgeCleanup = null;
    for (const d of bridgeDisposers) { try { d(); } catch (_) {} }
    bridgeDisposers.length = 0;
    window.__mnInline = null;
    window.__mnApplyLink = null;
    window.__mnFocus = null;
    window.__mnFocusAtMount = null;
    window.__mnSetHtml = null;
    window.__mnSyncAll = null;
    window.__mnStripSlash = null;
    window.__mnSlashAnchor = null;
    window.__mnXSel = null;
    if (window.CSS && CSS.highlights) CSS.highlights.delete('mn-xsel');
  };

  let composing = false;
  root.addEventListener('compositionstart', () => { composing = true; });
  root.addEventListener('compositionend', (e) => {
    composing = false;
    // 组字结束显式重放输入管线（批 1 B-11，原版双跑口径）：
    // 组字期间的 input 被 composing 守卫挡下，部分 WebKit 在
    // compositionend 后不补发 input——斜杠检测/智能前缀/音乐
    // 复检会漏掉已提交文本。这里以组字目标块直调 processInput
    // （具名函数声明、前向引用靠提升）；浏览器随后补发的
    // input 再跑一遍同管线，各项均为幂等复检（原版同为双跑）。
    const el = e.target && e.target.closest ? e.target.closest('[data-bid]') : null;
    if (el) processInput(el);
  });

  // 音乐胶囊粘贴事务（批 1 B-9）与最近聚焦块：beforeinput
  // 快照、paste 分流、input 回收三处共用，声明在此聚合。
  let lastFocusBid = null;
  let musicPasteTx = null;

  const editableOf = (e) => e.target.closest ? e.target.closest('[data-bid]') : null;

  function fragHtml(range) {
    const d = document.createElement('div');
    d.appendChild(range.cloneContents());
    return d.innerHTML;
  }
  function caretInfo(el) {
    const sel = window.getSelection();
    if (!sel.rangeCount) return { offset: 0, collapsed: true, beforeHtml: '', afterHtml: el.innerHTML };
    const range = sel.getRangeAt(0);
    if (!el.contains(range.startContainer)) {
      return { offset: 0, collapsed: range.collapsed, beforeHtml: '', afterHtml: el.innerHTML };
    }
    const pre = range.cloneRange();
    pre.selectNodeContents(el);
    pre.setEnd(range.startContainer, range.startOffset);
    const post = range.cloneRange();
    post.selectNodeContents(el);
    post.setStart(range.endContainer, range.endOffset);
    return { offset: pre.toString().length, collapsed: range.collapsed, beforeHtml: fragHtml(pre), afterHtml: fragHtml(post) };
  }
  // 可编辑块序列（DOM 序 = 阅读序：单栏自上而下、双栏左栏
  // 后右栏，与原版 getBlocks 同序）。原子块不是
  // contenteditable，天然不在列内——原版单宿主里方向键同样
  // 跳过不可编辑岛。
  function editableBlocks() {
    return Array.from(root.querySelectorAll('[data-bid]')).filter((n) => n.isContentEditable);
  }
  function setCaretEdge(el, toEnd) {
    el.focus();
    const r = document.createRange();
    r.selectNodeContents(el);
    r.collapse(!toEnd);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
  }
  function setCaretByPoint(el, x, y) {
    el.focus();
    if (!document.caretRangeFromPoint) return false;
    const range = document.caretRangeFromPoint(x, y);
    if (!range || !el.contains(range.startContainer)) return false;
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    return true;
  }
  // 光标所在行的矩形：折叠 range 在块尾（元素偏移形）时
  // getBoundingClientRect 可能全零，借相邻字符/子节点的矩
  // 形兜底（字符矩形高 ≈ 行高，x 差至多一个字宽）。
  function caretLineRect(el) {
    const sel = window.getSelection();
    if (!sel.rangeCount) return null;
    const range = sel.getRangeAt(0);
    let rect = range.getBoundingClientRect();
    if (rect && (rect.height || rect.top)) return rect;
    try {
      const probe = range.cloneRange();
      const node = range.endContainer;
      if (node.nodeType === 3) {
        if (range.endOffset > 0) probe.setStart(node, range.endOffset - 1);
        else if (node.textContent.length) probe.setEnd(node, 1);
        else return null;
      } else {
        const kids = el.childNodes;
        if (!kids.length) return null;
        probe.selectNode(kids[range.endOffset > 0 ? range.endOffset - 1 : 0]);
      }
      rect = probe.getBoundingClientRect();
      if (rect && (rect.height || rect.top)) return rect;
    } catch (_) {}
    return null;
  }
  function textAfterCaret(el) {
    const sel = window.getSelection();
    if (!sel.rangeCount) return '';
    const range = sel.getRangeAt(0);
    if (!el.contains(range.endContainer)) return '';
    const post = range.cloneRange();
    post.selectNodeContents(el);
    post.setStart(range.endContainer, range.endOffset);
    return post.toString();
  }
  // 方向键跨块（原版单宿主天然跨块 + editor.js:55 的跨栏
  // Left/Right；分块架构在此补齐，调优评估候选 1 口径）：
  // Left/Right 只在块首/块尾触发，落到相邻可编辑块的尾/首；
  // Up/Down 只在首行/末行触发，按光标 x 在目标块末/首行
  // hit-test 落点。修饰键/选区/斜杠面板时一律放行原生。
  // 块内视觉行盒（批 1 B-12）：全内容 Range 的逐行矩形，
  // 同 top 的片段合并为一行；空块/无矩形时以块自身 rect
  // 兜底一行。首/末行判定与 hit-test 纵坐标都以此为准，
  // 不再用行高比例阈值猜测、也不借源块行高量目标块。
  function lineBoxes(el) {
    const r = document.createRange();
    r.selectNodeContents(el);
    const rects = r.getClientRects();
    const boxes = [];
    for (let i = 0; i < rects.length; i++) {
      const rc = rects[i];
      if (!rc.height && !rc.width) continue;
      const last = boxes[boxes.length - 1];
      if (last && Math.abs(rc.top - last.top) < 2) {
        last.bottom = Math.max(last.bottom, rc.bottom);
      } else {
        boxes.push({ top: rc.top, bottom: rc.bottom });
      }
    }
    if (!boxes.length) {
      const er = el.getBoundingClientRect();
      boxes.push({ top: er.top, bottom: er.bottom });
    }
    return boxes;
  }
  // 纵向移动的目标列会话（B-12）：原版单宿主里浏览器在连续
  // Up/Down 间保持起始列（desired-x），分块架构下每次跨块
  // 跳跃的编程式落点都会把浏览器目标列重置为落点 x——实测
  // 「长-短-长」连按两次 Up：原版第二跳落首块末行行尾（目
  // 标列超出行宽取行尾），旧桥落短块落点 x 对应的中段。故
  // 桥内记会话目标列：序列首按以当前光标 x 立列，跨块跳跃
  // 后续按全程手动按此列 hit-test；非方向键/点按/输入即散。
  let arrowGoalX = null;
  let arrowManual = false;
  function resetArrowGoal() { arrowGoalX = null; arrowManual = false; }

  function crossBlockArrow(e, el) {
    if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return false;
    if (document.getElementById('slash-panel')) return false;
    const sel = window.getSelection();
    if (!sel.rangeCount || !sel.isCollapsed) return false;
    const blocks = editableBlocks();
    const idx = blocks.indexOf(el);
    if (idx < 0) return false;
    const key = e.key;
    if (key === 'ArrowLeft' || key === 'ArrowRight') {
      if (key === 'ArrowLeft') {
        if (caretInfo(el).offset !== 0 || idx === 0) return false;
        e.preventDefault();
        setCaretEdge(blocks[idx - 1], true);
      } else {
        if (textAfterCaret(el) !== '' || idx === blocks.length - 1) return false;
        e.preventDefault();
        setCaretEdge(blocks[idx + 1], false);
      }
      dioxus.send(JSON.stringify({ op: 'caretMove', dir: key === 'ArrowLeft' ? 'left' : 'right', id: el.dataset.bid }));
      return true;
    }
    const rect = caretLineRect(el);
    if (!rect) return false;
    const up = key === 'ArrowUp';
    const boxes = lineBoxes(el);
    let li = boxes.findIndex((b) => rect.top >= b.top - 1 && rect.top < b.bottom + 1);
    if (li < 0) li = rect.top < boxes[0].top ? 0 : boxes.length - 1;
    if (arrowGoalX === null) arrowGoalX = rect.left;
    const gx = arrowGoalX;
    const inBlock = up ? li > 0 : li < boxes.length - 1;
    if (inBlock) {
      // 块内行间移动：未跳跃过时放行原生（浏览器目标列与
      // gx 同值、结果等价）；已跳跃过则按会话目标列手动
      // 落点，防止以跳跃落点 x 为新目标列逐跳漂移。
      if (!arrowManual) return false;
      e.preventDefault();
      const b = boxes[up ? li - 1 : li + 1];
      if (!setCaretByPoint(el, gx, (b.top + b.bottom) / 2)) setCaretEdge(el, !up);
      return true;
    }
    const ti = up ? idx - 1 : idx + 1;
    if (ti < 0 || ti >= blocks.length) return false;
    e.preventDefault();
    const target = blocks[ti];
    const tb = lineBoxes(target);
    const line = up ? tb[tb.length - 1] : tb[0];
    if (!setCaretByPoint(target, gx, (line.top + line.bottom) / 2)) setCaretEdge(target, !up);
    arrowManual = true;
    dioxus.send(JSON.stringify({ op: 'caretMove', dir: up ? 'up' : 'down', id: el.dataset.bid }));
    return true;
  }
  function stripSlash(el) {
    // 剥离整个斜杠令牌：从 '/' 所在位置起、令牌长度内的全部
    // 文字（斜杠审计 S1/S2：原版 token 模型整体剥离；只删 '/'
    // 会把过滤词残留在正文里落库）。位置与长度由输入监听在开
    // 面板时记在 dataset（块内任意位置可触发）；缺失时兜底用
    // 「块首到光标」。剥离结果记在 el.__mnStrip 供行内命令按
    // 偏移修正选区（选区是在剥离前捕获的）。
    let start = parseInt(el.dataset.slashPos || 'NaN', 10);
    let len = parseInt(el.dataset.slashLen || 'NaN', 10);
    if (isNaN(start) || isNaN(len) || start < 0 || len <= 0) {
      // 无令牌记录时按输入监听同口径在光标前找令牌；找不到就
      // 不剥离——旧兜底「块首到光标」会在无斜杠场景误删正文
      // （__mnInline 直调时实测吃掉首字、包裹整体偏移一字）。
      const c = caretInfo(el);
      const before = (el.innerText || '').replace(/\n$/, '').slice(0, c.offset);
      const at = before.lastIndexOf('/');
      if (at < 0 || /\s/.test(before.slice(at + 1))) {
        el.__mnStrip = { pos: 0, len: 0 };
        return;
      }
      start = at;
      len = c.offset - at;
    }
    let remain = len;
    let skipped = 0;
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n = walker.nextNode();
    while (n && remain > 0) {
      const L = n.textContent.length;
      if (skipped + L <= start) { skipped += L; n = walker.nextNode(); continue; }
      const from = Math.max(0, start - skipped);
      const cut = Math.min(remain, L - from);
      n.textContent = n.textContent.slice(0, from) + n.textContent.slice(from + cut);
      remain -= cut;
      skipped += L;
      n = walker.nextNode();
    }
    el.__mnStrip = { pos: start, len: len - remain };
    delete el.dataset.slashPos;
    delete el.dataset.slashLen;
  }
  function moveSel(panel, dir) {
    const items = Array.from(panel.querySelectorAll('.slash-row'));
    if (!items.length) return;
    let i = items.findIndex((x) => x.classList.contains('sel'));
    items.forEach((x) => x.classList.remove('sel'));
    i = (i + dir + items.length) % items.length;
    items[i].classList.add('sel');
    items[i].scrollIntoView({ block: 'nearest' });
  }
  function collectSync() {
    const map = {};
    root.querySelectorAll('[data-bid]').forEach((el) => {
      // md 源编辑态由 mdText 消息单独同步（innerText），不走 HTML 同步
      if (el.dataset.btype === 'mdsrc') return;
      // 音乐输入胶囊的文本是占位/待解析 URL，不落模型（节点无 children）
      if (el.dataset.btype === 'musicInput') return;
      map[el.dataset.bid] = el.innerHTML;
    });
    return map;
  }

  // ═══ 跨块选区 ═══
  // 原版 .editor-body 是单个 contentEditable 宿主，浏览器原生
  // 选区可跨任意块（拖拽 / Shift+方向 / Ctrl+A / 编程 Range 均
  // 已活体实测）。Rust 版每块一个 CE 宿主，Chrome 把原生选区
  // 钳在宿主内——桥内维护虚拟选区 xsel（端点 = bid + UTF-16
  // 偏移，口径同 caretInfo），CSS Custom Highlight 绘画，编辑
  // 动作经 replaceRange 模型 op 落地；原生选区同时收拢到锚
  // 点避免双重选区显示。源码态块（mdsrc/codeBlock/musicInput）
  // 不作端点、不可被跨越：其内容是瞬时编辑态、模型 op 不感
  // 知未同步文本。
  const xselHl = (window.CSS && CSS.highlights && window.Highlight) ? new Highlight() : null;
  if (xselHl) CSS.highlights.set('mn-xsel', xselHl);
  const xselStyle = document.createElement('style');
  xselStyle.textContent = '::highlight(mn-xsel) { background-color: rgba(0, 105, 217, 0.30); }';
  document.head.appendChild(xselStyle);
  bridgeDisposers.push(() => xselStyle.remove());
  let xsel = null; // {a:{bid,off}, f:{bid,off}, fromStart, toEnd}
  const isSrcBlock = (el) => !!el && (el.dataset.btype === 'mdsrc' || el.dataset.btype === 'codeBlock' || el.dataset.btype === 'musicInput');
  function blockText(el) {
    const r = document.createRange();
    r.selectNodeContents(el);
    return r.toString();
  }
  // 块内 UTF-16 偏移（口径同 caretInfo：文本长度 + <br> 计 1）
  // → Range 端点 [node, off]
  function rangePoint(el, off) {
    let rem = Math.max(0, off);
    let lastText = null;
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    let n;
    while ((n = walker.nextNode())) {
      if (n.nodeType === 3) {
        lastText = n;
        if (rem <= n.textContent.length) return [n, rem];
        rem -= n.textContent.length;
      } else if (n.tagName === 'BR') {
        const parent = n.parentNode;
        const idx = Array.prototype.indexOf.call(parent.childNodes, n);
        if (rem === 0) return [parent, idx];
        rem -= 1;
        if (rem === 0) return [parent, idx + 1];
      }
    }
    return lastText ? [lastText, lastText.textContent.length] : [el, 0];
  }
  function rangeOf(el, from, to) {
    const r = document.createRange();
    const a = rangePoint(el, from);
    const b = rangePoint(el, to);
    r.setStart(a[0], a[1]);
    r.setEnd(b[0], b[1]);
    return r;
  }
  function posFromNode(el, node, off) {
    const r = document.createRange();
    r.selectNodeContents(el);
    try { r.setEnd(node, off); } catch (_) { return 0; }
    return r.toString().length;
  }
  function nodeBlockEl(node) {
    if (!node) return null;
    const el = node.nodeType === 1 ? node : node.parentElement;
    return el && el.closest ? el.closest('[data-bid]') : null;
  }
  // 原生选区的锚/焦两端（bid + UTF-16 偏移）
  function nativeEnds() {
    const sel = window.getSelection();
    if (!sel.rangeCount) return null;
    const aEl = nodeBlockEl(sel.anchorNode);
    const fEl = nodeBlockEl(sel.focusNode);
    if (!aEl || !fEl) return null;
    return {
      a: { bid: aEl.dataset.bid, off: posFromNode(aEl, sel.anchorNode, sel.anchorOffset) },
      f: { bid: fEl.dataset.bid, off: posFromNode(fEl, sel.focusNode, sel.focusOffset) },
      collapsed: sel.isCollapsed,
    };
  }
  function placeNativeAt(pos) {
    const el = root.querySelector('[data-bid="' + pos.bid + '"]');
    if (!el) return;
    el.focus();
    const p = rangePoint(el, pos.off);
    const r = document.createRange();
    r.setStart(p[0], p[1]);
    r.collapse(true);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
  }
  function xselOrder() {
    if (!xsel) return null;
    const blocks = editableBlocks();
    const ai = blocks.findIndex((b) => b.dataset.bid === xsel.a.bid);
    const fi = blocks.findIndex((b) => b.dataset.bid === xsel.f.bid);
    if (ai < 0 || fi < 0) return null;
    if (ai < fi || (ai === fi && xsel.a.off <= xsel.f.off)) return [xsel.a, xsel.f];
    return [xsel.f, xsel.a];
  }
  function paintXsel() {
    if (!xselHl) return;
    xselHl.clear();
    if (!xsel) return;
    const ord = xselOrder();
    if (!ord) return;
    const s = ord[0];
    const en = ord[1];
    const blocks = editableBlocks();
    const si = blocks.findIndex((b) => b.dataset.bid === s.bid);
    const ei = blocks.findIndex((b) => b.dataset.bid === en.bid);
    if (si < 0 || ei < 0) return;
    for (let i = si; i <= ei; i++) {
      const el = blocks[i];
      const from = i === si ? s.off : 0;
      const to = i === ei ? en.off : blockText(el).length;
      if (to > from) { try { xselHl.add(rangeOf(el, from, to)); } catch (_) {} }
    }
    // 端点块之间的非可编辑顶层单元（原子块/预览块）整块着色
    const su = unitOf(blocks[si]);
    const eu = unitOf(blocks[ei]);
    if (su && eu && su !== eu) {
      const units = allUnits();
      const sui = units.indexOf(su);
      const eui = units.indexOf(eu);
      for (let i = sui + 1; i < eui; i++) {
        const u = units[i];
        let hasEdit = false;
        for (const b of blocks) { if (u === b || u.contains(b)) { hasEdit = true; break; } }
        if (!hasEdit) { const r = document.createRange(); r.selectNodeContents(u); xselHl.add(r); }
      }
    }
  }
  // 选区不得跨越源码态块：焦点端钳到源码块近侧边界
  function guardSpan(anchor, focus) {
    const blocks = editableBlocks();
    const ai = blocks.findIndex((b) => b.dataset.bid === anchor.bid);
    const fi = blocks.findIndex((b) => b.dataset.bid === focus.bid);
    if (ai < 0 || fi < 0 || ai === fi) return focus;
    const step = ai < fi ? 1 : -1;
    for (let i = ai + step; step > 0 ? i <= fi : i >= fi; i += step) {
      if (isSrcBlock(blocks[i])) {
        const nb = blocks[i - step];
        return step > 0
          ? { bid: nb.dataset.bid, off: blockText(nb).length }
          : { bid: nb.dataset.bid, off: 0 };
      }
    }
    return focus;
  }
  function setXsel(anchor, focus, whole) {
    if (!whole) focus = guardSpan(anchor, focus);
    if (!whole && anchor.bid === focus.bid && anchor.off === focus.off) {
      xsel = null;
      paintXsel();
      return;
    }
    xsel = {
      a: { bid: anchor.bid, off: anchor.off },
      f: { bid: focus.bid, off: focus.off },
      fromStart: !!(whole && whole.fromStart),
      toEnd: !!(whole && whole.toEnd),
    };
    paintXsel();
    placeNativeAt(xsel.a);
  }
  function clearXsel() { xsel = null; paintXsel(); }
  function collapseXsel() { if (!xsel) return; const f = xsel.f; clearXsel(); placeNativeAt(f); }
  function xselText() {
    if (!xsel) return '';
    const ord = xselOrder();
    if (!ord) return '';
    const s = ord[0];
    const en = ord[1];
    const blocks = editableBlocks();
    const si = blocks.findIndex((b) => b.dataset.bid === s.bid);
    const ei = blocks.findIndex((b) => b.dataset.bid === en.bid);
    if (si < 0 || ei < 0) return '';
    const parts = [];
    for (let i = si; i <= ei; i++) {
      const t = blockText(blocks[i]);
      const from = i === si ? s.off : 0;
      const to = i === ei ? en.off : t.length;
      parts.push(t.slice(from, to));
    }
    return parts.join('\n\n');
  }
  window.__mnXSel = () => xsel ? { aBid: xsel.a.bid, aOff: xsel.a.off, fBid: xsel.f.bid, fOff: xsel.f.off, text: xselText() } : null;
  function sendReplace(text, enter) {
    if (!xsel) return;
    const ord = xselOrder();
    const fromStart = !!xsel.fromStart;
    const toEnd = !!xsel.toEnd;
    clearXsel();
    if (!ord) return;
    dioxus.send(JSON.stringify({
      op: 'replaceRange', aBid: ord[0].bid, aOff: ord[0].off, fBid: ord[1].bid, fOff: ord[1].off,
      text: text || '', enter: !!enter, fromStart: fromStart, toEnd: toEnd, sync: collectSync(),
    }));
  }
  function copyXsel() {
    const t = xselText();
    if (t && navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(t).catch(() => {});
    }
  }
  function selectAllXsel() {
    const blocks = editableBlocks();
    if (!blocks.length) return;
    const last = blocks[blocks.length - 1];
    setXsel({ bid: blocks[0].dataset.bid, off: 0 }, { bid: last.dataset.bid, off: blockText(last).length }, { fromStart: true, toEnd: true });
  }
  // 字符步进（按 Unicode 标量，不劈代理对；偏移 UTF-16)
  function stepChar(blocks, idx, off, dir) {
    const el = blocks[idx];
    const t = blockText(el);
    if (dir > 0) {
      if (off < t.length) {
        const c = t.charCodeAt(off);
        return { bid: el.dataset.bid, off: off + ((c >= 0xD800 && c <= 0xDBFF) ? 2 : 1) };
      }
      if (idx + 1 < blocks.length) return { bid: blocks[idx + 1].dataset.bid, off: 0 };
      return { bid: el.dataset.bid, off: t.length };
    }
    if (off > 0) {
      const c = t.charCodeAt(off - 1);
      return { bid: el.dataset.bid, off: off - ((c >= 0xDC00 && c <= 0xDFFF) ? 2 : 1) };
    }
    if (idx > 0) { const p = blocks[idx - 1]; return { bid: p.dataset.bid, off: blockText(p).length }; }
    return { bid: el.dataset.bid, off: 0 };
  }
  function pointRect(el, off) {
    const p = rangePoint(el, off);
    const r = document.createRange();
    r.setStart(p[0], p[1]);
    r.collapse(true);
    let rect = r.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0 && p[0].nodeType === 3 && p[0].textContent.length) {
      const alt = document.createRange();
      if (p[1] < p[0].textContent.length) { alt.setStart(p[0], p[1]); alt.setEnd(p[0], p[1] + 1); }
      else { alt.setStart(p[0], p[1] - 1); alt.setEnd(p[0], p[1]); }
      const ar = alt.getBoundingClientRect();
      if (ar.height) rect = ar;
    }
    return rect;
  }
  function pointFromXY(el, x, y) {
    if (!document.caretRangeFromPoint) return null;
    const r = document.caretRangeFromPoint(x, y);
    if (!r) return null;
    if (nodeBlockEl(r.startContainer) !== el) return null;
    return { bid: el.dataset.bid, off: posFromNode(el, r.startContainer, r.startOffset) };
  }
  // Shift+方向扩展：仅跨块步进（或已有 xsel）时接管，块内放行
  // 原生（保住原生选区粒度）。返回 true = 已处理。
  function xselExtend(e, el) {
    const key = e.key;
    const blocks = editableBlocks();
    let anchor;
    let focus;
    if (xsel) { anchor = xsel.a; focus = { bid: xsel.f.bid, off: xsel.f.off }; }
    else {
      const ends = nativeEnds();
      if (!ends) return false;
      anchor = ends.a;
      focus = { bid: ends.f.bid, off: ends.f.off };
    }
    const fi = blocks.findIndex((b) => b.dataset.bid === focus.bid);
    if (fi < 0) return false;
    const fEl = blocks[fi];
    let nf = null;
    if (key === 'ArrowLeft' || key === 'ArrowRight') {
      nf = stepChar(blocks, fi, focus.off, key === 'ArrowLeft' ? -1 : 1);
      if (!xsel && nf.bid === focus.bid) return false;
    } else {
      const rect = xsel ? pointRect(fEl, focus.off) : caretLineRect(fEl);
      if (!rect) return false;
      const er = fEl.getBoundingClientRect();
      const lh = rect.height || 24;
      const up = key === 'ArrowUp';
      const onEdge = up ? (rect.top - er.top < lh * 0.9) : (er.bottom - rect.bottom < lh * 0.9);
      if (!onEdge) {
        if (!xsel) return false;
        const y = up ? rect.top - lh * 0.6 : rect.bottom + lh * 0.6;
        nf = pointFromXY(fEl, rect.left + 1, y);
        if (!nf) return false;
      } else {
        const ti = up ? fi - 1 : fi + 1;
        if (ti < 0 || ti >= blocks.length) {
          nf = up ? { bid: blocks[0].dataset.bid, off: 0 } : { bid: fEl.dataset.bid, off: blockText(fEl).length };
          if (!xsel && nf.bid === focus.bid && nf.off === focus.off) return false;
        } else {
          const tEl = blocks[ti];
          const tr = tEl.getBoundingClientRect();
          const y = up ? tr.bottom - lh * 0.4 : tr.top + lh * 0.4;
          nf = pointFromXY(tEl, rect.left + 1, y) || (up ? { bid: tEl.dataset.bid, off: blockText(tEl).length } : { bid: tEl.dataset.bid, off: 0 });
        }
      }
    }
    if (!nf) return false;
    e.preventDefault();
    setXsel(anchor, nf, null);
    return true;
  }
  // 鼠标拖拽跨块选区：单次按下（detail 1）接管——原生拖拽被
  // CE 宿主钳制；双击/三击放行原生（选词/选段是块内行为）。
  // touch 不接管（长按原生块内选区保持现状）。
  let dragSel = null;
  function pointInBlock(el, x, y) {
    if (!document.caretRangeFromPoint) return null;
    const r = document.caretRangeFromPoint(x, y);
    if (!r) return null;
    if (nodeBlockEl(r.startContainer) !== el || isSrcBlock(el)) return null;
    return { bid: el.dataset.bid, off: posFromNode(el, r.startContainer, r.startOffset) };
  }
  function dragPoint(x, y) {
    const r = document.caretRangeFromPoint ? document.caretRangeFromPoint(x, y) : null;
    if (r) {
      const bel = nodeBlockEl(r.startContainer);
      if (bel && !isSrcBlock(bel)) return { bid: bel.dataset.bid, off: posFromNode(bel, r.startContainer, r.startOffset) };
    }
    // 指针压在原子块/块间隙：就近钳到相邻可编辑块边界
    const blocks = editableBlocks();
    if (!blocks.length) return null;
    let best = null;
    let bestD = Infinity;
    for (const b of blocks) {
      const br = b.getBoundingClientRect();
      const d = y < br.top ? br.top - y : (y > br.bottom ? y - br.bottom : 0);
      if (d < bestD) { bestD = d; best = { el: b, rect: br }; }
    }
    if (!best) return null;
    return y <= best.rect.top + best.rect.height / 2
      ? { bid: best.el.dataset.bid, off: 0 }
      : { bid: best.el.dataset.bid, off: blockText(best.el).length };
  }
  root.addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'mouse' || e.button !== 0 || composing) return;
    const t = e.target;
    if (!t || !t.closest) return;
    const el = t.closest('[data-bid]');
    if (!el || !el.isContentEditable || isSrcBlock(el)) return;
    if (e.shiftKey) {
      const pt = pointInBlock(el, e.clientX, e.clientY);
      if (!pt) return;
      let anchor = null;
      if (xsel) anchor = xsel.a;
      else { const ends = nativeEnds(); if (ends) anchor = ends.a; }
      if (!anchor) return;
      e.preventDefault();
      setXsel(anchor, pt, null);
      return;
    }
    if (e.detail >= 2) { clearXsel(); return; }
    const pt = pointInBlock(el, e.clientX, e.clientY);
    clearXsel();
    if (!pt) return;
    e.preventDefault();
    placeNativeAt(pt);
    dragSel = { a: pt };
  });
  root.addEventListener('pointermove', (e) => {
    if (!dragSel || e.pointerType !== 'mouse' || (e.buttons & 1) === 0) return;
    const pt = dragPoint(e.clientX, e.clientY);
    if (!pt) return;
    if (pt.bid === dragSel.a.bid && pt.off === dragSel.a.off) { if (xsel) clearXsel(); return; }
    setXsel(dragSel.a, pt, null);
  });
  root.addEventListener('pointerup', (e) => { if (e.pointerType === 'mouse') dragSel = null; });
  // 组合输入开始前先收拢选区（删除会与 IME 抢占同一块 DOM）
  root.addEventListener('compositionstart', () => { if (xsel) collapseXsel(); });
  // 外部光标移动（编程落点 __mnFocus、触摸点按落点等）使选区
  // 失效：原生选区一旦不在锚点收拢（或展开为原生选区），桥内
  // 选区即作废，避免陈旧跨度被下一次击键误替换。桥内自身落点
  // 恒在锚点，不会误清。
  onGlobal(document, 'selectionchange', () => {
    if (!xsel || dragSel) return;
    const ends = nativeEnds();
    if (!ends) return;
    if (!ends.collapsed) { clearXsel(); return; }
    if (ends.a.bid !== xsel.a.bid || ends.a.off !== xsel.a.off) clearXsel();
  });

  root.addEventListener('keydown', (e) => {
    const el = editableOf(e);
    if (!el) return;
    // 组合输入守卫必须最先（原版 editor.js:2026 同口径）：面板
    // 开着时用拼音打过滤词，组合中的回车/方向键是给输入法的，
    // 绝不能被面板分支抢走应用命令（编辑态审计 D3）。keyCode
    // 229 是 IME 处理中击键的兜底信号（批 1 B-11：部分 WebKit
    // isComposing 缺失时靠它识别组字击键）。
    if (composing || e.isComposing || e.keyCode === 229) return;
    // 纵向目标列会话（B-12）：非 Up/Down 的击键即散会话。
    if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') resetArrowGoal();
    const panel = document.getElementById('slash-panel');
    if (panel) {
      if (e.key === 'ArrowDown') { e.preventDefault(); moveSel(panel, 1); return; }
      if (e.key === 'ArrowUp') { e.preventDefault(); moveSel(panel, -1); return; }
      if (e.key === 'Enter') {
        e.preventDefault();
        const sel = panel.querySelector('.slash-row.sel') || panel.querySelector('.slash-row');
        if (sel) {
          const act = sel.dataset.act;
          if (act === 'link') {
            dioxus.send(JSON.stringify({ op: 'slashLink', id: el.dataset.bid }));
          } else if (INLINE_ACTS.indexOf(act) >= 0) {
            // applyInline 内部先捕获选区再剥离令牌（顺序反了选区会失效）
            const html = applyInline(act, el);
            dioxus.send(JSON.stringify({ op: 'pasteSync', id: el.dataset.bid, html }));
            dioxus.send(JSON.stringify({ op: 'slashClose' }));
          } else {
            stripSlash(el);
            dioxus.send(JSON.stringify({ op: 'slashApply', id: el.dataset.bid, act, html: el.innerHTML }));
          }
        }
        return;
      }
      if (e.key === 'Escape') { dioxus.send(JSON.stringify({ op: 'slashClose' })); return; }
    }
    // 跨块选区接管（xsel 引擎）：选区激活时编辑键走
    // replaceRange；Shift+方向仅在跨块步进时接管扩展；
    // Ctrl+A 全文选区（原版单宿主原生行为，分块架构补齐）。
    if (xsel) {
      const xk = e.key;
      if ((e.ctrlKey || e.metaKey) && (xk === 'a' || xk === 'A')) { e.preventDefault(); selectAllXsel(); return; }
      if ((e.ctrlKey || e.metaKey) && (xk === 'c' || xk === 'C')) { e.preventDefault(); copyXsel(); return; }
      if ((e.ctrlKey || e.metaKey) && (xk === 'x' || xk === 'X')) { e.preventDefault(); copyXsel(); sendReplace(''); return; }
      if (e.ctrlKey || e.metaKey) { clearXsel(); }
      else if (xk === 'Shift' || xk === 'Control' || xk === 'Alt' || xk === 'Meta' || xk === 'CapsLock' || xk === 'Dead') { /* 纯修饰键不动选区（按住 Shift 准备扩展时先到的就是这一下） */ }
      else if (xk === 'Backspace' || xk === 'Delete') { e.preventDefault(); sendReplace(''); return; }
      else if (xk === 'Enter') { e.preventDefault(); sendReplace('', true); return; }
      else if (xk === 'Escape') { collapseXsel(); return; }
      else if (e.shiftKey && xk.startsWith('Arrow')) { if (!xselExtend(e, el)) collapseXsel(); }
      else if (xk.startsWith('Arrow')) {
        e.preventDefault();
        const ord = xselOrder();
        clearXsel();
        if (ord) placeNativeAt((xk === 'ArrowLeft' || xk === 'ArrowUp') ? ord[0] : ord[1]);
        return;
      }
      else if (xk.length === 1 && !e.altKey) { e.preventDefault(); sendReplace(xk); return; }
      else { collapseXsel(); }
    } else if (e.shiftKey && e.key.startsWith('Arrow')) {
      if (xselExtend(e, el)) return;
    } else if ((e.ctrlKey || e.metaKey) && (e.key === 'a' || e.key === 'A') && !isSrcBlock(el)) {
      e.preventDefault();
      selectAllXsel();
      return;
    }
    if ((e.metaKey || e.ctrlKey) && !composing && !e.isComposing) {
      const k = e.key.toLowerCase();
      if (k === 'z' || k === 'y') {
        // 撤销/重做必须由应用接管（编辑态审计 D2）：放行浏览器
        // 原生 undo 只会改当前块 DOM、与模型脱节，随后 autosync
        // 还会把脱节结果落库。随消息带上全量同步与当前光标，
        // Rust 侧压栈回退并恢复焦点（D4）。事件打标供 doc 级
        // 兜底监听（B-10）防双发。
        e.preventDefault();
        e.__mnUndoHandled = true;
        const c = caretInfo(el);
        dioxus.send(JSON.stringify({
          op: (k === 'y' || e.shiftKey) ? 'redo' : 'undo',
          id: el.dataset.bid, off: c.offset, sync: collectSync(),
        }));
        return;
      }
      let cmd = null;
      if (k === 'b') cmd = 'bold';
      else if (k === 'i') cmd = 'italic';
      else if (k === 'u') cmd = 'underline';
      else if (k === 's' && e.shiftKey) cmd = 'strikeThrough';
      if (cmd) { e.preventDefault(); document.execCommand(cmd); return; }
    }
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight' || e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      // 块边界处跨块（见 crossBlockArrow）；块内/首末行之外
      // 返回 false 放行原生行内移动
      if (crossBlockArrow(e, el)) return;
    }
    if (el.dataset.btype === 'musicInput') {
      // 音乐输入胶囊（原版 resolvePendingMusicUrl 口径）：单行
      // URL 入口。回车 = 以当前文本尝试解析；段首退格 = 删块
      // 并回上块末尾；其余按键一律原生编辑，输入事件走
      // musicInput 复检（含 URL 即解析），绝不落 split/merge。
      if (e.key === 'Enter') {
        e.preventDefault();
        dioxus.send(JSON.stringify({ op: 'musicInput', id: el.dataset.bid, text: el.innerText || '' }));
      } else if (e.key === 'Backspace') {
        const c = caretInfo(el);
        if (c.collapsed && c.offset === 0) {
          e.preventDefault();
          dioxus.send(JSON.stringify({ op: 'musicDelete', id: el.dataset.bid }));
        }
      }
      return;
    }
    if (el.dataset.btype === 'codeBlock' || el.dataset.btype === 'mdsrc') {
      // md 源码/代码块（编辑态审计 B11）：回车仍是块内换行放行
      // 原生，但段首退格要能合并/删块（与普通段一致），不能被
      // 「直接放行原生」吞掉——原生在块首无前文可删只会无操作。
      if (e.key === 'Backspace') {
        const c = caretInfo(el);
        if (c.collapsed && c.offset === 0) {
          e.preventDefault();
          const esc = (el.innerText || '')
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/\n/g, '<br>');
          dioxus.send(JSON.stringify({ op: 'merge', id: el.dataset.bid, html: esc }));
        }
      }
      return;
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      if (e.shiftKey) {
        // Shift+Enter = 块内软换行（原版口径）：插入 <br> 后把
        // 本块 HTML 同步进模型（\n 落文本，见 core 的 Br 处理）
        document.execCommand('insertLineBreak');
        dioxus.send(JSON.stringify({ op: 'pasteSync', id: el.dataset.bid, html: el.innerHTML }));
        return;
      }
      const c = caretInfo(el);
      dioxus.send(JSON.stringify({ op: 'split', id: el.dataset.bid, before: c.beforeHtml, after: c.afterHtml }));
    } else if (e.key === 'Backspace') {
      const c = caretInfo(el);
      if (c.collapsed && c.offset === 0) {
        e.preventDefault();
        dioxus.send(JSON.stringify({ op: 'merge', id: el.dataset.bid, html: el.innerHTML }));
      }
    }
  });

  // 实时高亮：光标刚落在一对 ==…== 的闭合 == 之后时，就地把
  // 内段包成 <mark> 并把光标移到 mark 之后。只处理光标所在的
  // 单个文本节点、且该节点不在已有 mark 内；组合输入期间不
  // 调用（input 监听先查 composing），拼音确认后才触发。
  function realtimeHighlight(el) {
    const sel = window.getSelection();
    if (!sel.rangeCount) return false;
    const range = sel.getRangeAt(0);
    if (!range.collapsed) return false;
    const node = range.startContainer;
    if (node.nodeType !== 3) return false;
    if (node.parentElement && node.parentElement.closest('mark')) return false;
    const off = range.startOffset;
    const text = node.textContent;
    if (off < 2 || text.slice(off - 2, off) !== '==') return false;
    if (text[off] === '=') return false;
    const closeStart = off - 2;
    const openIdx = text.lastIndexOf('==', closeStart - 1);
    if (openIdx < 0) return false;
    if (openIdx > 0 && text[openIdx - 1] === '=') return false;
    const inner = text.slice(openIdx + 2, closeStart);
    if (!inner) return false;
    const parent = node.parentNode;
    const mark = document.createElement('mark');
    mark.className = 'mynote-highlight';
    mark.textContent = inner;
    const beforeNode = document.createTextNode(text.slice(0, openIdx));
    // afterNode 前置零宽空格并把光标放到其后：否则光标贴在
    // mark 边界上，后续键入会被浏览器吸进 mark 里。零宽空格
    // 在 core 解析时统一剥掉，不进模型。
    const afterNode = document.createTextNode('\u200b' + text.slice(off));
    parent.insertBefore(beforeNode, node);
    parent.insertBefore(mark, node);
    parent.insertBefore(afterNode, node);
    parent.removeChild(node);
    const r = document.createRange();
    r.setStart(afterNode, 1);
    r.collapse(true);
    sel.removeAllRanges();
    sel.addRange(r);
    return true;
  }

  // 标题编辑会话已整段迁至 Rust 侧 TitleController
  // （title_controller.rs，web-sys 直注监听）：桥不再持有
  // 任何标题状态/监听，标题输入事件在本桥 input 处理里经
  // editableOf 落空（无 data-bid）自然跳过。

  // 智能前缀防抖计时器（按块 id；桥卸载时统一清理）
  const prefixTimers = new Map();
  bridgeDisposers.push(() => {
    prefixTimers.forEach((tm) => clearTimeout(tm));
    prefixTimers.clear();
  });

  root.addEventListener('input', (e) => {
    resetArrowGoal();
    const el = editableOf(e);
    if (!el || composing) return;
    processInput(el);
  });

  // 输入管线本体（批 1 B-11 起具名化）：input 监听与组字
  // 结束重放共用同一入口。先走 B-9 错位粘贴回收（命中即
  // 还原该块并转交胶囊、跳过常规管线，与原版 resolve 后
  // return 同口径），其余分支与原监听同序。
  function processInput(el) {
    if (musicPasteRecover(el)) return;
    if (el.dataset.btype === 'mdsrc') {
      dioxus.send(JSON.stringify({ op: 'mdText', id: el.dataset.bid, text: el.innerText || '' }));
      return;
    }
    if (el.dataset.btype === 'musicInput') {
      // 音乐输入胶囊：文本只作待解析 URL 复检，绝不进斜杠
      // 检测（URL 里的 '/' 会误触面板）也不落模型
      dioxus.send(JSON.stringify({ op: 'musicInput', id: el.dataset.bid, text: el.innerText || '' }));
      return;
    }
    if (el.dataset.btype === 'codeBlock') return;
    if (realtimeHighlight(el)) {
      dioxus.send(JSON.stringify({ op: 'pasteSync', id: el.dataset.bid, html: el.innerHTML }));
      return;
    }
    const t = (el.innerText || '').replace(/\n$/, '');
    const panel = document.getElementById('slash-panel');
    // 触发面（斜杠审计 S2，原版 token 模型）：光标之前最后一个
    // '/' 起、到光标为止不含空白，即为斜杠令牌——块内任意位置
    // 可触发，不限块首。锚点用光标 rect 而非块 rect（长块里
    // 面板要贴着光标，不是贴着块底）。
    const c = caretInfo(el);
    const before = t.slice(0, c.offset);
    const slashAt = before.lastIndexOf('/');
    const query = slashAt >= 0 ? before.slice(slashAt + 1) : null;
    // 触发抑制（批 1 D-1，原版 use-slash 口径）：含当前 '/'
    // 的非空白 token（剥前导括号引号）以 http(s):// 或 www.
    // 开头时，该 '/' 是手打 URL 的一部分、不是命令触发；
    // 查询超过 30 字同样不触发（长查询不再是命令意图）。
    let urlToken = false;
    if (slashAt >= 0) {
      const tokMatch = before.slice(0, slashAt + 1).match(/\S+$/);
      const tok = tokMatch ? tokMatch[0].replace(/^[([{<"'"‘]+/, '') : '';
      urlToken = /^(?:https?:\/\/|www\.)\S*$/i.test(tok);
    }
    if (query !== null && !/\s/.test(query) && query.length <= 30 && !urlToken) {
      el.dataset.slashPos = String(slashAt);
      el.dataset.slashLen = String(query.length + 1);
      let ax = 0, ay = 0, ab = 0;
      const sel = window.getSelection();
      if (sel && sel.rangeCount) {
        const rects = sel.getRangeAt(0).getClientRects();
        const cr = rects.length ? rects[rects.length - 1] : null;
        if (cr) { ax = cr.left; ay = cr.top; ab = cr.bottom; }
      }
      if (!ab) {
        const r = el.getBoundingClientRect();
        ax = r.left; ay = r.top; ab = r.bottom;
      }
      dioxus.send(JSON.stringify({ op: 'slash', id: el.dataset.bid, filter: query, x: ax, y: ay, b: ab }));
    } else if (panel) {
      delete el.dataset.slashPos;
      dioxus.send(JSON.stringify({ op: 'slashClose' }));
    }
    // 智能前缀触发（原版 handleEditorInput 在 input 后以
    // 80ms 防抖跑前缀扫描）：普通打字不逐键同步模型，这里
    // 按原版同口径防抖——段落停顿 80ms 后文本命中原版
    // PATTERNS 才补发一次 pasteSync 把该块送进模型，权威
    // 转换在 Rust 侧 apply_smart_prefix 复检执行（同一组
    // 正则）。防抖保证中间态（如刚打出 "> "）不抢在后续
    // 字符之前误转、标注守卫按全文判定；发火时斜杠面板
    // 在场则跳过（原版 showSlash 守卫）。
    if (el.dataset.btype === 'paragraph') {
      const pbid = el.dataset.bid;
      const prevTm = prefixTimers.get(pbid);
      if (prevTm) clearTimeout(prevTm);
      prefixTimers.set(pbid, setTimeout(() => {
        prefixTimers.delete(pbid);
        const cur = root.querySelector('[data-bid="' + pbid + '"]');
        if (!cur || cur.dataset.btype !== 'paragraph') return;
        if (document.getElementById('slash-panel')) return;
        const tt = (cur.innerText || '').replace(/\n$/, '');
        if (/^#{1,3} .+/.test(tt) || /^>(?!\s*\[!\S).+/.test(tt) || /^\[ \] .+/.test(tt) || /^\[\] .+/.test(tt) || tt === '---') {
          dioxus.send(JSON.stringify({ op: 'pasteSync', id: pbid, html: cur.innerHTML }));
        }
      }, 80));
    }
  }

  root.addEventListener('focusin', (e) => {
    const el = editableOf(e);
    if (el) {
      lastFocusBid = el.dataset.bid;
      dioxus.send(JSON.stringify({ op: 'focusBlock', id: el.dataset.bid }));
    }
  });

  // 最近一次指针是否落在编辑区内（S8 判定用）：分块架构下
  // 点原子块会让焦点落到 body，单看 activeElement 分不清
  // 「还在编辑区里点按」与「点外面收键盘」；原版单宿主靠焦
  // 点包含关系区分，这里用最近指针位置合成同一判定。
  let lastPointerInEditor = 0;
  root.addEventListener('pointerdown', (e) => {
    resetArrowGoal();
    lastPointerInEditor = e.target && e.target.closest && e.target.closest('.editor-body, .editor-title-dock') ? Date.now() : 0;
    // 点原子块同样刷新「最近聚焦」标记（B-9 engaged 判定用：
    // 点别的块即解除音乐胶囊的 engaged，与原版点击清
    // activeMusicInputId 同口径；点胶囊本尊不在 blk-wrap 内、
    // 不受影响）。
    const wrap = e.target && e.target.closest ? e.target.closest('.blk-wrap') : null;
    if (wrap) lastFocusBid = wrap.getAttribute('data-wrapbid');
  }, true);

  root.addEventListener('focusout', (e) => {
    const el = editableOf(e);
    if (el) {
      dioxus.send(JSON.stringify({ op: 'blurBlock', id: el.dataset.bid }));
      if (el.dataset.btype === 'mdsrc') {
        dioxus.send(JSON.stringify({ op: 'mdDone', id: el.dataset.bid }));
      }
      // 失焦回顶（滚动审计 S8，原版 use-editor-dom.js:425-450）：
      // 焦点真正离开编辑区（不在正文、不在标题坞、也不是刚
      // 点了编辑区内的原子块）时 scrollTo(0,0) 回顶，并以
      // 80ms × 6 次重发 forceTop 压住 iOS 的异步滚动恢复
      // （原版同机制：scrollTo 一次 + setEditorScrolled(false)
      // 重试六次；标题重新获焦即停）。
      requestAnimationFrame(() => {
        // 结构性卸载（块被重渲染替换，如音乐胶囊解析后换成
        // 骨架）不是用户失焦：节点已脱离文档时不回顶，否则
        // 骨架期会被 forceTop 拽着滚。
        if (!document.contains(el)) return;
        const active = document.activeElement;
        if (active && active.closest && (active.closest('.editor-body') || active.closest('.editor-title-dock'))) return;
        if (Date.now() - lastPointerInEditor < 500) return;
        if (window.visualViewport) window.scrollTo(0, 0);
        dioxus.send(JSON.stringify({ op: 'forceTop' }));
        let retries = 0;
        const force = () => {
          const cur = document.activeElement;
          if (cur && cur.closest && (cur.closest('.editor-body') || cur.closest('.editor-title-dock'))) return;
          dioxus.send(JSON.stringify({ op: 'forceTop' }));
          retries++;
          if (retries < 6) setTimeout(force, 80);
        };
        setTimeout(force, 80);
      });
    }
  });

  // 原子块点击（原版 use-editor-dom.js 的边缘区语义）：插段
  // 边带按块型分档（卡片类右 15%、附件/链接卡左右 28px，
  // 见处理内 B-13 注）；点中央 = 选中该块（块操作钮只在
  // 选中后出现）。按钮/链接/图片（灯箱）/图文文本区（开
  // 面板）各自的行为优先，不发消息。
  root.addEventListener('click', (e) => {
    const t = e.target;
    if (!t || !t.closest) return;
    // 点面板外关闭斜杠面板（斜杠审计 S9，原版口径；点别的块
    // 同样关闭，不再把面板钉在旧块上）
    const sp = document.getElementById('slash-panel');
    if (sp && !t.closest('#slash-panel')) {
      dioxus.send(JSON.stringify({ op: 'slashClose' }));
    }
    if (t.closest('button, input, label')) return;
    const wrap = t.closest('.blk-wrap');
    if (!wrap) {
      if (t.closest('[contenteditable="true"]')) {
        dioxus.send(JSON.stringify({ op: 'clearSelect' }));
      }
      return;
    }
    const bid = wrap.getAttribute('data-wrapbid');
    if (!bid) return;
    const r = wrap.getBoundingClientRect();
    const x = e.clientX - r.left;
    // 插段区按块型分档（批 1 B-13，原版 use-editor-dom 口径）：
    // 卡片类（imgTextCard/imageTextRow/image/gallery/
    // musicCard/divider）只有右侧 15% 插段区、无左侧区——
    // 旧实现统一 28px 时宽卡左侧误触插段、右侧 15% 区内
    // （28px 之外）又点不中；附件/链接卡类维持左右 28px；
    // 其余类型维持既有 28px 双侧口径。块型由渲染侧写在
    // blk-wrap 的 data-wtype 上。卡片右区判定先于图文文本
    // 区/可编辑区早退（原版同序：先几何区、后图区/文本
    // 区）——否则右区落在 .itc-text 上被开面板吞掉、整区
    // 失效。
    const wtype = wrap.getAttribute('data-wtype') || '';
    const CARD_TYPES = ['imgTextCard', 'imageTextRow', 'image', 'gallery', 'musicCard', 'divider'];
    const isCard = CARD_TYPES.indexOf(wtype) >= 0;
    if (isCard && x > r.width * 0.85) {
      // kind=card 标记供 Rust 侧区分落段语义：卡片右区恒
      // 新插一段（原版「新增一行」），附件右区才是聚焦既有
      // 下一段（见 editor.rs insertPara 臂）。
      dioxus.send(JSON.stringify({ op: 'insertPara', id: bid, where: 'after', kind: 'card' }));
      return;
    }
    // 卡片编辑门禁（卡片交互专项）：带内部可编辑子区域的
    // 卡（图文卡/左图右字/图片/画廊）按编辑态分流子区域
    // 点按——非编辑态：文本区拦下开表（stopPropagation 阻
    // 断 Dioxus 委托，本处理在 #editor-root 冒泡先于委托
    // 触发）、只选中卡片（图文文本区原 clearSelect 口径就
    // 此统一为选中，与左图右字卡既有落点一致）；图片区不
    // 干预（灯箱/选中照旧）。编辑态：文本区放行开表；图
    // 片区拦下灯箱、直调系统选图（cardPick）。右 15% 插
    // 段区判定在前，本段不改变其落点。
    const cardEditing = wrap.classList.contains('card-editing');
    if (wtype === 'imgTextCard' || wtype === 'imageTextRow') {
      if (t.closest('.itc-text, .itr-text')) {
        if (cardEditing) return;
        e.stopPropagation();
        dioxus.send(JSON.stringify({ op: 'selectBlock', id: bid }));
        return;
      }
      if (cardEditing && t.closest('.itc-img-wrap, .itr-img')) {
        e.stopPropagation();
        dioxus.send(JSON.stringify({ op: 'cardPick', id: bid, kind: 'set' }));
        return;
      }
    } else if (wtype === 'image') {
      if (cardEditing && t.closest('img, .atomic-placeholder')) {
        e.stopPropagation();
        dioxus.send(JSON.stringify({ op: 'cardPick', id: bid, kind: 'set' }));
        return;
      }
    } else if (wtype === 'gallery') {
      if (cardEditing) {
        if (t.closest('.gallery-empty-tile')) {
          e.stopPropagation();
          dioxus.send(JSON.stringify({ op: 'cardPick', id: bid, kind: 'galleryAdd' }));
          return;
        }
        const gimg = t.closest('.gallery-grid img');
        if (gimg) {
          const gimgs = wrap.querySelectorAll('.gallery-grid img');
          const gix = Array.prototype.indexOf.call(gimgs, gimg);
          e.stopPropagation();
          dioxus.send(JSON.stringify({ op: 'cardPick', id: bid, kind: 'galleryItem', index: gix }));
          return;
        }
      }
    }
    if (t.closest('[contenteditable="true"], .itc-text')) {
      dioxus.send(JSON.stringify({ op: 'clearSelect' }));
      return;
    }
    if (!isCard) {
      if (x < 28) {
        dioxus.send(JSON.stringify({ op: 'insertPara', id: bid, where: 'before' }));
        return;
      }
      if (x > r.width - 28) {
        dioxus.send(JSON.stringify({ op: 'insertPara', id: bid, where: 'after' }));
        return;
      }
    }
    // C-11：link-card 容器为 div + data-url（原版委托口
    // 径，容器不再是整卡 <a>）——命中卡且 data-url 非空
    // 时新窗打开并收口；data-url 为空（URL 被 C-30 白名
    // 单拦下）时落到下方 selectBlock，只选中不打开。左
    // 右插段区判定在前，本段不改变其落点。
    const lc = t.closest('.link-card-block[data-url], .link-card-err[data-url]');
    if (lc) {
      const u = lc.getAttribute('data-url') || '';
      if (u) { window.open(u, '_blank'); return; }
    }
    // 链接（音乐成品卡）保持跳转；图片保持灯箱（图片块的既有
    // 行为），同时选中该块——关掉灯箱后块操作钮就在原地。
    if (t.closest('a')) return;
    dioxus.send(JSON.stringify({ op: 'selectBlock', id: bid }));
  });

  // 桌面右键菜单（卡片交互专项）：覆盖卡右键 → 同一浮层
  // 菜单（点锚定位），preventDefault 压掉系统菜单；可编
  // 辑区与非覆盖块不干预（保留系统菜单与文本行为）。
  root.addEventListener('contextmenu', (e) => {
    const t = e.target;
    if (!t || !t.closest) return;
    if (t.closest('[contenteditable="true"], input, textarea')) return;
    const wrap = t.closest('.blk-wrap');
    if (!wrap) return;
    const wtype = wrap.getAttribute('data-wtype') || '';
    if (CARD_MENU_TYPES.indexOf(wtype) < 0) return;
    const bid = wrap.getAttribute('data-wrapbid');
    if (!bid) return;
    e.preventDefault();
    const r = wrap.getBoundingClientRect();
    dioxus.send(JSON.stringify({ op: 'cardMenu', id: bid, wtype, anchor: 'point', x: e.clientX, y: e.clientY, rect: [r.left, r.top, r.width, r.height] }));
  });

  // 选中态的键盘删除（原版单一编辑器里原子块随选区 Delete；
  // 分块架构下由选中态承载）：焦点不在可编辑区时 Backspace/
  // Delete 删选中块，Escape 取消选中。监听挂 document 级：
  // 块被删后焦点落 body（不在 root 子树内），root 级监听收
  // 不到这一下退格——「空段退格选中原子块、再退格删块」的
  // 两步流与点选后退格删块都死在这里（实测）。Rust 侧
  // deleteSelected 对无选中态是 no-op，document 级安全。
  onGlobal(document, 'keydown', (e) => {
    if (e.key !== 'Backspace' && e.key !== 'Delete' && e.key !== 'Escape') return;
    const t = e.target;
    if (t && t.closest && t.closest('[contenteditable="true"], input, textarea')) return;
    if (e.key === 'Escape') {
      dioxus.send(JSON.stringify({ op: 'clearSelect' }));
    } else {
      e.preventDefault();
      dioxus.send(JSON.stringify({ op: 'deleteSelected' }));
    }
  });

  // 撤销快捷键作用域兜底（批 1 B-10，原版 use-history 的
  // window 级 keydown）：焦点不在任何可编辑块内（点过原子
  // 块后焦点落 body 是典型场景）时 Ctrl/Cmd+Z、Ctrl+Shift+Z、
  // Ctrl+Y 仍由应用接管；目标是 input/textarea（含标题原生
  // input 与链接表单）时绝不劫持其原生撤销。根级块内路径
  // 已处理同一事件时带 __mnUndoHandled 标记、此处跳过防
  // 双发（目标判定本身亦互斥）。op 带 collectSync 与空 id，
  // Rust 侧空 bid 走 focus_hint 恢复焦点。
  onGlobal(document, 'keydown', (e) => {
    if (e.__mnUndoHandled) return;
    if (!(e.ctrlKey || e.metaKey)) return;
    const k = (e.key || '').toLowerCase();
    if (k !== 'z' && k !== 'y') return;
    const t = e.target;
    if (t && t.closest && t.closest('[contenteditable="true"], input, textarea')) return;
    e.preventDefault();
    dioxus.send(JSON.stringify({
      op: (k === 'y' || e.shiftKey) ? 'redo' : 'undo',
      id: '', off: 0, sync: collectSync(),
    }));
  });

  // 音乐胶囊 engaged 判定（批 1 B-9，原版 activeMusicInputId
  // 的桥内等价）：胶囊存在，且焦点或选区在胶囊内，或最近
  // 一次聚焦/点按落在胶囊上（点别的块、聚焦别的块都会把
  // lastFocusBid 换走、自然解除）。
  function engagedMusicInput() {
    const mi = root.querySelector('[data-btype="musicInput"]');
    if (!mi) return null;
    const ae = document.activeElement;
    if (ae && (ae === mi || mi.contains(ae))) return mi;
    const sel = window.getSelection();
    if (sel && sel.focusNode && mi.contains(sel.focusNode)) return mi;
    if (lastFocusBid === mi.dataset.bid) return mi;
    return null;
  }

  // beforeinput 总线（批 1）：
  // B-5 iOS 三指撤销/重做（原版 use-history 在 beforeinput
  // 拦 historyUndo/historyRedo）：preventDefault 并发与键盘
  // 路径同形的 undo/redo op（collectSync + 当前块 id/off；
  // 焦点不在块内时 id 为空、走 focus_hint）。
  // B-9 音乐胶囊粘贴事务快照：insertFromPaste 且胶囊
  // engaged 时，按原版 captureMusicPasteTransaction 口径
  // 快照——落点块可编辑且非胶囊本尊则只快照该块；落点不
  // 明时快照全部可编辑块（排除胶囊本尊与不可编辑块），供
  // input 阶段 diff 回收错位粘贴的 URL 段。非粘贴的
  // beforeinput 一律作废旧事务，防陈旧快照误回收。
  root.addEventListener('beforeinput', (e) => {
    if (e.inputType === 'historyUndo' || e.inputType === 'historyRedo') {
      e.preventDefault();
      const el = editableOf(e);
      const c = el ? caretInfo(el) : { offset: 0 };
      dioxus.send(JSON.stringify({
        op: e.inputType === 'historyUndo' ? 'undo' : 'redo',
        id: el ? el.dataset.bid : '', off: c.offset, sync: collectSync(),
      }));
      return;
    }
    if (e.inputType !== 'insertFromPaste') { musicPasteTx = null; return; }
    const mi = engagedMusicInput();
    if (!mi) { musicPasteTx = null; return; }
    const sel = window.getSelection();
    const focusEl = sel && sel.focusNode ? (sel.focusNode.nodeType === 1 ? sel.focusNode : sel.focusNode.parentElement) : null;
    const targetBlock = (e.target && e.target.closest && e.target.closest('[data-bid]'))
      || (focusEl && focusEl.closest ? focusEl.closest('[data-bid]') : null);
    const snaps = [];
    if (targetBlock && targetBlock !== mi && targetBlock.isContentEditable) {
      snaps.push({ el: targetBlock, html: targetBlock.innerHTML, text: targetBlock.textContent || '' });
    } else if (!targetBlock) {
      root.querySelectorAll('[data-bid]').forEach((b) => {
        if (b === mi || !b.isContentEditable) return;
        snaps.push({ el: b, html: b.innerHTML, text: b.textContent || '' });
      });
    }
    musicPasteTx = { miBid: mi.dataset.bid, snaps, at: Date.now() };
  });

  // B-9 错位回收（processInput 首行调用）：按快照对本次
  // input 的块做前后缀 diff，插入段含 URL 时还原该块到粘
  // 贴前 HTML、把插入段转交胶囊解析（消息带 via 供 Rust
  // 侧 Diag 区分来源），返回 true 表示已回收、跳过常规
  // 管线。事务只对粘贴后 1s 内的首次对应 input 有效，其
  // 他情形顺延作废（防陈旧快照误伤后续正常编辑）。
  function musicPasteRecover(el) {
    const tx = musicPasteTx;
    if (!tx) return false;
    if (Date.now() - tx.at > 1000) { musicPasteTx = null; return false; }
    if (el.dataset.bid === tx.miBid) { musicPasteTx = null; return false; }
    const snap = tx.snaps.find((s) => s.el === el) || null;
    if (!snap) return false;
    musicPasteTx = null;
    const before = snap.text;
    const after = el.textContent || '';
    if (after === before) return false;
    let prefix = 0;
    while (prefix < before.length && prefix < after.length && before.charAt(prefix) === after.charAt(prefix)) prefix++;
    let bEnd = before.length, aEnd = after.length;
    while (bEnd > prefix && aEnd > prefix && before.charAt(bEnd - 1) === after.charAt(aEnd - 1)) { bEnd--; aEnd--; }
    const inserted = after.slice(prefix, aEnd);
    if (!/https?:\/\/\S+/i.test(inserted)) return false;
    el.innerHTML = snap.html;
    dioxus.send(JSON.stringify({ op: 'musicInput', id: tx.miBid, text: inserted, via: 'paste-recover' }));
    return true;
  }

  root.addEventListener('paste', (e) => {
    const el = editableOf(e);
    if (!el) return;
    const cd = e.clipboardData;
    if (!cd) return;
    // 跨块选区激活时粘贴 = 整段替换（纯文本，多行在模型侧成块）
    if (xsel) {
      const pt = cd.getData('text/plain');
      if (pt) { e.preventDefault(); sendReplace(pt); return; }
      clearXsel();
    }
    const text = cd.getData('text/plain');
    const trimmed = (text || '').trim();
    const URL_RE = /^https?:\/\/(www\.)?[-\u4e00-\u9fa5a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-\u4e00-\u9fa5a-zA-Z0-9()@:%_+.~#?&\/=]*)$/i;
    const URL_INLINE_RE = /https?:\/\/[-\u4e00-\u9fa5a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b[-a-zA-Z0-9()@:%_+.~#?&\/=]*/i;
    const MEDIA_RE = /music\.163\.com|163cn\.tv|y\.qq\.com|i\.y\.qq\.com|open\.spotify\.com|music\.apple\.com|b23\.tv|xiaohongshu\.com|xhslink\.com/i;
    const looksMd = (t) => /(^|\n)#{1,6}\s|(^|\n)[-*+]\s|(^|\n)\d+\.\s|(^|\n)>\s|`{1,3}|\*\*[^*]+\*\*|(^|[^*])\*[^*\n]+\*($|[^*])|__[^_]+__|~~[^~]+~~|!\[[^\]]*\]\([^)]+\)|\[[^\]]+\]\([^)]+\)|(^|\n)---+($|\n)|==[^=]+==|\[\[[^\]]+\]\]|\$\$[\s\S]+?\$\$|\$[^$\n]+\$/m.test(t);
    const inlineM = trimmed.match(URL_INLINE_RE);
    const embeddedUrl = inlineM ? inlineM[0] : null;
    const sendCard = (url, remain) => {
      const c = caretInfo(el);
      dioxus.send(JSON.stringify({ op: 'pasteCard', id: el.dataset.bid, url: url, remain: remain, before: c.beforeHtml, after: c.afterHtml }));
    };
    // B-9 分流（原版 handleEditorPaste 先于纯 URL 分支检查
    // 胶囊 engaged）：胶囊 engaged 而粘贴目标不是胶囊本尊、
    // 剪贴板含 URL 时，错位粘贴直接转交胶囊解析、不落邻块
    // 成文本；未被分流拦截而原生落地的粘贴由 beforeinput
    // 快照 + input 阶段回收兜底（见 musicPasteRecover）。
    if (el.dataset.btype !== 'musicInput') {
      const miEl = engagedMusicInput();
      if (miEl && trimmed && URL_INLINE_RE.test(trimmed)) {
        e.preventDefault();
        musicPasteTx = null;
        dioxus.send(JSON.stringify({ op: 'musicInput', id: miEl.dataset.bid, text: trimmed, via: 'paste-divert' }));
        return;
      }
    }
    if (el.dataset.btype === 'musicInput') {
      // 粘贴进音乐输入胶囊（原版 handleEditorPaste 口径）：含
      // URL 即拦截并走解析（胶囊随即被骨架替换）；不含 URL
      // 不拦截，原生粘贴落字后由 input 事件复检全文。
      const m = trimmed.match(URL_INLINE_RE);
      if (m) {
        e.preventDefault();
        dioxus.send(JSON.stringify({ op: 'musicInput', id: el.dataset.bid, text: trimmed, via: 'direct' }));
      }
      return;
    }
    if (trimmed && URL_RE.test(trimmed)) {
      e.preventDefault();
      sendCard(trimmed, '');
      return;
    }
    if (trimmed && embeddedUrl && MEDIA_RE.test(embeddedUrl)) {
      e.preventDefault();
      sendCard(embeddedUrl, '');
      return;
    }
    if (trimmed && embeddedUrl && !looksMd(trimmed)) {
      e.preventDefault();
      sendCard(embeddedUrl, trimmed.replace(embeddedUrl, '').trim());
      return;
    }
    const imgItems = cd.items ? Array.from(cd.items).filter((it) => it.kind === 'file' && it.type && it.type.indexOf('image/') === 0) : [];
    if (imgItems.length) {
      e.preventDefault();
      imgItems.forEach((it) => {
        const f = it.getAsFile();
        if (!f) return;
        const reader = new FileReader();
        reader.onload = () => {
          const b64 = String(reader.result || '').split(',')[1] || '';
          dioxus.send(JSON.stringify({ op: 'pasteImage', id: el.dataset.bid, name: f.name || 'image.png', mime: f.type || 'image/png', b64: b64 }));
        };
        reader.readAsDataURL(f);
      });
      return;
    }
    if (text) {
      e.preventDefault();
      // 粘贴只取纯文本、格式一律不带（有 text/html 也只用其
      // text/plain）——此点与原版同口径（editor.js:2147、
      // 2262-2270）。多行口径此前注释自述「进当前块成块内
      // 换行、不拆块」，与原版实测不符（audit_markdown_
      // slash §3.1 双侧实证）：原版按行拆块、换行零丢失；
      // 且旧路径 insertText 在 Chromium 把换行生成 <div>
      // 行元素、pasteSync 的 HTML 回读只映射 <br>→\n，
      // <div> 边界丢换行（首个 \n 黏连、预览坏死）。
      // 现口径：普通块多行走模型侧 pasteText 按行拆块
      // （首行并入当前块保其类型、余行成新段、末行接
      // 光标后内容；智能前缀随后只作用于首行所在块，
      // 「# 标题行\n正文」首块成标题、次块仍段落）；
      // 单行维持 insertText + pasteSync。md 源码态的
      // 换行是源码数据本身、不拆块，维持原通道。
      const btype = el.dataset.btype;
      if (btype !== 'mdsrc' && btype !== 'codeBlock') {
        const lines = text.replace(/\r\n?/g, '\n').split('\n');
        if (lines.length >= 2) {
          const c = caretInfo(el);
          dioxus.send(JSON.stringify({ op: 'pasteText', id: el.dataset.bid, before: c.beforeHtml, after: c.afterHtml, lines: lines }));
          return;
        }
      }
      document.execCommand('insertText', false, text);
      if (btype === 'mdsrc') {
        dioxus.send(JSON.stringify({ op: 'mdText', id: el.dataset.bid, text: el.innerText || '' }));
      } else if (btype !== 'codeBlock') {
        dioxus.send(JSON.stringify({ op: 'pasteSync', id: el.dataset.bid, html: el.innerHTML }));
      }
    }
  });

  const syncTimer = setInterval(() => {
    if (document.visibilityState === 'visible') {
      dioxus.send(JSON.stringify({ op: 'sync', map: collectSync() }));
    }
  }, 20000);
  bridgeDisposers.push(() => clearInterval(syncTimer));
  onGlobal(document, 'visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      dioxus.send(JSON.stringify({ op: 'sync', map: collectSync() }));
    }
  });

  const INLINE_ACTS = ['bold', 'italic', 'highlight', 'code', 'strikethrough'];
  let savedRange = null;
  onGlobal(document, 'selectionchange', () => {
    const sel = window.getSelection();
    if (sel.rangeCount) {
      const r = sel.getRangeAt(0);
      if (root.contains(r.startContainer)) savedRange = r.cloneRange();
    }
  });

  function restoreSel(el) {
    if (savedRange && el.contains(savedRange.startContainer)) {
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(savedRange);
      return true;
    }
    return false;
  }
  function caretBack(n) {
    const sel = window.getSelection();
    try { for (let i = 0; i < n; i++) sel.modify('move', 'backward', 'character'); } catch (_) {}
  }
  function rangeOffsets(el, range) {
    const pre = document.createRange();
    pre.selectNodeContents(el);
    pre.setEnd(range.startContainer, range.startOffset);
    return { start: pre.toString().length, len: range.toString().length };
  }
  function selectRange(el, start, len) {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n = walker.nextNode();
    let acc = 0, sNode = null, sOff = 0, eNode = null, eOff = 0;
    while (n) {
      const L = n.textContent.length;
      if (sNode === null && acc + L >= start) { sNode = n; sOff = start - acc; }
      if (acc + L >= start + len) { eNode = n; eOff = start + len - acc; break; }
      acc += L;
      n = walker.nextNode();
    }
    if (!sNode) return false;
    if (!eNode) { eNode = sNode; eOff = sOff; }
    const r = document.createRange();
    r.setStart(sNode, Math.min(sOff, sNode.textContent.length));
    r.setEnd(eNode, Math.min(eOff, eNode.textContent.length));
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
    return true;
  }
  function applyInline(act, el) {
    // 行内命令（斜杠审计 S3）：旧实现先 strip 再靠 execCommand
    // + savedRange 包裹——strip 改了文本节点后选区失效，包裹
    // 经常落空；无选区时加粗/斜体更是空转。新实现：剥离前先
    // 按偏移捕获选区，剥离后按偏移差重建选区，再手工包裹元素；
    // 无选区则插入带原版占位文「文字」的包裹，光标落其后。
    el.focus();
    const sel = window.getSelection();
    let range = null;
    if (sel.rangeCount && el.contains(sel.getRangeAt(0).startContainer)) {
      range = sel.getRangeAt(0);
    } else if (savedRange && el.contains(savedRange.startContainer)) {
      range = savedRange;
    }
    let start = -1, len = 0;
    if (range) {
      const o = rangeOffsets(el, range);
      start = o.start;
      len = o.len;
    }
    stripSlash(el);
    const strip = el.__mnStrip || { pos: 0, len: 0 };
    if (start >= 0) {
      if (start >= strip.pos + strip.len) start -= strip.len;
      else if (start > strip.pos) { len = Math.max(0, len - (strip.pos + strip.len - start)); start = strip.pos; }
      if (!selectRange(el, start, len) && len > 0) return el.innerHTML;
      // 选区首尾空白外置（批 1 MD-C5，斜杠审计 §2-④）：选区
      // 文本形如 " ab " 时直接包裹会存出 ** ab **——标记内
      // 侧带空白、预览不渲染粗体（斜/删/高亮/代码同病）。
      // 包裹前把选区收缩到实义核心，空白留在包裹元素之外；
      // 核心为空（全空白选区）时不收缩、回退原包裹。
      if (len > 0) {
        const selNow = window.getSelection();
        if (selNow.rangeCount && !selNow.getRangeAt(0).collapsed) {
          const selText = selNow.getRangeAt(0).toString();
          const lead = selText.length - selText.replace(/^\s+/, '').length;
          const trail = selText.length - selText.replace(/\s+$/, '').length;
          if ((lead > 0 || trail > 0) && lead + trail < selText.length) {
            selectRange(el, start + lead, len - lead - trail);
          }
        }
      }
    }
    const tag = act === 'bold' ? 'b'
      : act === 'italic' ? 'i'
      : act === 'strikethrough' ? 's'
      : act === 'code' ? 'code'
      : act === 'highlight' ? 'mark' : null;
    if (!tag) return el.innerHTML;
    const node = document.createElement(tag);
    if (tag === 'mark') node.className = 'mynote-highlight';
    const sel2 = window.getSelection();
    if (sel2.rangeCount && !sel2.getRangeAt(0).collapsed) {
      const r0 = sel2.getRangeAt(0);
      try { r0.surroundContents(node); }
      catch (_) { node.appendChild(r0.extractContents()); r0.insertNode(node); }
    } else if (sel2.rangeCount) {
      node.textContent = '文字';
      sel2.getRangeAt(0).insertNode(node);
    } else {
      node.textContent = '文字';
      el.appendChild(node);
    }
    const r = document.createRange();
    r.setStartAfter(node);
    r.collapse(true);
    sel2.removeAllRanges();
    sel2.addRange(r);
    return el.innerHTML;
  }
  window.__mnInline = (act, bid) => {
    const el = root.querySelector('[data-bid="' + bid + '"]');
    if (!el) return '';
    return applyInline(act, el);
  };
  window.__mnApplyLink = (url, bid) => {
    const el = root.querySelector('[data-bid="' + bid + '"]');
    if (!el) return '';
    el.focus();
    const had = restoreSel(el);
    const sel = window.getSelection();
    if (had && sel.rangeCount && !sel.getRangeAt(0).collapsed) {
      document.execCommand('createLink', false, url);
    } else {
      // 无选区（斜杠审计 S8，原版口径）：插入字面 Markdown
      // 链接 [链接文字](url)，不造以 URL 为文本的 <a>
      document.execCommand('insertText', false, '[链接文字](' + url + ')');
    }
    return el.innerHTML;
  };
  window.__mnFocus = (bid, offset) => {
    let tries = 0;
    // 聚焦平滑（调优评估衔接项）：落点后一帧检查光标 rect，
    // 出视口才做 block:'nearest' 最小滚动——原生 focus 滚动在
    // 本应用的 Safari 标签页几何下有帧级闪烁/不到位风险；不给
    // 块插入加高度动画（会与 contenteditable 光标打架）。
    const ensureVisible = (el, range) => {
      requestAnimationFrame(() => {
        const rects = range.getClientRects();
        const r = rects && rects.length ? rects[rects.length - 1] : el.getBoundingClientRect();
        if (r && (r.bottom > window.innerHeight - 8 || r.top < 8)) {
          el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
        }
      });
    };
    const attempt = () => {
      const el = root.querySelector('[data-bid="' + bid + '"]');
      if (!el) { if (tries++ < 10) setTimeout(attempt, 50); return; }
      el.focus();
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
      let remaining = offset;
      let n = walker.nextNode();
      let last = null;
      while (n) {
        last = n;
        if (remaining <= n.textContent.length) {
          const range = document.createRange();
          range.setStart(n, remaining);
          range.collapse(true);
          const sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(range);
          ensureVisible(el, range);
          return;
        }
        remaining -= n.textContent.length;
        n = walker.nextNode();
      }
      const range = document.createRange();
      if (last) range.setStart(last, last.textContent.length);
      else range.selectNodeContents(el);
      range.collapse(true);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      ensureVisible(el, range);
    };
    attempt();
  };
  window.__mnSetHtml = (bid, html, offset) => {
    const el = root.querySelector('[data-bid="' + bid + '"]');
    if (!el) return;
    el.innerHTML = html;
    window.__mnFocus(bid, offset);
  };
  // md 预览→源码的落点守卫（M9 复核）：目标源码块由 Dioxus
  // 在点击后异步挂载，且合并路径的 persist/物化 effect 会再
  // 触发重渲染换掉节点，固定延时（如旧实现 setTimeout 60ms）
  // 与之竞速、整段丢失聚焦（list-group 实测选区为空、active
  // 为 BODY）。改走确定性挂载信号：MutationObserver 守到可
  // 编辑目标出现即经 __mnFocus 落点，目标被重挂载替换则对
  // 新节点重落；守卫不按时间/帧数撤防（落点后一帧看似落稳、
  // 其后仍有重挂载的实测教训），只在用户接管时撤防——按键/
  // 点按/开始组字（capture 阶段先于本次输入的 DOM 变更，绝
  // 不与输入抢光标）、焦点转到其他块、或桥清理。全程无定时器。
  let mnMdFocusGuard = null;
  const disarmMdFocusGuard = () => {
    if (!mnMdFocusGuard) return;
    mnMdFocusGuard.observer.disconnect();
    mnMdFocusGuard = null;
  };
  bridgeDisposers.push(disarmMdFocusGuard);
  root.addEventListener('keydown', disarmMdFocusGuard, true);
  root.addEventListener('pointerdown', disarmMdFocusGuard, true);
  root.addEventListener('compositionstart', disarmMdFocusGuard, true);
  root.addEventListener('focusin', (e) => {
    if (!mnMdFocusGuard) return;
    const el = e.target && e.target.closest ? e.target.closest('[data-bid]') : null;
    if (el && el.dataset.bid !== mnMdFocusGuard.bid) disarmMdFocusGuard();
  }, true);
  window.__mnFocusAtMount = (bid, offset) => {
    disarmMdFocusGuard();
    const findTarget = () => {
      const el = root.querySelector('[data-bid="' + bid + '"]');
      return el && el.isContentEditable ? el : null;
    };
    const guard = { bid, observer: null, appliedEl: null };
    const apply = (el) => {
      guard.appliedEl = el;
      window.__mnFocus(bid, offset);
    };
    guard.observer = new MutationObserver(() => {
      if (mnMdFocusGuard !== guard) return;
      const el = findTarget();
      if (el && el !== guard.appliedEl) apply(el);
    });
    mnMdFocusGuard = guard;
    const now = findTarget();
    if (now) apply(now);
    guard.observer.observe(root, { childList: true, subtree: true });
  };
  // ---------- 块排序（iOS 桌面式长按拾起，新增能力） ----------
  // 原版 editor.js 有一套从未接线的拖拽实现（无元素被设
  // draggable、三个处理函数无引用、活体不可用）；这里以指
  // 针事件自建引擎，无拖柄：拾起的单元本体即浮块。触屏
  // 长按 480ms 拾起（文本块光标在本块内时不武装、选词
  // 接管）；桌面原子/组合块按下移动 ≥6px 拾起、文本块
  // 静止 hold 280ms 拾起（移动 >6px 视为选词、本次按下
  // 放弃）。拾起同帧震动反馈 + 玻璃抬升（.mn-lifted，
  // 轮廓圆角按块自身视觉面定形、拾起等距内收轻微缩小，
  // 见 liftShape/LIFT_INSET）；
  // 拖动由单一 rAF 循环驱动：浮块以 translate 属性跟指
  // （transform 只管拾起/落位的 scale 弹簧；拾起缩放为
  // 中心原点等距内收、抓握点位移由 translate 补偿，见
  // LIFT_INSET），落点按缓
  // 存 rect + 累计滚动量以最近中点规则判定，兄弟以
  // FLIP 链让位（--motion-reorder），边缘自动滚动同由
  // rAF 循环每帧步进（旧引擎只在 pointermove 时滚、手
  // 指停在边缘不滚）。松手浮块弹簧落位，落定同帧发
  // moveBlock{ids,to,sync} 给 Rust 重排落盘并清全部
  // transform（撤销栈由消息循环按结构性变化压栈）；取
  // 消（pointercancel/blur/Esc）走 --motion-reorder 曲
  // 线复位、不发 moveBlock。单元 = 栏/
  // 正文容器的直子元素；ids 解析序：data-bids（预览/列表
  // 组）> data-bid/data-wrapbid（直子自带）> 内嵌 [data-bid]
  // （todo 行/列表/标注的内层可编辑区，其 id 由 Rust
  // find_loc 解析到顶层块）。
  function unitBids(unit) {
    if (!unit || !unit.getAttribute) return null;
    const multi = unit.getAttribute('data-bids');
    if (multi) return multi.split(',').filter(Boolean);
    const own = unit.getAttribute('data-bid') || unit.getAttribute('data-wrapbid');
    if (own) return [own];
    const inner = unit.querySelector ? unit.querySelector('[data-bid]') : null;
    if (inner) return [inner.getAttribute('data-bid')];
    return null;
  }
  function unitOf(node) {
    const body = root.querySelector('.editor-body');
    if (!body || !node) return null;
    let el = node.nodeType === 1 ? node : node.parentElement;
    while (el && el !== body && el !== root) {
      const p = el.parentElement;
      if (!p) return null;
      if (p === body || (p.classList && p.classList.contains('editor-column'))) {
        return unitBids(el) ? el : null;
      }
      el = p;
    }
    return null;
  }
  function allUnits() {
    const body = root.querySelector('.editor-body');
    if (!body) return [];
    const out = [];
    const collect = (parent) => {
      for (const child of parent.children) {
        if (child.classList && child.classList.contains('editor-column')) { collect(child); continue; }
        if (unitBids(child)) out.push(child);
      }
    };
    collect(body);
    return out;
  }
  // ---------- 震动反馈（拾起/落位各一次，取消不调） ----------
  // Android 等有 navigator.vibrate 直接用；iOS Safari 无
  // vibrate，17.4 ≤ 版本 < 26.5 可借 switch 元素切换触
  // 发 Taptic（元素桥内惰性建一个常驻、视觉隐藏）；
  // iOS 27（用户设备）预期无震动，属平台限制。UA 解析
  // 失败静默。
  let hapticSwitch = null;
  function hapticTap() {
    try {
      if (navigator.vibrate) { navigator.vibrate(10); return; }
      const m = /CPU (?:iPhone )?OS (\d+)_(\d+)/.exec(navigator.userAgent || '');
      if (!m) return;
      const ver = parseFloat(m[1] + '.' + m[2]);
      if (!(ver >= 17.4 && ver < 26.5)) return;
      if (!hapticSwitch) {
        hapticSwitch = document.createElement('input');
        hapticSwitch.type = 'checkbox';
        hapticSwitch.setAttribute('switch', '');
        hapticSwitch.setAttribute('aria-hidden', 'true');
        hapticSwitch.tabIndex = -1;
        hapticSwitch.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;opacity:0;pointer-events:none;';
        document.body.appendChild(hapticSwitch);
        bridgeDisposers.push(() => { if (hapticSwitch) { hapticSwitch.remove(); hapticSwitch = null; } });
      }
      hapticSwitch.click();
    } catch (_) { /* 平台不支持时静默 */ }
  }

  let focusUnit = null;
  let drag = null;
  // focusUnit 只作「光标在本块内」判定（触屏文本块长按
  // 不武装的依据）；旧拖柄的 hover/click/scroll 刷新监听
  // 已随拖柄删除。
  root.addEventListener('focusin', (e) => { focusUnit = unitOf(e.target); });
  // 单元分类：data-bids 多块组与 todo/标注/列表等含内嵌
  // 可编辑区的为组合块；blk-wrap（data-wrapbid）为原子
  // 块；单元本体即 contenteditable 文本的为文本块；其
  // 余无可编辑内容的按原子块。
  function unitKind(u) {
    if (u.getAttribute('data-bids')) return 'composite';
    if (u.getAttribute('data-wrapbid')) return 'atomic';
    if (u.isContentEditable && u.getAttribute('data-bid')) return 'text';
    if (!u.querySelector('[data-bid]')) return 'atomic';
    return 'composite';
  }
  function caretInUnit(u) {
    if (focusUnit !== u) return false;
    const sel = window.getSelection();
    return !!(sel && sel.rangeCount && u.contains(sel.anchorNode));
  }

  function unitMetas() {
    let acc = 0;
    return allUnits().map((u) => {
      const bids = unitBids(u);
      const m = { u, bids, start: acc, count: bids.length, r: u.getBoundingClientRect() };
      acc += bids.length;
      return m;
    });
  }
  // 有效边距：单元自身边距与首/尾在流子元素的边距折叠
  // 穿透（祖先链无 padding/border 阻断时子边距 protrude
  // 到单元外，如音乐卡内层链接的 8px 上下边距穿透无
  // padding 的 wrap）取最大值——走查必须用有效边距，
  // 否则带卡片的单元落位会差一个穿透量。
  function inFlowEl(el) {
    const cs = getComputedStyle(el);
    return cs.display !== 'none' && cs.position !== 'absolute' && cs.position !== 'fixed' && cs.float === 'none';
  }
  function effMargin(el, top) {
    const prop = top ? 'marginTop' : 'marginBottom';
    let m = parseFloat(getComputedStyle(el)[prop]) || 0;
    let cur = el;
    while (cur) {
      const cs = getComputedStyle(cur);
      const pad = parseFloat(top ? cs.paddingTop : cs.paddingBottom) || 0;
      const bor = parseFloat(top ? cs.borderTopWidth : cs.borderBottomWidth) || 0;
      if (pad > 0 || bor > 0) break;
      const kids = cur.children;
      let child = null;
      if (top) { for (let i = 0; i < kids.length; i++) { if (inFlowEl(kids[i])) { child = kids[i]; break; } } }
      else { for (let i = kids.length - 1; i >= 0; i--) { if (inFlowEl(kids[i])) { child = kids[i]; break; } } }
      if (!child) break;
      const cm = parseFloat(getComputedStyle(child)[prop]) || 0;
      if (cm > m) m = cm;
      cur = child;
    }
    return m;
  }
  // 拾起时一次性缓存：全部单元 rect（视口坐标）、栏归
  // 属、上下有效边距、栏内容顶。拖动全程不逐帧量测单
  // 元，位置由缓存 + 累计滚动量（winDy/colDy）平移。栏
  // 内相邻间隙的成因（边距折叠 max / 边距相加 sum）逐
  // 栏以原始相邻对实测判定，落位走查据此精确复现提交
  // 后布局。
  function unitMetasExt() {
    const metas = unitMetas();
    const body = root.querySelector('.editor-body');
    const lists = new Map();
    let prev = null;
    for (const m of metas) {
      m.colEl = m.u.closest('.editor-column');
      const key = m.colEl || body;
      let list = lists.get(key);
      if (!list) {
        const kr = key.getBoundingClientRect();
        const padTop = parseFloat(getComputedStyle(key).paddingTop) || 0;
        list = { id: lists.size, el: m.colEl, colRect: kr, stackTop: kr.top + padTop, items: [] };
        lists.set(key, list);
      }
      m.list = list;
      m.mt = effMargin(m.u, true);
      m.mb = effMargin(m.u, false);
      m.leadGap = (prev && prev.list === list) ? (m.r.top - prev.r.bottom) : (m.r.top - list.stackTop);
      list.items.push(m);
      prev = m;
    }
    for (const list of lists.values()) {
      let maxScore = 0, sumScore = 0;
      for (let i = 1; i < list.items.length; i++) {
        const a = list.items[i - 1], b = list.items[i];
        const actual = b.r.top - (a.r.top + a.r.height);
        if (Math.abs(actual - Math.max(a.mb, b.mt)) <= 0.75) maxScore++;
        if (Math.abs(actual - (a.mb + b.mt)) <= 0.75) sumScore++;
      }
      list.gapMode = sumScore > maxScore ? 'sum' : 'max';
      const f = list.items[0];
      list.firstMode = !f ? 'mt' : (Math.abs(f.leadGap - f.mt) <= 0.75 ? 'mt' : (Math.abs(f.leadGap) <= 0.75 ? 'zero' : 'lead'));
    }
    return metas;
  }
  // FLIP 走查：算某栏在给定插入位下的新顶层位置（拾起
  // 时视口坐标）。items 内部排除拖块；insertPos<0 表示
  // 拖块不进本栏。相邻间隙按栏的实测边距模型计算（首
  // 元间隙按 firstMode：边距计入 / 折叠穿透为零 / 兜底
  // 用其实测 leadGap），使走查终点与提交后真实布局一致。
  function columnWalk(list, dragMeta, insertPos) {
    const items = list.items.filter((m) => m !== dragMeta);
    const order = [];
    for (let i = 0; i <= items.length; i++) {
      if (i === insertPos) order.push(dragMeta);
      if (i < items.length) order.push(items[i]);
    }
    const tops = new Map();
    let cursor = list.stackTop;
    let prev = null;
    for (const m of order) {
      let gap;
      if (!prev) gap = list.firstMode === 'zero' ? 0 : (list.firstMode === 'mt' ? m.mt : m.leadGap);
      else gap = list.gapMode === 'sum' ? (prev.mb + m.mt) : Math.max(prev.mb, m.mt);
      const top = cursor + gap;
      tops.set(m, top);
      cursor = top + m.r.height;
      prev = m;
    }
    return tops;
  }
  function metaRectNow(m) {
    const dy = drag.winDy + (m.colEl ? (drag.colDy.get(m.colEl) || 0) : 0);
    return { left: m.r.left, right: m.r.right, top: m.r.top - dy, bottom: m.r.bottom - dy, width: m.r.width, height: m.r.height };
  }
  // 落点：最近单元中点规则（与旧 dragTargetAt 同判定），
  // rect 吃缓存 + 累计滚动量。返回文档序插入下标与栏内
  // 插入位（不含拖块的该栏序）。
  function computeTarget(x, y) {
    if (!drag || !drag.metas.length) return null;
    let best = null;
    let bestDist = Infinity;
    let bestRect = null;
    for (const m of drag.metas) {
      const r = metaRectNow(m);
      const dx = x < r.left ? r.left - x : x > r.right ? x - r.right : 0;
      const dy = y < r.top ? r.top - y : y > r.bottom ? y - r.bottom : 0;
      const d = dx * dx + dy * dy;
      if (d < bestDist) { bestDist = d; best = m; bestRect = r; }
    }
    if (best === drag.meta) {
      const pos = best.list.items.indexOf(best);
      return { index: best.start, list: best.list, insertPos: pos, key: best.list.id + '|' + pos };
    }
    const before = y < bestRect.top + bestRect.height / 2;
    const items = best.list.items.filter((mm) => mm !== drag.meta);
    const refIdx = items.indexOf(best);
    const insertPos = before ? refIdx : refIdx + 1;
    return {
      index: before ? best.start : best.start + best.count,
      list: best.list,
      insertPos,
      key: best.list.id + '|' + insertPos,
    };
  }
  // 兄弟 FLIP 链：目标插入位变化时，对原栏与目标栏（同
  // 栏则一栏）走查，位移兄弟的 transform 更新为新旧顶
  // 差；过渡由 .mn-shift 类的 --motion-reorder 承担。
  function applyFlip(t) {
    const origin = drag.meta.list;
    const cols = t.list === origin ? [origin] : [origin, t.list];
    for (const col of cols) {
      const tops = columnWalk(col, drag.meta, col === t.list ? t.insertPos : -1);
      if (col === t.list) {
        drag.settleTopPickup = tops.get(drag.meta);
        drag.settleList = col;
        drag.settleLeft = col.items.length ? col.items[0].r.left : drag.meta.r.left;
      }
      for (const m of col.items) {
        if (m === drag.meta) continue;
        const dy = Math.round((tops.get(m) - m.r.top) * 10) / 10;
        if (drag.shifted.get(m) === dy) continue;
        drag.shifted.set(m, dy);
        m.u.classList.add('mn-shift');
        m.u.style.transform = dy ? 'translateY(' + dy + 'px)' : '';
      }
    }
  }
  // 边缘自动滚动（rAF 循环每帧调用）：栏判定与步进沿
  // 旧口径（独立滚动栏优先、64px 边缘带、每帧 12px），
  // 实际滚动量累积进 winDy/colDy 供缓存 rect 平移。
  function autoScrollStep(y, t) {
    const body = root.querySelector('.editor-body');
    const step = 12, edge = 64;
    if (t && t.list.el && body && body.classList.contains('is-independent-scroll')) {
      const col = t.list.el;
      if (col.scrollHeight > col.clientHeight) {
        const cr = { top: t.list.colRect.top - drag.winDy, bottom: t.list.colRect.bottom - drag.winDy };
        const before = col.scrollTop;
        if (y < cr.top + edge) col.scrollTop -= step;
        else if (y > cr.bottom - edge) col.scrollTop += step;
        const d = col.scrollTop - before;
        if (d) drag.colDy.set(col, (drag.colDy.get(col) || 0) + d);
        return !!d;
      }
    }
    const beforeY = window.scrollY;
    if (y < edge) window.scrollBy(0, -step);
    else if (y > window.innerHeight - edge) window.scrollBy(0, step);
    const dy = window.scrollY - beforeY;
    if (dy) drag.winDy += dy;
    return !!dy;
  }
  let suppressClickUntil = 0;
  // 拖动结束后的合成 click 抑制（捕获相先于既有块点击处理）：
  // 触摸长按拖完松手会再派 click，不拦会误触原子块的选中/
  // 边缘插段。
  root.addEventListener('click', (e) => {
    if (Date.now() < suppressClickUntil) {
      e.stopPropagation();
      e.preventDefault();
    }
  }, true);
  // ---------- 拾起 ----------
  // 拾起缩放：等距内收（卡片交互专项，用户口径）——缩放
  // 以本体中心为原点、双轴按宽高分别取值，使浮块四边与
  // 原位之间的间隙恒为 LIFT_INSET。此口径 supersede
  // fab40b5 的抓握点原点等比缩放：等比缩放的边间隙随块
  // 宽高比放大（宽卡左右近贴合、高卡上下悬殊），四边不
  // 等。抓握点不漂移靠平移补偿解耦（缩放归中心、跟随归
  // 平移，补偿量 = 抓握点因中心缩放产生的位移，见
  // pickup）。单点常量，手感调整只改这里。
  const LIFT_INSET = 4;
  const liftScaleFor = (dim) => dim > 0
    ? Math.max((dim - 2 * LIFT_INSET) / dim, 0.9) : 1;
  // 卡片浮层菜单覆盖面（卡片交互专项）：含可点子区域或
  // 后果动作的卡片类块。长按拾起/右键/悬停钮三路同开一
  // 个菜单（编辑 + 删除）；纯文本类块不入列。
  const CARD_MENU_TYPES = ['imgTextCard', 'imageTextRow', 'image', 'gallery', 'musicCard', 'link-card', 'attachment', 'video', 'divider'];
  // 拾起定形：浮起轮廓跟随块自身的形状与圆角，不套统
  // 一外形。拾起瞬间在单元后代里找视觉面——带可见面
  // （背景/背景滤镜/图片视频本体）且带圆角的块级元素，
  // 取面积最大者（卡片本体、图片、图文卡、文件行等皆
  // 由此命中）——把它的四角圆角（% 按其自身盒解析为
  // px）写入 lifted 单元内联，并以 clip-path 裁剪使玻
  // 璃填充贴合该形状（不用 overflow，理由见函数尾注）。
  // 无视觉面的块（纯文本、待办/列
  // 表组、图库网格等）不强加外形：圆角归零、玻璃面只
  // 顺块的矩形范围，最克制口径。
  function liftShape(unit) {
    const ur = unit.getBoundingClientRect();
    const uArea = ur.width * ur.height;
    if (uArea <= 0) { unit.style.borderRadius = '0px'; return; }
    let best = null;
    let bestArea = 0;
    const consider = (el) => {
      const cs = getComputedStyle(el);
      if (cs.display === 'inline') return;
      const bg = cs.backgroundColor;
      const bf = (cs.backdropFilter || cs.getPropertyValue('-webkit-backdrop-filter') || '').trim();
      const hasFace = (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent')
        || (bf !== '' && bf !== 'none')
        || el.tagName === 'IMG' || el.tagName === 'VIDEO';
      if (!hasFace) return;
      const corners = [cs.borderTopLeftRadius, cs.borderTopRightRadius,
        cs.borderBottomRightRadius, cs.borderBottomLeftRadius];
      if (!corners.some((c) => (c || '').split(/\s+/).some((t) => parseFloat(t) > 0))) return;
      const r = el.getBoundingClientRect();
      const area = r.width * r.height;
      if (area < uArea * 0.15 || area <= bestArea) return;
      bestArea = area;
      best = { corners, w: r.width, h: r.height };
    };
    consider(unit);
    unit.querySelectorAll('*').forEach(consider);
    if (!best) { unit.style.borderRadius = '0px'; return; }
    const hs = [], vs = [];
    for (const c of best.corners) {
      const toks = (c || '0px').trim().split(/\s+/);
      const res = (tok, base) => tok.endsWith('%')
        ? (parseFloat(tok) / 100 * base) + 'px' : tok;
      hs.push(res(toks[0], best.w));
      vs.push(res(toks.length > 1 ? toks[1] : toks[0], best.h));
    }
    const rad = hs.every((v, i) => v === vs[i])
      ? hs.join(' ')
      : hs.join(' ') + ' / ' + vs.join(' ');
    unit.style.borderRadius = rad;
    // 裁剪跟形走 clip-path（纯视觉，不建格式化上下文）：
    // 旧 overflow:hidden 会让子边距由折叠变包含、单元盒
    // 在拾起瞬间增高（.atomic 上下 8px 边距实测 +16.5px、
    // 只向下生长），拾起四边间隙与落点量测随之全偏——
    // 等距内收口径下该增高直接表现为底边间隙负值，实测
    // 定性后改此（卡片交互专项）。
    unit.style.clipPath = 'inset(0 round ' + rad + ')';
  }
  function pickup(unit, pointerId, x, y) {
    const bids = unitBids(unit);
    if (!bids || !bids.length) return false;
    const metas = unitMetasExt();
    const meta = metas.find((m) => m.u === unit);
    if (!meta) return false;
    teardownDrag();
    drag = {
      unit, bids, pointerId, sx: x, sy: y, x, y,
      start: meta.start, count: meta.count,
      metas, meta,
      phase: 'drag', targetIndex: meta.start, target: null,
      insertKey: meta.list.id + '|' + meta.list.items.indexOf(meta),
      settleTopPickup: meta.r.top, settleList: meta.list, settleLeft: meta.r.left,
      winDy: 0, colDy: new Map(), shifted: new Map(), raf: 0,
      settleTimer: 0, returnTimer: 0,
      liftComp: { x: 0, y: 0 }, menuShown: false,
    };
    hapticTap();
    liftShape(unit);
    // 等距内收定形：中心原点 + 双轴 scale（四边间隙恒为
    // LIFT_INSET，极小单元按轴钳制 scale ≥ 0.9 防压扁）；
    // 抓握点（钳制在盒内）因中心缩放产生的位移由
    // liftComp 平移补偿——translate 与 transform 同弹簧
    // 同帧推进，补偿量随缩放进度成比例，抓握点全程不漂
    // 移（位移公式 (g-c)·(1-s)，见 LIFT_INSET 注）。
    const gw = meta.r.width, gh = meta.r.height;
    const lsx = liftScaleFor(gw), lsy = liftScaleFor(gh);
    const gx = Math.min(Math.max(x - meta.r.left, 0), gw);
    const gy = Math.min(Math.max(y - meta.r.top, 0), gh);
    const compX = (gx - gw / 2) * (1 - lsx);
    const compY = (gy - gh / 2) * (1 - lsy);
    drag.liftComp = { x: compX, y: compY };
    unit.style.transformOrigin = '50% 50%';
    unit.classList.add('mn-lifted');
    unit.style.transition = 'translate var(--motion-pop) var(--motion-spring), transform var(--motion-pop) var(--motion-spring)';
    unit.style.translate = compX + 'px ' + compY + 'px';
    unit.style.transform = 'scale(' + lsx + ', ' + lsy + ')';
    // 卡片浮层菜单（卡片交互专项）：覆盖面内的原子单元
    // 拾起即贴卡弹出菜单；手指转入拖动（位移 >10px）由
    // dragMove 收起，原地松手留存待点选。非覆盖单元拾起
    // 时关掉可能残留的菜单。
    const wtype0 = unit.getAttribute('data-wtype') || '';
    if (unit.classList.contains('blk-wrap') && CARD_MENU_TYPES.indexOf(wtype0) >= 0) {
      drag.menuShown = true;
      dioxus.send(JSON.stringify({ op: 'cardMenu', id: bids[0], wtype: wtype0, anchor: 'card', rect: [meta.r.left, meta.r.top, meta.r.width, meta.r.height] }));
    } else {
      dioxus.send(JSON.stringify({ op: 'cardMenuHide' }));
    }
    document.body.classList.add('mn-drag-active');
    dioxus.send(JSON.stringify({ op: 'drag', note: 'pickup' }));
    window.addEventListener('pointermove', dragMove, true);
    window.addEventListener('pointerup', dragUp, true);
    window.addEventListener('pointercancel', dragCancelEv, true);
    window.addEventListener('keydown', dragEsc, true);
    window.addEventListener('blur', dragBlur);
    drag.raf = requestAnimationFrame(dragFrame);
    return true;
  }
  function dragMove(e) {
    if (!drag || e.pointerId !== drag.pointerId || drag.phase !== 'drag') return;
    drag.x = e.clientX; drag.y = e.clientY;
    // 手指转入拖动：拾起时弹出的卡片菜单自动收起，排序
    // 照常（卡片交互专项；阈值与触屏按压取消同量级）。
    if (drag.menuShown
      && (Math.abs(drag.x - drag.sx) > 10 || Math.abs(drag.y - drag.sy) > 10)) {
      drag.menuShown = false;
      dioxus.send(JSON.stringify({ op: 'cardMenuHide' }));
    }
    e.preventDefault();
  }
  // 单一 rAF 循环：落点（先按当前滚动算、滚动后同帧重
  // 算）→ FLIP 链 → 浮块跟指（translate 属性，无过渡、
  // 逐帧精确；transform 的 scale 弹簧只在拾起/落位动）。
  function stepDrag() {
    let t = computeTarget(drag.x, drag.y);
    if (autoScrollStep(drag.y, t)) {
      const t2 = computeTarget(drag.x, drag.y);
      if (t2) t = t2;
    }
    if (!t) return;
    drag.targetIndex = t.index;
    drag.target = t;
    if (t.key !== drag.insertKey) {
      drag.insertKey = t.key;
      applyFlip(t);
    }
    // 跟随 = 拾起补偿（恒定）+ 指针位移：缩放归中心、跟
    // 随归平移，两者解耦（卡片交互专项，见 pickup）。
    drag.unit.style.translate = (drag.liftComp.x + drag.x - drag.sx) + 'px ' + (drag.liftComp.y + drag.y - drag.sy) + 'px';
  }
  function dragFrame() {
    if (!drag || drag.phase !== 'drag') return;
    stepDrag();
    drag.raf = requestAnimationFrame(dragFrame);
  }
  // ---------- 落位（提交） ----------
  function dragUp(e) {
    if (!drag || e.pointerId !== drag.pointerId) return;
    if (drag.phase === 'drag') settleDrag();
  }
  function settleDrag() {
    const d = drag;
    d.phase = 'settle';
    // 尾随 click 在 pointerup 后立即派发，抑制窗口须此刻
    // 武装；等落位完成（220ms 后）再武装会漏掉它，图片
    // 块会被误开图。
    suppressClickUntil = Date.now() + 400;
    cancelAnimationFrame(d.raf);
    window.removeEventListener('pointermove', dragMove, true);
    const originDy = d.meta.colEl ? (d.colDy.get(d.meta.colEl) || 0) : 0;
    const settleDy = d.settleList.el ? (d.colDy.get(d.settleList.el) || 0) : 0;
    const layoutTop = d.meta.r.top - d.winDy - originDy;
    const desiredTop = d.settleTopPickup - d.winDy - settleDy;
    d.settleDesiredTop = desiredTop;
    const fx = d.settleLeft - d.meta.r.left;
    const fy = desiredTop - layoutTop;
    d.unit.style.transition = 'translate 220ms var(--motion-spring), transform 220ms var(--motion-spring)';
    d.unit.style.translate = fx + 'px ' + fy + 'px';
    d.unit.style.transform = 'scale(1)';
    d.unit.addEventListener('transitionend', onSettleEnd);
    d.settleTimer = setTimeout(() => settleFallback(0), 300);
  }
  function onSettleEnd(e) {
    if (e.propertyName !== 'translate' && e.propertyName !== 'transform') return;
    finishCommit();
  }
  // 兜底：transitionend 未达时不硬提交——先量浮块是否已
  // 收敛到目标位（帧钟慢于墙钟的环境里过渡会晚于定时
  // 器），未收敛则续等，收敛或续等超限才提交。
  function settleFallback(n) {
    const d = drag;
    if (!d || d.phase !== 'settle') return;
    const r = d.unit.getBoundingClientRect();
    if (Math.abs(r.top - d.settleDesiredTop) <= 1 || n >= 5) { finishCommit(); return; }
    d.settleTimer = setTimeout(() => settleFallback(n + 1), 120);
  }
  function finishCommit() {
    const d = drag;
    if (!d || d.phase !== 'settle') return;
    d.phase = 'done';
    clearTimeout(d.settleTimer);
    d.unit.removeEventListener('transitionend', onSettleEnd);
    removeDragListeners();
    // 下标未变不发（目标仍在自身跨度内即原地落位）。
    if (d.targetIndex < d.start || d.targetIndex > d.start + d.count) {
      dioxus.send(JSON.stringify({ op: 'moveBlock', ids: d.bids, to: d.targetIndex, sync: collectSync() }));
    }
    dioxus.send(JSON.stringify({ op: 'drag', note: 'drop' }));
    hapticTap();
    teardownDragVisual();
    drag = null;
  }
  // ---------- 取消（复位，不发 moveBlock） ----------
  function dragCancelEv() { cancelDrag(); }
  function dragBlur() { cancelDrag(); }
  function dragEsc(e) { if (e.key === 'Escape') cancelDrag(); }
  function cancelDrag() {
    const d = drag;
    if (!d || (d.phase !== 'drag' && d.phase !== 'settle')) return;
    d.phase = 'return';
    if (d.menuShown) {
      d.menuShown = false;
      dioxus.send(JSON.stringify({ op: 'cardMenuHide' }));
    }
    cancelAnimationFrame(d.raf);
    clearTimeout(d.settleTimer);
    d.unit.removeEventListener('transitionend', onSettleEnd);
    window.removeEventListener('pointermove', dragMove, true);
    d.unit.style.transition = 'translate 260ms var(--motion-reorder), transform 260ms var(--motion-reorder)';
    d.unit.style.translate = '0px 0px';
    d.unit.style.transform = 'scale(1)';
    for (const [m] of d.shifted) { m.u.style.transform = ''; }
    dioxus.send(JSON.stringify({ op: 'drag', note: 'cancel' }));
    suppressClickUntil = Date.now() + 400;
    d.unit.addEventListener('transitionend', onReturnEnd);
    d.returnTimer = setTimeout(finishCancel, 340);
  }
  function onReturnEnd(e) {
    if (e.propertyName !== 'translate' && e.propertyName !== 'transform') return;
    finishCancel();
  }
  function finishCancel() {
    const d = drag;
    if (!d || d.phase !== 'return') return;
    d.phase = 'done';
    clearTimeout(d.returnTimer);
    d.unit.removeEventListener('transitionend', onReturnEnd);
    removeDragListeners();
    teardownDragVisual();
    drag = null;
  }
  function removeDragListeners() {
    window.removeEventListener('pointermove', dragMove, true);
    window.removeEventListener('pointerup', dragUp, true);
    window.removeEventListener('pointercancel', dragCancelEv, true);
    window.removeEventListener('keydown', dragEsc, true);
    window.removeEventListener('blur', dragBlur);
  }
  function teardownDragVisual() {
    const d = drag;
    if (!d) return;
    d.unit.style.transition = 'none';
    d.unit.style.transform = '';
    d.unit.style.translate = '';
    d.unit.style.transformOrigin = '';
    d.unit.style.borderRadius = '';
    d.unit.style.clipPath = '';
    d.unit.style.transition = '';
    d.unit.classList.remove('mn-lifted');
    for (const [m] of d.shifted) {
      m.u.style.transform = '';
      m.u.classList.remove('mn-shift');
    }
    document.body.classList.remove('mn-drag-active');
  }
  function teardownDrag() {
    if (!drag) return;
    cancelAnimationFrame(drag.raf);
    clearTimeout(drag.settleTimer);
    clearTimeout(drag.returnTimer);
    drag.unit.removeEventListener('transitionend', onSettleEnd);
    drag.unit.removeEventListener('transitionend', onReturnEnd);
    removeDragListeners();
    teardownDragVisual();
    drag = null;
  }
  bridgeDisposers.push(() => { teardownDrag(); clearPress(); });
  // ---------- 按压状态机（起拖手势） ----------
  let press = null;
  function clearPress() {
    if (!press) return;
    if (press.timer) clearTimeout(press.timer);
    if (press.noSelectEl) press.noSelectEl.style.userSelect = '';
    press = null;
  }
  root.addEventListener('pointerdown', (e) => {
    // 卡片编辑态退出（卡片交互专项）：点编辑卡之外的区
    // 域即退出编辑态（点菜单面板本身不退——点「编辑」进
    // 入另一卡由菜单处理覆盖同一信号；点编辑卡自身不
    // 退）。卡自身的会话层（图文底表/灯箱——从该卡打开、
    // 关后应回到该卡的编辑会话）不算卡外。与按压状态机
    // 相互独立，先于其判定。
    const edEl = root.querySelector('.blk-wrap.card-editing');
    if (edEl && e.target && !edEl.contains(e.target)
      && !(e.target.closest && e.target.closest('.card-menu-panel, .image-text-sheet, .image-text-sheet-backdrop, .lightbox'))) {
      dioxus.send(JSON.stringify({ op: 'cardEditExit' }));
    }
    clearPress();
    if (drag || composing || e.isPrimary === false) return;
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    const t = e.target;
    if (!t || !t.closest) return;
    if (t.closest('button, input, textarea, select, label, .todo-checkbox')) return;
    const u = unitOf(t);
    if (!u) return;
    const kind = unitKind(u);
    if (e.pointerType === 'mouse') {
      press = { unit: u, pointerId: e.pointerId, x: e.clientX, y: e.clientY, type: 'mouse', kind, timer: 0 };
      if (kind === 'text') {
        // 文本块静止 hold 280ms 拾起；拾起瞬间选区锚在
        // 本块则清选区（浮块不带选区走）。
        press.timer = setTimeout(() => {
          const p = press;
          clearPress();
          if (!p || composing) return;
          const sel = window.getSelection();
          if (sel && sel.rangeCount && p.unit.contains(sel.anchorNode)) sel.removeAllRanges();
          pickup(p.unit, p.pointerId, p.x, p.y);
        }, 280);
      }
    } else {
      // touch / pen 长按 480ms：文本块光标在本块内不武
      // 装（选词接管）；光标不在本块时按下即给该单元临
      // 时 user-select:none，防系统选区抢跑（仅本次按压，
      // 双击选词不受影响）。
      if (kind === 'text' && caretInUnit(u)) return;
      press = { unit: u, pointerId: e.pointerId, x: e.clientX, y: e.clientY, type: 'touch', kind, timer: 0 };
      if (kind === 'text') { u.style.userSelect = 'none'; press.noSelectEl = u; }
      press.timer = setTimeout(() => {
        const p = press;
        clearPress();
        if (!p || composing) return;
        pickup(p.unit, p.pointerId, p.x, p.y);
      }, 480);
    }
  });
  root.addEventListener('pointermove', (e) => {
    if (!press || e.pointerId !== press.pointerId) return;
    const dx = e.clientX - press.x, dy = e.clientY - press.y;
    const d2 = dx * dx + dy * dy;
    if (press.type === 'touch') {
      if (d2 > 100) clearPress();
      return;
    }
    // 桌面：原子/组合块移动 ≥6px 即拾起；文本块 hold 中
    // 移动 >6px = 选词，本次按下永久放弃（不再武装，待
    // 下次 pointerdown）。
    if (press.kind === 'text') {
      if (d2 > 36) clearPress();
    } else if (d2 >= 36) {
      const p = press;
      clearPress();
      if (pickup(p.unit, p.pointerId, p.x, p.y) && drag) {
        drag.x = e.clientX; drag.y = e.clientY;
      }
    }
  });
  root.addEventListener('pointerup', clearPress);
  root.addEventListener('pointercancel', clearPress);
  // 触摸拖动期间禁滚（非被动 touchmove 的 preventDefault 是
  // 指针事件下唯一可靠的止滚手段）。
  root.addEventListener('touchmove', (e) => {
    if (drag) e.preventDefault();
  }, { passive: false });
  // 原生拖拽拦截：press 武装或拖动中时，图片/链接的浏
  // 览器原生拖拽会以 pointercancel 抢走手势，编辑区内一
  // 律拦下；无 press 的场合（如已成形的选区被直接拖动）
  // 不拦，保留原生文本拖放。外部文件拖入走 dragover/
  // drop，不受 dragstart 拦截影响。
  root.addEventListener('dragstart', (e) => {
    if ((drag || press) && e.target && e.target.closest && e.target.closest('.editor-body')) e.preventDefault();
  });

  window.__mnSyncAll = () => collectSync();
  window.__mnStripSlash = (bid) => {
    const el = root.querySelector('[data-bid="' + bid + '"]');
    if (!el) return '';
    stripSlash(el);
    return el.innerHTML;
  };
  // 斜杠面板滚动跟随（滚动审计 S3）：返回光标当前视口 rect
  // （选区不在该块内时兜底用块 rect）
  window.__mnSlashAnchor = (bid) => {
    const el = root.querySelector('[data-bid="' + bid + '"]');
    if (!el) return null;
    const sel = window.getSelection();
    if (sel && sel.rangeCount) {
      const rng = sel.getRangeAt(0);
      if (el.contains(rng.startContainer)) {
        const rects = rng.getClientRects();
        if (rects.length) {
          const cr = rects[rects.length - 1];
          return { x: cr.left, y: cr.top, b: cr.bottom };
        }
      }
    }
    const r = el.getBoundingClientRect();
    return { x: r.left, y: r.top, b: r.bottom };
  };
  return null;
"#;


/// 编辑器卸载的同步清理（use_drop 闭包内直调，绝不 spawn）：
/// ① 调 JS 侧 __mnBgCleanup（撤 #body-before-bg 顶部渐变样式、
/// 背景滚动监听与 scheme matchMedia 监听，置
/// __mnBgActive=false）；② 摘除具名全局监听
/// __mnEdScroll（window scroll）/__mnEsc（document keydown
/// capture）/__mnTypedMark（document input capture）/
/// __mnResume（visibilitychange/pageshow/focus 回前台补完）
/// 并置 null；
/// ③ 调桥的 __mnBridgeCleanup（摘 document/window/
/// visualViewport 全部桥监听、清 20s 同步定时器、桥 window
/// 入口置 null，幂等自清）；④ 调 __mnWideCleanup（摘 wide
/// matchMedia 监听）。③④ 是页面副作用审计泄漏 2/3 的根治：
/// 桥与两处 matchMedia 旧实现全是匿名登记、跨挂载线性累积。
/// 全部 web_sys/js_sys 同步执行——卸载后组件作用域消失，任何
/// 异步清理（spawn+eval）都会被取消、永不落地（实测教训）。
/// html/body 根背景不在此处处理：已改由 App 外壳派生（main.rs）。
pub(super) fn sync_editor_cleanup() {
    let Some(w) = web_sys::window() else { return };
    let wv: &wasm_bindgen::JsValue = w.as_ref();
    let null = wasm_bindgen::JsValue::NULL;
    // ① 顶部渐变系统清理（JS 闭包自带摘监听/删样式元素）
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnBgCleanup".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call0(wv);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnBgCleanup".into(), &null);
    let _ = js_sys::Reflect::set(wv, &"__mnBgUpdate".into(), &null);
    // ③ JS 桥全局登记清理（幂等：调用后自置 null）
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnBridgeCleanup".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call0(wv);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnBridgeCleanup".into(), &null);
    // ④ wide matchMedia 监听清理（幂等：调用后自置 null）
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnWideCleanup".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call0(wv);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnWideCleanup".into(), &null);
    // ② window scroll 监听
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnEdScroll".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = w.remove_event_listener_with_callback("scroll", func);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnEdScroll".into(), &null);
    // ③ document capture 监听（Esc / typed 标记）
    if let Some(d) = w.document() {
        if let Ok(f) = js_sys::Reflect::get(wv, &"__mnEsc".into()) {
            if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                let _ = d.remove_event_listener_with_callback_and_bool("keydown", func, true);
            }
        }
        let _ = js_sys::Reflect::set(wv, &"__mnEsc".into(), &null);
        if let Ok(f) = js_sys::Reflect::get(wv, &"__mnResume".into()) {
            if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                let _ = d.remove_event_listener_with_callback("visibilitychange", func);
                let _ = w.remove_event_listener_with_callback("pageshow", func);
                let _ = w.remove_event_listener_with_callback("focus", func);
            }
        }
        let _ = js_sys::Reflect::set(wv, &"__mnResume".into(), &null);
        if let Ok(f) = js_sys::Reflect::get(wv, &"__mnTypedMark".into()) {
            if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                let _ = d.remove_event_listener_with_callback_and_bool("input", func, true);
            }
        }
        let _ = js_sys::Reflect::set(wv, &"__mnTypedMark".into(), &null);
    }
    diag::log("EDIT", "editor cleanup sync done");
}
