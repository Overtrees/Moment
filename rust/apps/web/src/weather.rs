//! 天气子系统（审计 WL-W-3 补回，原版 src/services/weather.js
//! 移植）：新建卡天气行的数据层——缓存（localStorage
//! `weather_cache` v6、30 分钟 TTL，与原版同键同形态）→
//! GPS 定位（5s 超时）→ ipapi.co HTTPS 兜底定位 → 和风天气
//! now + 城市反查。城市标签在渲染侧经 to_cn 英转中（原版
//! CN_CITY 表逐值移植），与原版「缓存存原文、渲染转中文」
//! 的分工一致。
//!
//! 彩云兜底（2026-11-25 恢复）：旧单体 Moments.html 的
//! fetchWeather 在和风链失败后还有一段彩云天气兜底
//! （06585de 引入），原版拆分模块化时佚失、现行原版与
//! 本移植一度同为和风单源。本次按单体原文行为等价恢复：
//! 和风链失败（请求失败 / code 非 200 / now 缺失）才走
//! 彩云 v2.6 JSONP 端点，字段映射与 skycon 表逐值照
//! 单体原文；彩云亦失败才熄火。Diag 成功行记来源
//! provider=qweather / caiyun-fallback，双失败记
//! provider=fail。
//!
//! 数据源现状（2026-11-24 核）：和风 API key 在原版仓库
//! `src/app-config.js` 中为空串（部署时注入、仓库不落凭据），
//! 本移植同样从 `window.__APP_CONFIG__.QWEATHER_API_KEY`
//! （或 MynoteConstants 同名字段）读注入值——未注入时与原版
//! 仓库构建行为逐字一致：定位照走、天气请求不发、天气行
//! 不渲染。彩云 key 在单体中原为硬编码，本恢复按和风同规
//! 改走 `window.__APP_CONFIG__.CAIYUN_API_KEY` 部署注入、
//! 仓库不落值。Diag 记结果行（命中/失败原因），不只记意图。

use dioxus::prelude::*;

use crate::diag;

#[derive(Clone, Debug, PartialEq)]
pub struct WeatherData {
    pub temp: i32,
    pub city: String,
    pub condition: String,
}

const CACHE_KEY: &str = "weather_cache";
const CACHE_VERSION: i64 = 6;
const CACHE_TTL_MS: f64 = 1_800_000.0;

fn storage() -> Option<web_sys::Storage> {
    web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
}

/// 缓存读（原版 WeatherCache.get：版本不符或超 30 分钟即弃）。
pub fn cached() -> Option<WeatherData> {
    let raw = storage()?.get_item(CACHE_KEY).ok()??;
    let d: serde_json::Value = serde_json::from_str(&raw).ok()?;
    if d.get("v").and_then(|v| v.as_i64()) != Some(CACHE_VERSION) {
        return None;
    }
    let ts = d.get("ts").and_then(|v| v.as_f64())?;
    if js_sys::Date::now() - ts > CACHE_TTL_MS {
        return None;
    }
    Some(WeatherData {
        temp: d.get("temp").and_then(|v| v.as_i64())? as i32,
        city: d
            .get("city")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        condition: d
            .get("condition")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
    })
}

fn cache_set(w: &WeatherData, lat: f64, lng: f64) {
    if let Some(s) = storage() {
        let v = serde_json::json!({
            "temp": w.temp, "city": w.city, "condition": w.condition,
            "lat": lat, "lng": lng, "ts": js_sys::Date::now(), "v": CACHE_VERSION,
        });
        let _ = s.set_item(CACHE_KEY, &v.to_string());
    }
}

/// 部署注入 key（与原版 app-config.js 同口径）：
/// window.__APP_CONFIG__.<field>，次选
/// window.MynoteConstants.<field>；皆无 → 空串。
fn injected_key(field: &str) -> String {
    let js = format!(
        "(()=>{{try{{var a=window.__APP_CONFIG__||{{}};var b=window.MynoteConstants||{{}};\
         return a.{field}||b.{field}||''}}catch(e){{return ''}}}})()"
    );
    js_sys::eval(&js)
        .ok()
        .and_then(|v| v.as_string())
        .unwrap_or_default()
}

/// 和风 key（部署注入点）。
fn qweather_key() -> String {
    injected_key("QWEATHER_API_KEY")
}

