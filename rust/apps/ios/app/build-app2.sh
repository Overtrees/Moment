#!/bin/bash
# Moment 原生阶段 2 构建：SwiftUI 应用 + moment-ffi →
# Moment.app（bundle id com.canopies.moment）→ ipa。
# 链路同 spike/build-spike.sh（ios-dev-linux 口径）。
set -euo pipefail
TC=$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04
SDK=$HOME/ios-native/iPhoneOS27.2.sdk
RD=$HOME/ios-native/swift-resource
MODS=$HOME/ios-native/mods
SKILL=$HOME/workspace/custom-skills/ios-dev-linux
HERE=$(cd "$(dirname "$0")" && pwd)
IOSDIR=$(dirname "$HERE")
OUT=$HERE/build
mkdir -p "$OUT"
CLANG=/usr/lib/llvm-18/bin/clang

XCC="-Xcc -I$SDK/usr/include -Xcc -fmodule-map-file=$SDK/usr/include/dispatch.modulemap -Xcc -fmodule-map-file=$IOSDIR/bindings/moment_ffiFFI.modulemap"
COMMON="-target arm64-apple-ios16.0 -sdk $SDK -resource-dir $RD -module-cache-path $HOME/ios-native/swift-cache -module-name MomentMain -swift-version 5 -parse-as-library -Onone -I$MODS -I$IOSDIR/bindings $XCC"

$TC/usr/bin/swift-frontend -frontend -c \
  -primary-file "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" $COMMON -o "$OUT/moment_ffi.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  -primary-file "$HERE/MomentApp.swift" \
  $COMMON -o "$OUT/app.o"
echo "objects ok"

"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" -c \
  "$IOSDIR/src/stub.c" -o "$OUT/stub.o"
export PATH=/usr/lib/llvm-18/bin:$PATH
"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -fuse-ld=lld -Wl,-adhoc_codesign \
  -L$SDK/usr/lib/swift -Wl,-rpath,/usr/lib/swift \
  -framework SwiftUI -framework WebKit -framework UIKit -framework Foundation -framework CoreLocation \
  -o "$OUT/Moment" "$OUT/app.o" "$OUT/moment_ffi.o" \
  "$IOSDIR/../../target/aarch64-apple-ios/ios/libmoment_ffi.a" \
  "$OUT/stub.o"
python3 "$SKILL/scripts/check-macho.py" "$OUT/Moment"

APP=$OUT/Moment.app
rm -rf "$APP" && mkdir -p "$APP"
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
  <key>CFBundleShortVersionString</key><string>0.8.8</string>
  <key>CFBundleVersion</key><string>26</string>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>用于显示你所在城市的天气</string>
  <key>UILaunchScreen</key><dict/>
</dict>
</plist>
PLIST

# 天气 key 构建注入（用户裁定）：源文件在仓外
# ~/ios-native/weather-keys.json（不入 git）；存在则打进
# bundle，缺失则天气链按 Web 无 key 口径静默不发请求。
if [ -f "$HOME/ios-native/weather-keys.json" ]; then
  cp "$HOME/ios-native/weather-keys.json" "$APP/weather-keys.json"
  echo "weather keys injected (bundle)"
else
  echo "weather keys NOT found, bundle without keys"
fi

rm -rf "$OUT/Payload" && mkdir -p "$OUT/Payload"
cp -r "$APP" "$OUT/Payload/"
IPA=$OUT/Moment-stage2.ipa
(cd "$OUT" && rm -f "$IPA" && zip -qr "$IPA" Payload)
ls -la "$IPA"
