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
sed "s/__VERSION__/$VER/" sw.js > dist/sw.js
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
echo "dist ready: $(du -sh dist | cut -f1) (wasm $(stat -c%s dist/moment-web_bg.wasm) B)"