/// 彩云 key（部署注入点，与和风同规；单体原文为硬编码，
/// 恢复时改走注入、仓库不落值）。
fn caiyun_key() -> String {
    injected_key("CAIYUN_API_KEY")
}

/// eval + dioxus.send 回送一发 JSON（本仓既有桥模式）：
/// JS 侧负责带超时的异步动作，结果以 JSON 值回 Rust。
async fn eval_json(js: &str) -> Option<serde_json::Value> {
    let mut eval = document::eval(js);
    eval.recv::<serde_json::Value>().await.ok()
}

/// GPS 定位（原版口径：getCurrentPosition + 5s 竞速超时，
/// enableHighAccuracy=false）；拒绝/超时/无 API → None。
async fn geolocate() -> Option<(f64, f64)> {
    let v = eval_json(
        "(function(){ \
           if (!navigator.geolocation) { dioxus.send(null); return; } \
           var done = false; \
           var send = function(x){ if (!done) { done = true; dioxus.send(x); } }; \
           var t = setTimeout(function(){ send(null); }, 5000); \
           navigator.geolocation.getCurrentPosition( \
             function(p){ clearTimeout(t); send([p.coords.latitude, p.coords.longitude]); }, \
             function(){ clearTimeout(t); send(null); }, \
             { timeout: 5000, enableHighAccuracy: false }); \
         })()",
    )
    .await?;
    let arr = v.as_array()?;
    let lat = arr.first()?.as_f64()?;
    let lng = arr.get(1)?.as_f64()?;
    Some((lat, lng))
}

/// 带 4s 超时的 JSON GET（原版 AbortSignal.timeout(4000)）。
async fn fetch_json(url: &str) -> Option<serde_json::Value> {
    let js = format!(
        "fetch({url:?}, {{signal: AbortSignal.timeout(4000)}}) \
         .then(function(r){{ return r.ok ? r.json() : null; }}) \
         .then(function(d){{ dioxus.send(d); }}) \
         .catch(function(){{ dioxus.send(null); }})"
    );
    eval_json(&js).await.filter(|v| !v.is_null())
}

/// 带 4s 超时的文本 GET（彩云 JSONP 端点用：原版 fetch
/// 后取 text 再剥回调包裹，AbortSignal.timeout(4000)
/// 同口径）。
async fn fetch_text(url: &str) -> Option<String> {
    let js = format!(
        "fetch({url:?}, {{signal: AbortSignal.timeout(4000)}}) \
         .then(function(r){{ return r.ok ? r.text() : null; }}) \
         .then(function(d){{ dioxus.send(d); }}) \
         .catch(function(){{ dioxus.send(null); }})"
    );
    eval_json(&js)
        .await
        .and_then(|v| v.as_str().map(|s| s.to_string()))
}

/// 并发守卫：列表反复进出不重复发整条链（原版以
/// weatherRefreshRef 计时器去重，此处以在飞标记等价）。
static IN_FLIGHT: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// 拉取天气（原版 fetchWeather 全链）：缓存新鲜直接回；
/// 定位（GPS → IP 兜底）→ 和风 now → 城市反查（失败回落
/// IP 城市原文）。任一环失败回 None 且 Diag 记原因。
pub async fn fetch_weather() -> Option<WeatherData> {
    if let Some(w) = cached() {
        diag::log(
            "WEATHER",
            &format!("cache hit {}° {} {}", w.temp, w.city, w.condition),
        );
        return Some(w);
    }
    if IN_FLIGHT.swap(true, std::sync::atomic::Ordering::SeqCst) {
        return None;
    }
    let out = fetch_weather_inner().await;
    IN_FLIGHT.store(false, std::sync::atomic::Ordering::SeqCst);
    out
}

