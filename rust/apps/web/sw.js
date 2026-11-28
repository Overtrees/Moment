// Mynote Rust Web Service Worker（对齐原版 sw.js 的离线能力）
// 版本号由 build.sh 用 wasm md5 戳入，部署即换缓存代。
const VERSION = '__VERSION__';
const CACHE = 'moment-' + VERSION;
const CORE = [
  './',
  './index.html',
  './moment-web.js',
  './moment-web_bg.wasm',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './lang/zh-CN.json',
  './lang/zh-TW.json',
  './lang/en-US.json',
  './lang/ja-JP.json',
  './lang/ko-KR.json',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(
        ks.filter((k) => k.indexOf('moment-') === 0 && k !== CACHE)
          .map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;
  // 指纹资产（build.sh 内容寻址命名 moment-web.<af>.js /
  // moment-web-<af>_bg.wasm）与 bindgen snippets（目录名自带
  // 内容哈希）：名字即内容、永不变旧，走缓存优先——命中零
  // 网络，未命中回源并回填。启动热路径由此脱离网络状态
  // （部署切换由 index.html/sw.js 两个枢轴感知，见下）。
  const fingerprinted = /\/moment-web[^/]*[.-][a-f0-9]{10}[^/]*\.(js|wasm)$/.test(url.pathname)
    || url.pathname.includes('/snippets/');
  if (fingerprinted) {
    e.respondWith(
      caches.match(req, { ignoreSearch: true }).then((hit) => hit || fetch(req).then((r) => {
        if (r.ok) {
          const cp = r.clone();
          caches.open(CACHE).then((c) => c.put(req, cp));
        }
        return r;
      }))
    );
    return;
  }
  // 导航与枢轴文件（html/未指纹 js/wasm）走网络优先，保证
  // 部署即时生效；断网时回缓存。语言包/图标等走 SWR。
  const networkFirst = req.mode === 'navigate'
    || url.pathname.endsWith('.js')
    || url.pathname.endsWith('.wasm')
    || url.pathname.endsWith('.html');
  if (networkFirst) {
    e.respondWith(
      fetch(req).then((r) => {
        if (r.ok) {
          const cp = r.clone();
          caches.open(CACHE).then((c) => c.put(req, cp));
        }
        return r;
      }).catch(() => caches.match(req, { ignoreSearch: true })
        .then((hit) => hit || caches.match('./index.html')))
    );
    return;
  }
  e.respondWith(
    caches.match(req, { ignoreSearch: true }).then((hit) => {
      const net = fetch(req).then((r) => {
        if (r.ok) {
          const cp = r.clone();
          caches.open(CACHE).then((c) => c.put(req, cp));
        }
        return r;
      }).catch(() => hit);
      return hit || net;
    })
  );
});
