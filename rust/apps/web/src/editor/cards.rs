//! 链接/音乐卡片：元数据解析回填（hydrate/retry/设链公共
//! 路径）与音乐输入胶囊的解析、删除。

use super::*;

/// 解析一张卡片（原版 hydrate / retry / 设链后的公共路径）：
/// 拉元数据 → 回写 meta + status（有 title=ready，否则 error）；
/// 期间 URL 已被改掉则放弃（防竞态，同原版守卫）。
/// card_caret/focus_req 仅音乐输入解析路径传 Some：该卡落定
/// 后按原版 focusCaretBelowResolvedCard 把光标放到卡片下方
/// 一行的开头；其余路径（hydrate/retry/设链）传 None，不抢光标。
#[allow(clippy::too_many_arguments)]
pub(super) fn spawn_resolve_card(
    mut doc: Signal<Vec<Node>>,
    bid: String,
    url: String,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
    card_caret: Option<Signal<Option<String>>>,
    focus_req: Option<Signal<Option<(String, usize)>>>,
) {
    spawn(async move {
        let meta = fetch_link_meta(&url).await;
        let mut d = doc.read().clone();
        if let Some(loc) = find_loc(&d, &bid) {
            let cur_url = {
                let n = node_at_mut(&mut d, loc);
                n.extra
                    .get("url")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string()
            };
            if cur_url != url {
                // 防竞态放弃时同步清掉本卡的待落点标记，免得
                // 残留标记被后续无关解析误触发
                if let Some(mut cc) = card_caret {
                    if cc.read().as_deref() == Some(bid.as_str()) {
                        cc.set(None);
                    }
                }
                return;
            }
            let ready = meta
                .as_ref()
                .and_then(|m| m.get("title"))
                .and_then(|v| v.as_str())
                .map(|s| !s.is_empty())
                .unwrap_or(false);
            let n = node_at_mut(&mut d, loc);
            if ready {
                n.extra.insert("meta".into(), meta.clone().unwrap());
                n.extra.insert("status".into(), json!("ready"));
            } else {
                n.extra.insert("meta".into(), serde_json::Value::Null);
                n.extra.insert("status".into(), json!("error"));
            }
            doc.set(d.clone());
            persist.call(d, title.read().clone(), data);
            diag::log(
                "CARD",
                &format!("resolve {bid} -> {}", if ready { "ready" } else { "error" }),
            );
            // 音乐输入解析路径的光标落点（原版
            // focusCaretBelowResolvedCard）：卡片下方不是现成
            // 的可编辑文本块就补一个空段落，光标落其开头。
            if let (Some(mut cc), Some(mut fr)) = (card_caret, focus_req) {
                if cc.read().as_deref() == Some(bid.as_str()) {
                    cc.set(None);
                    let mut d2 = doc.read().clone();
                    if let Some(Loc::Top(i)) = find_loc(&d2, &bid) {
                        let next_is_text = d2
                            .get(i + 1)
                            .map(|n| is_text_block(n.block_type().unwrap_or("")))
                            .unwrap_or(false);
                        let target = if next_is_text {
                            d2[i + 1].id.clone().unwrap_or_default()
                        } else {
                            let p = new_block("paragraph");
                            let pid = p.id.clone().unwrap_or_default();
                            d2.insert(i + 1, p);
                            doc.set(d2.clone());
                            persist.call(d2, title.read().clone(), data);
                            pid
                        };
                        if !target.is_empty() {
                            fr.set(Some((target.clone(), 0)));
                            diag::log("CARD", &format!("caret below {bid} -> {target}"));
                        }
                    }
                }
            }
            if ready {
                if let Some(cover) = meta
                    .as_ref()
                    .and_then(|m| m.get("cover"))
                    .and_then(|v| v.as_str())
                {
                    if !cover.is_empty() {
                        diag::log(
                            "CARD",
                            &format!("cover {bid} -> {}", crate::blocks::proxy_img(cover)),
                        );
                    }
                }
            }
        }
    });
}

