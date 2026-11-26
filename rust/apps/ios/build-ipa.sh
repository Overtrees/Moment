#!/bin/bash
# Moment iOS 探针壳链接 + 打包（阶段 0-④）：App.o +
# moment_ffi.o + libmoment_ffi.a + stub.o → Mach-O 可执行
# → 组 .app（最小 Info.plist）→ check-macho 校验 →
# pack-ipa 出 adhoc ipa（交付用户以全能签重签装机）。
# 链路口径见 ios-dev-linux 技能 link.md / pack-ipa.py。
set -euo pipefail
SDK=$HOME/ios-native/iPhoneOS27.2.sdk
SKILL=$HOME/workspace/custom-skills/ios-dev-linux
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/build
APP=$OUT/Moment.app
FFI_LIB=$HOME/workspace/Mynote/rust/target/aarch64-apple-ios/ios/libmoment_ffi.a
CLANG=/usr/lib/llvm-18/bin/clang

bash "$HERE/build-app.sh"
"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" -c "$HERE/src/stub.c" -o "$OUT/stub.o"
# -fuse-ld 须用名而非绝对路径（clang 18 驱动对绝对路径走
# 通用链接调用、丢 -platform_version）；llvm-18/bin 入
# PATH 后驱动自找 ld64.lld。
export PATH=/usr/lib/llvm-18/bin:$PATH
"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -fuse-ld=lld -Wl,-adhoc_codesign \
  -L$SDK/usr/lib/swift -Wl,-rpath,/usr/lib/swift \
  -framework SwiftUI -framework WebKit -framework UIKit -framework Foundation \
  -o "$OUT/Moment" "$OUT/App.o" "$OUT/moment_ffi.o" "$FFI_LIB" "$OUT/stub.o"
python3 "$SKILL/scripts/check-macho.py" "$OUT/Moment"

rm -rf "$APP"
mkdir -p "$APP"
cp "$OUT/Moment" "$APP/Moment"
chmod 755 "$APP/Moment"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>此刻</string>
  <key>CFBundleExecutable</key><string>Moment</string>
  <key>CFBundleIdentifier</key><string>com.canopies.moment</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Moment</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UILaunchScreen</key><dict/>
</dict>
</plist>
PLIST

if python3 "$SKILL/scripts/pack-ipa.py" "$APP" "$OUT/Moment-phase0.ipa" --min-os 16.0; then
  echo "pack-ipa ok"
else
  echo "pack-ipa 核包未过（见上），改手工 Payload 打包"
  rm -rf "$OUT/Payload" && mkdir -p "$OUT/Payload"
  cp -r "$APP" "$OUT/Payload/"
  (cd "$OUT" && rm -f Moment-phase0.ipa && zip -qr Moment-phase0.ipa Payload)
fi
ls -la "$OUT/Moment-phase0.ipa"
