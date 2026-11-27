#!/usr/bin/env bash
# 出包门（用户 2026-11-26 立规：每次出包前跑一次全
# 量冒烟，全绿才出包）。顺序：① Rust 全仓测试
# （core 含 MD R 系列回归 + ffi 契约含 checksum 双
# 向核对）→ ② 重建 iOS FFI 静态库 → ③ 构建 ipa →
# ④ verify_ios.sh 八组断言（版本/禁区/FFI/数据契
# 约/产物/校验和/几何前提/资源）。任一步红即停，
# 不产出可交付 ipa。真机侧冒烟由装机后 Diag 的
# SMOKE 冷启行留证（本机无模拟器，不在此列）。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
RUST="$HERE/../../.."
export PATH="$HOME/.cargo/bin:/usr/lib/llvm-18/bin:$PATH"
export TMPDIR="$HOME/.tmp"
mkdir -p "$TMPDIR"

echo "== [smoke 1/4] cargo test --workspace =="
(cd "$RUST" && cargo test --workspace 2>&1 | tail -5)

echo "== [smoke 2/4] 重建 iOS FFI 静态库 =="
export CC_aarch64_apple_ios="clang -target arm64-apple-ios16.0 -isysroot $HOME/.ios-sdk/iPhoneOS27.1.sdk"
export AR_aarch64_apple_ios=/usr/lib/llvm-18/bin/llvm-ar
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$HOME/ios-native/bin/ld64.lld"
(cd "$RUST" && cargo build -p moment-ffi --lib \
  --target aarch64-apple-ios --profile ios 2>&1 | tail -2)

echo "== [smoke 3/4] 构建 ipa =="
bash "$HERE/build-app2.sh" 2>&1 | tee "$HERE/last-build.log" | tail -3

echo "== [smoke 4/4] verify_ios.sh =="
bash "$HERE/verify_ios.sh"

echo "SMOKE ALL GREEN — 可出包"
