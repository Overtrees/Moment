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
    window.__mnSetHtml = null;
    window.__mnSyncAll = null;
    window.__mnStripSlash = null;
    window.__mnSlashAnchor = null;
  };

  let composing = false;
  root.addEventListener('compositionstart', () => { composing = true; });
  root.addEventListener('compositionend', () => { composing = false; });

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
    const er = el.getBoundingClientRect();
    const lh = rect.height || 24;
    if (key === 'ArrowUp') {
      if (rect.top - er.top >= lh * 0.9 || idx === 0) return false;
      e.preventDefault();
      const target = blocks[idx - 1];
      const tr = target.getBoundingClientRect();
      if (!setCaretByPoint(target, rect.left, tr.bottom - lh * 0.4)) setCaretEdge(target, true);
    } else {
      if (er.bottom - rect.bottom >= lh * 0.9 || idx === blocks.length - 1) return false;
      e.preventDefault();
      const target = blocks[idx + 1];
      const tr = target.getBoundingClientRect();
      if (!setCaretByPoint(target, rect.left, tr.top + lh * 0.4)) setCaretEdge(target, false);
    }
    dioxus.send(JSON.stringify({ op: 'caretMove', dir: key === 'ArrowUp' ? 'up' : 'down', id: el.dataset.bid }));
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

  root.addEventListener('keydown', (e) => {
    const el = editableOf(e);
    if (!el) return;
    // 组合输入守卫必须最先（原版 editor.js:2026 同口径）：面板
    // 开着时用拼音打过滤词，组合中的回车/方向键是给输入法的，
    // 绝不能被面板分支抢走应用命令（编辑态审计 D3）。
    if (composing || e.isComposing) return;
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
    if ((e.metaKey || e.ctrlKey) && !composing && !e.isComposing) {
      const k = e.key.toLowerCase();
      if (k === 'z' || k === 'y') {
        // 撤销/重做必须由应用接管（编辑态审计 D2）：放行浏览器
        // 原生 undo 只会改当前块 DOM、与模型脱节，随后 autosync
        // 还会把脱节结果落库。随消息带上全量同步与当前光标，
        // Rust 侧压栈回退并恢复焦点（D4）。
        e.preventDefault();
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

  // 标题组合期布局同步（原版 syncTitleCompositionLayout 的移植）：
  // 组合期间不走 Rust 状态，直接按文本长度改胶囊/滚动区/标题
  // 的内联样式（单向升级：>5 长标题、>11 横向溢出），失焦/组合
  // 结束时由 Rust 侧清掉内联样式回到类驱动。
  function syncTitleLayout(el) {
    const len = (el.textContent || '').length;
    const isLong = len > 5;
    const isOverflow = len > 11;
    const scroller = el.parentElement;
    const capsule = scroller && scroller.parentElement;
    if (!scroller || !capsule) return;
    capsule.style.width = isOverflow ? '184px' : 'auto';
    capsule.style.padding = isLong ? '6px 18px' : '0px 20px';
    scroller.style.width = isOverflow ? '100%' : 'auto';
    scroller.style.minWidth = '0';
    scroller.style.maxWidth = '100%';
    scroller.style.boxSizing = 'border-box';
    scroller.style.paddingLeft = isOverflow ? '16px' : '0px';
    scroller.style.paddingRight = isOverflow ? '16px' : '0px';
    scroller.style.scrollPaddingInline = isOverflow ? '16px' : '0px';
    el.style.fontSize = isLong ? '11px' : '14px';
    el.style.whiteSpace = isOverflow ? 'nowrap' : isLong ? 'normal' : 'nowrap';
    el.style.wordBreak = !isOverflow && isLong ? 'break-all' : 'normal';
    el.style.textAlign = isOverflow ? 'left' : 'center';
    el.style.minWidth = isOverflow ? 'max-content' : 'auto';
    el.style.paddingRight = '0px';
  }

  root.addEventListener('compositionupdate', (e) => {
    if (e.target && e.target.id === 'editor-title-text') syncTitleLayout(e.target);
  });

  root.addEventListener('compositionend', (e) => {
    // 标题组合输入结束：提交全文（组合期间 input 不提交，同原版）
    if (e.target && e.target.id === 'editor-title-text') {
      dioxus.send(JSON.stringify({ op: 'titleText', text: e.target.textContent || '' }));
    }
  });

  root.addEventListener('input', (e) => {
    if (e.target && e.target.id === 'editor-title-text') {
      if (composing) syncTitleLayout(e.target);
      else dioxus.send(JSON.stringify({ op: 'titleText', text: e.target.textContent || '' }));
      return;
    }
    const el = editableOf(e);
    if (!el || composing) return;
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
    if (query !== null && !/\s/.test(query)) {
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
  });

  root.addEventListener('focusin', (e) => {
    const el = editableOf(e);
    if (el) dioxus.send(JSON.stringify({ op: 'focusBlock', id: el.dataset.bid }));
  });

  // 最近一次指针是否落在编辑区内（S8 判定用）：分块架构下
  // 点原子块会让焦点落到 body，单看 activeElement 分不清
  // 「还在编辑区里点按」与「点外面收键盘」；原版单宿主靠焦
  // 点包含关系区分，这里用最近指针位置合成同一判定。
  let lastPointerInEditor = 0;
  root.addEventListener('pointerdown', (e) => {
    lastPointerInEditor = e.target && e.target.closest && e.target.closest('.editor-body, .editor-title-dock') ? Date.now() : 0;
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

  // 原子块点击（原版 use-editor-dom.js 的边缘区语义）：点块体
  // 左右 28px 边带 = 在块前/块后落段；点中央 = 选中该块（块
  // 操作钮只在选中后出现）。按钮/链接/图片（灯箱）/图文文本
  // 区（开面板）各自的行为优先，不发消息。
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
    if (t.closest('[contenteditable="true"], .itc-text')) {
      dioxus.send(JSON.stringify({ op: 'clearSelect' }));
      return;
    }
    const r = wrap.getBoundingClientRect();
    const x = e.clientX - r.left;
    if (x < 28) {
      dioxus.send(JSON.stringify({ op: 'insertPara', id: bid, where: 'before' }));
      return;
    }
    if (x > r.width - 28) {
      dioxus.send(JSON.stringify({ op: 'insertPara', id: bid, where: 'after' }));
      return;
    }
    // 链接（音乐成品卡）保持跳转；图片保持灯箱（图片块的既有
    // 行为），同时选中该块——关掉灯箱后块操作钮就在原地。
    if (t.closest('a')) return;
    dioxus.send(JSON.stringify({ op: 'selectBlock', id: bid }));
  });

  // 选中态的键盘删除（原版单一编辑器里原子块随选区 Delete；
  // 分块架构下由选中态承载）：焦点不在可编辑区时 Backspace/
  // Delete 删选中块，Escape 取消选中。
  root.addEventListener('keydown', (e) => {
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

  root.addEventListener('paste', (e) => {
    const el = editableOf(e);
    if (!el) return;
    const cd = e.clipboardData;
    if (!cd) return;
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
    if (el.dataset.btype === 'musicInput') {
      // 粘贴进音乐输入胶囊（原版 handleEditorPaste 口径）：含
      // URL 即拦截并走解析（胶囊随即被骨架替换）；不含 URL
      // 不拦截，原生粘贴落字后由 input 事件复检全文。
      const m = trimmed.match(URL_INLINE_RE);
      if (m) {
        e.preventDefault();
        dioxus.send(JSON.stringify({ op: 'musicInput', id: el.dataset.bid, text: trimmed }));
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
      // 原版口径（编辑态审计 B9；editor.js:2147、2262-2270）：
      // 粘贴只取纯文本、格式一律不带（有 text/html 也只用其
      // text/plain）；多行进当前块成块内换行（\n），不拆块。
      // md 源码态同理走纯文本落位并按源码通道同步。
      document.execCommand('insertText', false, text);
      if (el.dataset.btype === 'mdsrc') {
        dioxus.send(JSON.stringify({ op: 'mdText', id: el.dataset.bid, text: el.innerText || '' }));
      } else if (el.dataset.btype !== 'codeBlock') {
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

  // 标题光标跟随（原版 scheduleTitleCaretSync，滚动审计 S6）：
  // 标题处于横向溢出态时，只调滚动区的 scrollLeft 让光标保持
  // 在左右 16px 边距内——不碰选区本身，故不会引起光标跳动；
  // 双 rAF 合并快速输入期的多次请求。光标 x 按相邻字形边界
  // 测（折叠 Range 的 rect 会把前一字形宽算进去，原版同法）。
  let titleCaretFrame = null;
  function syncTitleCaret() {
    if (titleCaretFrame !== null) return;
    titleCaretFrame = requestAnimationFrame(() => {
      titleCaretFrame = requestAnimationFrame(() => {
        titleCaretFrame = null;
        const el = document.getElementById('editor-title-text');
        if (!el || document.activeElement !== el) return;
        const scroller = el.parentElement;
        if (!scroller) return;
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount || !el.contains(sel.focusNode)) return;
        // 光标 x 解析（原版 scheduleTitleCaretSync 全量口径）：
        // 折叠选区的锚点有两种形态——文本节点锚（打字产生）与
        // 元素节点锚（聚焦事务 selectNodeContents+collapse 产
        // 生，正是二次聚焦后的形态）。元素锚的折叠 Range rect
        // 在 Chromium 实测为全零（left/height 均为 0），旧简化
        // 版只认文本锚、元素锚退到 Range rect 后因高度 0 静默
        // 返回——二次聚焦时长标题光标落在胶囊外、scrollLeft
        // 永远停在 0，左右留空就此失衡。原版用 findEdgeText
        // 把元素锚落到相邻文本节点的字形边界上量 x，此处补齐。
        function findEdgeText(node, fromEnd) {
          if (!node) return null;
          if (node.nodeType === 3) return node.length ? node : null;
          const children = Array.prototype.slice.call(node.childNodes || []);
          if (fromEnd) children.reverse();
          for (const child of children) {
            const found = findEdgeText(child, fromEnd);
            if (found) return found;
          }
          return null;
        }
        let caretX = null;
        let textNode = sel.focusNode && sel.focusNode.nodeType === 3 ? sel.focusNode : null;
        let off = textNode ? Math.max(0, Math.min(sel.focusOffset, textNode.length)) : 0;
        if ((!textNode || !textNode.length) && sel.focusNode && sel.focusNode.nodeType === 1) {
          const atEnd = sel.focusOffset > 0;
          const edgeChild = sel.focusNode.childNodes[atEnd ? sel.focusOffset - 1 : sel.focusOffset];
          textNode = findEdgeText(edgeChild, atEnd);
          if (textNode) off = atEnd ? textNode.length : 0;
        }
        if (textNode && textNode.length && el.contains(textNode)) {
          off = Math.max(0, Math.min(off, textNode.length));
          const from = off > 0 ? off - 1 : off;
          const to = off > 0 ? off : Math.min(off + 1, textNode.length);
          const gr = document.createRange();
          gr.setStart(textNode, from);
          gr.setEnd(textNode, to);
          const g = gr.getBoundingClientRect();
          if (g && g.height) caretX = off > 0 ? g.right : g.left;
        }
        if (caretX === null) return;
        const cr = scroller.getBoundingClientRect();
        const M = 16;
        const before = scroller.scrollLeft;
        if (caretX < cr.left + M) {
          scroller.scrollLeft = Math.max(0, scroller.scrollLeft - (cr.left + M - caretX));
        } else if (caretX > cr.right - M) {
          scroller.scrollLeft = Math.min(
            scroller.scrollWidth - scroller.clientWidth,
            scroller.scrollLeft + (caretX - cr.right + M)
          );
        }
        if (scroller.scrollLeft !== before) {
          dioxus.send(JSON.stringify({ op: 'titleCaretSync', from: before, to: scroller.scrollLeft }));
        }
      });
    });
  }
  onGlobal(document, 'selectionchange', () => {
    const el = document.getElementById('editor-title-text');
    if (el && document.activeElement === el) syncTitleCaret();
  });
  if (window.visualViewport) {
    onGlobal(window.visualViewport, 'resize', () => {
      const el = document.getElementById('editor-title-text');
      if (el && document.activeElement === el) syncTitleCaret();
    });
    // 原版 handleViewportChange 还挂 visualViewport scroll 与
    // window resize（iOS 键盘升起/收起时视口滚动同样要把光标
    // 同步回对称留空），一并补齐。
    onGlobal(window.visualViewport, 'scroll', () => {
      const el = document.getElementById('editor-title-text');
      if (el && document.activeElement === el) syncTitleCaret();
    }, { passive: true });
  }
  onGlobal(window, 'resize', () => {
    const el = document.getElementById('editor-title-text');
    if (el && document.activeElement === el) syncTitleCaret();
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
/// capture）/__mnTypedMark（document input capture）并置 null；
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
        if let Ok(f) = js_sys::Reflect::get(wv, &"__mnTypedMark".into()) {
            if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                let _ = d.remove_event_listener_with_callback_and_bool("input", func, true);
            }
        }
        let _ = js_sys::Reflect::set(wv, &"__mnTypedMark".into(), &null);
    }
    diag::log("EDIT", "editor cleanup sync done");
}