/// 从任意文本里提第一个 http(s) URL（原版 extractUrlFromText
/// 的 URL_INLINE_REGEX 口径）：定位 scheme 后按 URL 字符集
/// 延伸，再用 Url 解析校验协议；无 scheme 时整段须是裸域名
/// 形态（原版 resolvePendingMusicUrl 的兜底正则）才补 https://。
fn extract_card_url(candidate: &str) -> Option<String> {
    let lower = candidate.to_lowercase();
    let start = lower.find("http://").or_else(|| lower.find("https://"));
    if let Some(pos) = start {
        let mut end = candidate.len();
        for (i, ch) in candidate[pos..].char_indices() {
            let ok = ch.is_ascii_alphanumeric()
                || matches!(ch, '-' | '@' | ':' | '%' | '.' | '_' | '+' | '~' | '#' | '=' | '?' | '&' | '/' | '(' | ')')
                || ('\u{4e00}'..='\u{9fa5}').contains(&ch);
            if !ok {
                end = pos + i;
                break;
            }
        }
        let url = &candidate[pos..end];
        let parsed = web_sys::Url::new(url).ok()?;
        if parsed.protocol() == "http:" || parsed.protocol() == "https:" {
            return Some(url.to_string());
        }
        return None;
    }
    let t = candidate.trim();
    if t.is_empty() || t.chars().any(|c| c.is_whitespace()) {
        return None;
    }
    let host = t.split(['/', '?', '#']).next().unwrap_or(t);
    let mut parts = host.rsplitn(2, '.');
    let tld = parts.next().unwrap_or("");
    let name = parts.next().unwrap_or("");
    if name.is_empty()
        || tld.len() < 2
        || !tld.chars().all(|c| c.is_ascii_alphabetic())
        || !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '.'))
    {
        return None;
    }
    let url = format!("https://{t}");
    let parsed = web_sys::Url::new(&url).ok()?;
    if parsed.protocol() == "https:" {
        Some(url)
    } else {
        None
    }
}

/// 音乐输入胶囊的文本复检（原版 resolvePendingMusicUrl）：
/// 剥掉占位提示文案后能提出 URL 才动作——节点转 loading
/// （胶囊随重渲染被骨架替换、焦点随卸载消失 = 加载期无光
/// 标），登记待落点标记并走公共解析路径；提不出 URL 时
/// 什么都不做（用户还在输入）。返回是否发生了文档变更。
#[allow(clippy::too_many_arguments)]
pub(super) fn op_music_input(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    raw_text: &str,
    card_caret: &mut Signal<Option<String>>,
    focus_req: &mut Signal<Option<(String, usize)>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: &PersistHandle,
) -> bool {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        return false;
    };
    {
        let n = node_at(&d, loc);
        if n.block_type() != Some("musicCard")
            || n.extra.get("status").and_then(|v| v.as_str()) != Some("input")
        {
            return false;
        }
    }
    let hint = crate::i18n::t("media.music_paste_hint");
    let candidate = raw_text.replace(&hint, " ");
    let Some(url) = extract_card_url(candidate.trim()) else {
        return false;
    };
    {
        let n = node_at_mut(&mut d, loc);
        n.children = None;
        n.extra.insert("url".into(), json!(url.clone()));
        n.extra.insert("meta".into(), serde_json::Value::Null);
        n.extra.insert("status".into(), json!("loading"));
    }
    doc.set(d.clone());
    persist.call(d, title.read().clone(), data);
    diag::log("CARD", &format!("music input resolve {bid} <- {url}"));
    diag::log("CARD", &format!("skeleton {bid}"));
    card_caret.set(Some(bid.to_string()));
    spawn_resolve_card(
        *doc,
        bid.to_string(),
        url,
        title,
        data,
        persist.clone(),
        Some(*card_caret),
        Some(*focus_req),
    );
    true
}

/// 音乐输入胶囊段首退格（原版单宿主里胶囊就是普通块，段首
/// 退格删块、光标回上一块末尾）：删节点并把焦点还给相邻
/// 可编辑块。返回是否发生了文档变更。
pub(super) fn op_music_delete(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: &PersistHandle,
) -> bool {
    let mut d = doc.read().clone();
    let Some(Loc::Top(i)) = find_loc(&d, bid) else {
        return false;
    };
    if d[i].block_type() != Some("musicCard")
        || d[i].extra.get("status").and_then(|v| v.as_str()) != Some("input")
    {
        return false;
    }
    d.remove(i);
    // 落点：优先前一个文本块末尾，其次后一个文本块开头
    let mut target: Option<(String, usize)> = None;
    for n in d[..i.min(d.len())].iter().rev() {
        if is_text_block(n.block_type().unwrap_or("")) {
            target = Some((n.id.clone().unwrap_or_default(), plain_len(n)));
            break;
        }
    }
    if target.is_none() {
        for n in d[i.min(d.len())..].iter() {
            if is_text_block(n.block_type().unwrap_or("")) {
                target = Some((n.id.clone().unwrap_or_default(), 0));
                break;
            }
        }
    }
    doc.set(d.clone());
    persist.call(d, title.read().clone(), data);
    diag::log("CARD", &format!("music input delete {bid}"));
    if let Some(t) = target {
        if !t.0.is_empty() {
            focus_req.set(Some(t));
        }
    }
    true
}