async fn fetch_weather_inner() -> Option<WeatherData> {
    let mut ip_city = String::new();
    let coords = match geolocate().await {
        Some(c) => Some(c),
        None => {
            // HTTPS IP 兜底（原版：ip-api.com 仅 HTTP 已弃，
            // 用 ipapi.co）。
            let ip = fetch_json("https://ipapi.co/json/").await;
            match ip {
                Some(d) => {
                    if let Some(c) = d.get("city").and_then(|v| v.as_str()) {
                        let region = d.get("region").and_then(|v| v.as_str()).unwrap_or("");
                        ip_city = if region.is_empty() {
                            c.to_string()
                        } else {
                            format!("{c} {region}")
                        };
                    }
                    let lat = d.get("latitude").and_then(|v| v.as_f64());
                    let lng = d.get("longitude").and_then(|v| v.as_f64());
                    match (lat, lng) {
                        (Some(a), Some(o)) => Some((a, o)),
                        _ => None,
                    }
                }
                None => None,
            }
        }
    };
    let Some((lat, lng)) = coords else {
        diag::log("WEATHER", "locate failed (gps + ip)");
        return None;
    };
    let key = qweather_key();
    if key.is_empty() {
        // 与原版仓库构建同行为：无注入 key 不发请求
        // （原版此门在彩云兜底之前——无和风 key 时彩云
        // 亦不走，单体原文同序）。
        diag::log_warn("WEATHER", "no api key injected, skip qweather");
        return None;
    }
    if let Some(w) = fetch_qweather(lat, lng, &key, &ip_city).await {
        return Some(w);
    }
    // 和风链失败 → 彩云兜底（单体原文失败点同位）。
    let out = fetch_caiyun(lat, lng, &ip_city).await;
    if out.is_none() {
        diag::log("WEATHER", "provider=fail (qweather + caiyun)");
    }
    out
}

/// 和风主链：now → code 校验 → 城市反查（失败回落 IP
/// 城市原文）→ 写缓存。任一环失败回 None（Diag 记
/// 原因），由调用方接彩云兜底。
async fn fetch_qweather(
    lat: f64,
    lng: f64,
    key: &str,
    ip_city: &str,
) -> Option<WeatherData> {
    let now_url = format!(
        "https://jq3dna235e.re.qweatherapi.com/v7/weather/now?location={lng},{lat}&key={key}"
    );
    let Some(qw) = fetch_json(&now_url).await else {
        diag::log("WEATHER", "qweather now failed");
        return None;
    };
    if qw.get("code").and_then(|v| v.as_str()) != Some("200") {
        diag::log("WEATHER", "qweather now failed");
        return None;
    }
    let now = qw.get("now")?;
    let condition = now
        .get("text")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let temp = now
        .get("temp")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse::<i32>().ok())
        .or_else(|| now.get("temp").and_then(|v| v.as_i64()).map(|n| n as i32))?;
    let mut city = String::new();
    let geo_url = format!(
        "https://jq3dna235e.re.qweatherapi.com/geo/v2/city/lookup?location={lng},{lat}&key={key}"
    );
    if let Some(geo) = fetch_json(&geo_url).await {
        if geo.get("code").and_then(|v| v.as_str()) == Some("200") {
            if let Some(loc) = geo
                .get("location")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
            {
                let name = loc.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let adm2 = loc.get("adm2").and_then(|v| v.as_str()).unwrap_or("");
                city = if adm2.is_empty() {
                    name.to_string()
                } else {
                    format!("{adm2}{name}")
                };
            }
        }
    }
    if city.is_empty() {
        city = ip_city.to_string();
    }
    let w = WeatherData {
        temp,
        city,
        condition,
    };
    cache_set(&w, lat, lng);
    diag::log(
        "WEATHER",
        &format!(
            "fetched provider=qweather {}° {} {}",
            w.temp, w.city, w.condition
        ),
    );
    Some(w)
}

/// 彩云 skycon → 状况文本（单体原文 condMap 逐值移植；
/// 未命中回 skycon 原文，原版 `condMap[x] || x` 同口径）。
fn caiyun_condition(skycon: &str) -> String {
    let hit = match skycon {
        "CLEAR_DAY" | "CLEAR_NIGHT" => "晴",
        "PARTLY_CLOUDY_DAY" | "PARTLY_CLOUDY_NIGHT" => "多云",
        "CLOUDY" => "阴",
        "LIGHT_RAIN" => "小雨",
        "MODERATE_RAIN" => "中雨",
        "HEAVY_RAIN" => "大雨",
        "STORM_RAIN" => "暴雨",
        "THUNDER_SHOWER" => "雷阵雨",
        "SLEET" => "雨夹雪",
        "LIGHT_SNOW" => "小雪",
        "MODERATE_SNOW" => "中雪",
        "HEAVY_SNOW" => "大雪",
        "STORM_SNOW" => "暴雪",
        "HAIL" => "冰雹",
        "LIGHT_HAZE" => "薄雾",
        "MODERATE_HAZE" => "中度雾",
        "HEAVY_HAZE" => "浓雾",
        "FOG" => "雾",
        "DUST" => "沙尘",
        "WIND" => "大风",
        _ => return skycon.to_string(),
    };
    hit.to_string()
}

