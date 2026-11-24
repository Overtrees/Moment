//! 天气子系统（审计 WL-W-3 补回，原版 src/services/weather.js
//! 移植）：新建卡天气行的数据层——缓存（localStorage
//! `weather_cache` v6、30 分钟 TTL，与原版同键同形态）→
//! GPS 定位（5s 超时）→ ipapi.co HTTPS 兜底定位 → 和风天气
//! now + 城市反查。城市标签在渲染侧经 to_cn 英转中（原版
//! CN_CITY 表逐值移植），与原版「缓存存原文、渲染转中文」
//! 的分工一致。
//!
//! 数据源现状（2026-11-24 核）：和风 API key 在原版仓库
//! `src/app-config.js` 中为空串（部署时注入、仓库不落凭据），
//! 本移植同样从 `window.__APP_CONFIG__.QWEATHER_API_KEY`
//! （或 MynoteConstants 同名字段）读注入值——未注入时与原版
//! 仓库构建行为逐字一致：定位照走、天气请求不发、天气行
//! 不渲染。Diag 记结果行（命中/失败原因），不只记意图。

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

/// 和风 key（部署注入点，与原版 app-config.js 同口径）：
/// window.__APP_CONFIG__.QWEATHER_API_KEY，次选
/// window.MynoteConstants.QWEATHER_API_KEY；皆无 → 空串。
fn qweather_key() -> String {
    js_sys::eval(
        "(()=>{try{var a=window.__APP_CONFIG__||{};var b=window.MynoteConstants||{};\
         return a.QWEATHER_API_KEY||b.QWEATHER_API_KEY||''}catch(e){return ''}})()",
    )
    .ok()
    .and_then(|v| v.as_string())
    .unwrap_or_default()
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
        // 与原版仓库构建同行为：无注入 key 不发请求。
        diag::log("WEATHER", "no api key injected, skip qweather");
        return None;
    }
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
        city = ip_city;
    }
    let w = WeatherData {
        temp,
        city,
        condition,
    };
    cache_set(&w, lat, lng);
    diag::log(
        "WEATHER",
        &format!("fetched {}° {} {}", w.temp, w.city, w.condition),
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
