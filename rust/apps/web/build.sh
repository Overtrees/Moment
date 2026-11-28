#!/usr/bin/env bash
# Rust Web 构建：cargo release → wasm-bindgen → dist（壳 +
# 语言包）。部署：deploy_api.py dist canopies-moment
# MOMENT_SQLITE=1：附加 sqlite-backend feature 与存储
# Worker 构建段（阶段二演练构建；默认构建不带、行为不变）。
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"
WEB_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WEB_DIR/../.."
if [ "${MOMENT_SQLITE:-0}" = "1" ]; then
  cargo build -p moment-web --target wasm32-unknown-unknown --release --features sqlite-backend
else
  cargo build -p moment-web --target wasm32-unknown-unknown --release
fi
cd "$WEB_DIR"
rm -rf dist
wasm-bindgen --target web --out-dir dist --out-name moment-web ../../target/wasm32-unknown-unknown/release/moment-web.wasm
cp index.html dist/index.html
cp manifest.json dist/manifest.json
cp icon-192.png icon-512.png dist/
cp -r lang dist/lang
VER=$(md5sum dist/moment-web_bg.wasm | cut -c1-10)
# 资产指纹 AF：胶水 JS 与 wasm 内容对的 md5 前 10 位。两件
# 产物改内容寻址名（moment-web.<AF>.js / moment-web-<AF>
# _bg.wasm——后缀保留 _bg.wasm，全仓既有 *_bg.wasm glob
# 消费面〔verify §4/§8、归档/回滚/线上核验工具〕零改动），
# index.html 与 sw.js CORE 在 dist 内改指新名；配合
# _headers 的 immutable 长缓存与 sw 的缓存优先分支，热启动
# 不再为 4MB wasm 付网络往返/重下（启动慢根治，见
# docs/reports/fix_web_boot_latency.md）。AF 与 VER 分开：
# VER 是 sw 缓存代戳（wasm md5 口径，verify §4 锁），AF 是
# 「JS+wasm 对」的指纹——只改胶水不改 wasm 时也必须换名。
# 推导定义（verify §22 同口径）：AF 在改名之前对原始内容
# 对计算，胶水内嵌的 wasm 引用随后才被改写为指纹名——自
# 引用内容无法一步自洽，复算时先把指纹名还原裸名再取
# md5，即得同一 AF。
AF=$(cat dist/moment-web_bg.wasm dist/moment-web.js | md5sum | cut -c1-10)
mv dist/moment-web.js "dist/moment-web.$AF.js"
mv dist/moment-web_bg.wasm "dist/moment-web-${AF}_bg.wasm"
[ -f dist/moment-web.d.ts ] && mv dist/moment-web.d.ts "dist/moment-web.$AF.d.ts"
[ -f dist/moment-web_bg.wasm.d.ts ] && mv dist/moment-web_bg.wasm.d.ts "dist/moment-web-${AF}_bg.wasm.d.ts"
sed -i "s/moment-web_bg\.wasm/moment-web-${AF}_bg.wasm/g" "dist/moment-web.$AF.js"
sed -i "s|from './moment-web.js'|from './moment-web.$AF.js'|" dist/index.html
sed -e "s/__VERSION__/$VER/" \
    -e "s|\\./moment-web\\.js|./moment-web.$AF.js|" \
    -e "s|\\./moment-web_bg\\.wasm|./moment-web-${AF}_bg.wasm|" \
    sw.js > dist/sw.js
# 指纹资产 immutable 长缓存（内容寻址、永不变旧）；枢轴
# index.html/sw.js 不在此列，保持平台默认 must-revalidate。
cat > dist/_headers <<EOF
/moment-web.$AF.js
  Cache-Control: public, max-age=31536000, immutable
/moment-web-${AF}_bg.wasm
  Cache-Control: public, max-age=31536000, immutable
/snippets/*
  Cache-Control: public, max-age=31536000, immutable
EOF
if [ "${MOMENT_SQLITE:-0}" = "1" ]; then
  # 存储 Worker（Dedicated Worker + SAHPool + Store 本体，
  # 独立 workspace 的 moment-storage-worker）→
  # dist/storage-worker/；资产进 sw CORE 与主戳同代换版。
  command -v clang >/dev/null || { echo "MOMENT_SQLITE=1 需要 clang（sqlite-wasm-rs 编 C 侧）" >&2; exit 1; }
  (cd ../storage-worker && cargo build --release --target wasm32-unknown-unknown)
  mkdir -p dist/storage-worker/pkg
  wasm-bindgen --target web --out-dir dist/storage-worker/pkg --out-name moment_storage_worker ../storage-worker/target/wasm32-unknown-unknown/release/moment_storage_worker.wasm
  cp ../storage-worker/web/worker.js dist/storage-worker/worker.js
  cp ../storage-worker/web/index.html dist/storage-worker/index.html
  sed -i "s|'./lang/ko-KR.json',|'./lang/ko-KR.json',\n  './storage-worker/worker.js',\n  './storage-worker/pkg/moment_storage_worker.js',\n  './storage-worker/pkg/moment_storage_worker_bg.wasm',|" dist/sw.js
fi
echo "dist ready: $(du -sh dist | cut -f1) (wasm $(stat -c%s "dist/moment-web-${AF}_bg.wasm") B)"