/// 彩云 JSONP 载荷解析（单体原文：剥 `MYCALLBACK(…)`
/// 包裹 → status=="ok" → result.realtime.temperature
/// 以 Math.round 语义取整、skycon 映射状况）。任一环
/// 不合 → None。
fn parse_caiyun(raw: &str) -> Option<(i32, String)> {
    let body = raw.trim();
    let body = body.strip_prefix("MYCALLBACK(").unwrap_or(body);
    let body = body.strip_suffix(')').unwrap_or(body);
    let j: serde_json::Value = serde_json::from_str(body).ok()?;
    if j.get("status").and_then(|v| v.as_str()) != Some("ok") {
        return None;
    }
    let rt = j.get("result")?.get("realtime")?;
    let t = rt.get("temperature").and_then(|v| v.as_f64())?;
    // JS Math.round = floor(x + 0.5)（与 f64::round 的
    // 半值远离零不同，负温 .5 时以此为准）。
    let temp = (t + 0.5).floor() as i32;
    let skycon = rt
        .get("skycon")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    Some((temp, caiyun_condition(skycon)))
}

/// 彩云兜底（单体 Moments.html fetchWeather 尾段行为
/// 等价恢复）：同坐标调 v2.6 JSONP 端点（lng,lat 序、
/// 4s 超时），城市名只取 IP 定位侧（单体原文无反查），
/// 成功同样写缓存；失败回 None（Diag 记原因）。
async fn fetch_caiyun(lat: f64, lng: f64, ip_city: &str) -> Option<WeatherData> {
    let key = caiyun_key();
    if key.is_empty() {
        diag::log("WEATHER", "caiyun fallback skipped (no key)");
        return None;
    }
    let url = format!(
        "https://api.caiyunapp.com/v2.6/{key}/{lng},{lat}/weather.jsonp?callback=MYCALLBACK"
    );
    let parsed = match fetch_text(&url).await {
        Some(raw) => parse_caiyun(&raw),
        None => None,
    };
    let Some((temp, condition)) = parsed else {
        diag::log("WEATHER", "caiyun fallback failed");
        return None;
    };
    let w = WeatherData {
        temp,
        city: ip_city.to_string(),
        condition,
    };
    cache_set(&w, lat, lng);
    diag::log(
        "WEATHER",
        &format!(
            "fetched provider=caiyun-fallback {}° {} {}",
            w.temp, w.city, w.condition
        ),
    );
    Some(w)
}

/// 城市英转中（原版 CN_CITY 表逐值移植，demo-memos.js）：
/// 命中回中文、未命中回原文（原版 toCn 同口径）。
pub fn to_cn(name: &str) -> String {
    let hit = match name {
        "Beijing" => "北京",
        "Shanghai" => "上海",
        "Guangzhou" => "广州",
        "Shenzhen" => "深圳",
        "Hangzhou" => "杭州",
        "Nanjing" => "南京",
        "Chengdu" => "成都",
        "Wuhan" => "武汉",
        "Tianjin" => "天津",
        "Chongqing" => "重庆",
        "Shenyang" => "沈阳",
        "Changchun" => "长春",
        "Harbin" => "哈尔滨",
        "Dalian" => "大连",
        "Qingdao" => "青岛",
        "Jinan" => "济南",
        "Zhengzhou" => "郑州",
        "Changsha" => "长沙",
        "Nanchang" => "南昌",
        "Hefei" => "合肥",
        "Fuzhou" => "福州",
        "Xiamen" => "厦门",
        "Kunming" => "昆明",
        "Guiyang" => "贵阳",
        "Lanzhou" => "兰州",
        "Xi'an" => "西安",
        "Xining" => "西宁",
        "Yinchuan" => "银川",
        "Nanning" => "南宁",
        "Haikou" => "海口",
        "Zhuhai" => "珠海",
        "Foshan" => "佛山",
        "Dongguan" => "东莞",
        "Suzhou" => "苏州",
        "Wuxi" => "无锡",
        "Ningbo" => "宁波",
        "Wenzhou" => "温州",
        "Changzhou" => "常州",
        "Zhongshan" => "中山",
        "Huizhou" => "惠州",
        "Shantou" => "汕头",
        "Zhanjiang" => "湛江",
        "Taizhou" => "台州",
        "Jiaxing" => "嘉兴",
        "Shaoxing" => "绍兴",
        "Yangzhou" => "扬州",
        "Zhenjiang" => "镇江",
        "Nantong" => "南通",
        "Xuzhou" => "徐州",
        "Luoyang" => "洛阳",
        "Guilin" => "桂林",
        "Lhasa" => "拉萨",
        "Urumqi" => "乌鲁木齐",
        "Hohhot" => "呼和浩特",
        "Macau" => "澳门",
        "Hong Kong" => "香港",
        "Taipei" => "台北",
        "Kaohsiung" => "高雄",
        "Taichung" => "台中",
        "Tainan" => "台南",
        _ => return name.to_string(),
    };
    hit.to_string()
}

