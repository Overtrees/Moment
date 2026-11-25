#!/usr/bin/env bash
# SQLite spike 构建（阶段一脚手架）：与主线 build.sh 同链
# （cargo release → wasm-bindgen），多出 clang 依赖——
# sqlite-wasm-rs 的 build.rs 以 clang 编 SQLite amalgamation。
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"
cd "$(dirname "$0")"
cargo build --release --target wasm32-unknown-unknown
wasm-bindgen --target web --out-dir web/pkg --out-name mynote_sqlite_spike \
  target/wasm32-unknown-unknown/release/mynote_sqlite_spike.wasm
echo "pkg ready: web/pkg/mynote_sqlite_spike_bg.wasm $(stat -c%s web/pkg/mynote_sqlite_spike_bg.wasm) B"
