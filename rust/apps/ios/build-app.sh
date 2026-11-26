#!/bin/bash
# Moment iOS 探针壳编译（阶段 0-③）：Swift 业务代码 +
# UniFFI 生成绑定 → arm64 目标文件。工具链/SDK/模块路径
# 均为本机布局（见 ios-dev-linux 技能与 ~/ios-native）。
# 链接与打包在 build-ipa.sh（阶段 0-④）。
set -euo pipefail
TC=$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04
SDK=$HOME/ios-native/iPhoneOS27.2.sdk
RD=$HOME/ios-native/swift-resource
MODS=$HOME/ios-native/mods
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/build
mkdir -p "$OUT"
XCC="-Xcc -I$SDK/usr/include -Xcc -fmodule-map-file=$SDK/usr/include/dispatch.modulemap -Xcc -fmodule-map-file=$HERE/bindings/moment_ffiFFI.modulemap"
COMMON="-target arm64-apple-ios16.0 -sdk $SDK -resource-dir $RD -module-cache-path $HOME/ios-native/swift-cache -module-name Moment -swift-version 5 -parse-as-library -O -I$MODS -I$HERE/bindings $XCC"
cd "$HERE"
$TC/usr/bin/swift-frontend -frontend -c \
  -primary-file bindings/moment_ffi.swift src/App.swift \
  $COMMON -o "$OUT/moment_ffi.o"
$TC/usr/bin/swift-frontend -frontend -c \
  bindings/moment_ffi.swift -primary-file src/App.swift \
  $COMMON -o "$OUT/App.o"
echo "app objects ok: $OUT"