/// 延时（列表挂载后 1500ms 再拉天气的原版节拍，与 Toast
/// 同一 eval 计时模式）。
pub async fn sleep_ms(ms: u32) {
    let mut eval = document::eval(&format!("setTimeout(() => dioxus.send(null), {ms});"));
    let _ = eval.recv::<serde_json::Value>().await;
}

#[cfg(test)]
mod tests {
    use super::{caiyun_condition, parse_caiyun};

    fn payload(temp: f64, skycon: &str) -> String {
        format!(
            "MYCALLBACK({{\"status\":\"ok\",\"api_version\":\"v2.6\",\"result\":{{\"realtime\":{{\"temperature\":{temp},\"skycon\":\"{skycon}\"}}}}}})"
        )
    }

    #[test]
    fn caiyun_jsonp_ok_rounds_temp_and_maps_skycon() {
        // 原版 Math.round(12.6) = 13、CLEAR_DAY → 晴。
        assert_eq!(parse_caiyun(&payload(12.6, "CLEAR_DAY")), Some((13, "晴".to_string())));
        assert_eq!(
            parse_caiyun(&payload(0.4, "STORM_RAIN")),
            Some((0, "暴雨".to_string()))
        );
    }

    #[test]
    fn caiyun_negative_half_uses_js_math_round() {
        // JS Math.round(-12.5) = -12（floor(x+0.5)），
        // 不是 f64::round 的 -13。
        assert_eq!(
            parse_caiyun(&payload(-12.5, "LIGHT_SNOW")),
            Some((-12, "小雪".to_string()))
        );
    }

    #[test]
    fn caiyun_skycon_table_samples_and_unknown_passthrough() {
        assert_eq!(caiyun_condition("PARTLY_CLOUDY_NIGHT"), "多云");
        assert_eq!(caiyun_condition("CLOUDY"), "阴");
        assert_eq!(caiyun_condition("THUNDER_SHOWER"), "雷阵雨");
        assert_eq!(caiyun_condition("SLEET"), "雨夹雪");
        assert_eq!(caiyun_condition("LIGHT_HAZE"), "薄雾");
        assert_eq!(caiyun_condition("WIND"), "大风");
        // 未命中回原文（原版 condMap[x] || x）。
        assert_eq!(caiyun_condition("SOMETHING_NEW"), "SOMETHING_NEW");
        assert_eq!(caiyun_condition(""), "");
    }

    #[test]
    fn caiyun_rejects_bad_payloads() {
        // status 非 ok。
        assert_eq!(
            parse_caiyun("MYCALLBACK({\"status\":\"failed\",\"result\":{}})"),
            None
        );
        // 缺 realtime。
        assert_eq!(parse_caiyun("MYCALLBACK({\"status\":\"ok\",\"result\":{}})"), None);
        // 非 JSON / 空串。
        assert_eq!(parse_caiyun("not json"), None);
        assert_eq!(parse_caiyun(""), None);
    }

    #[test]
    fn caiyun_bare_json_without_wrapper_also_parses() {
        // 包裹不存在时 strip 为 no-op（原版 replace 同行为）。
        let raw = "{\"status\":\"ok\",\"result\":{\"realtime\":{\"temperature\":20,\"skycon\":\"FOG\"}}}";
        assert_eq!(parse_caiyun(raw), Some((20, "雾".to_string())));
    }
}
