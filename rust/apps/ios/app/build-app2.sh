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
  <key>CFBundleShortVersionString</key><string>0.9.37</string>
  <key>CFBundleVersion</key><string>64</string>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UISupportedInterfaceOrientations~ipad</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>NSLocationWhenInUseUsageDescription</key><string>用于显示你所在城市的天气</string>
  <key>UILaunchScreen</key><dict/>
  <key>CFBundleIcons</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconFiles</key><array><string>AppIcon60x60</string><string>AppIcon1024</string></array><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
  <key>CFBundleIcons~ipad</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconFiles</key><array><string>AppIcon60x60</string><string>AppIcon76x76</string><string>AppIcon83.5x83.5</string><string>AppIcon1024</string></array><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
</dict>
</plist>
PLIST

# 应用图标（用户素材，2026-11-26 入仓）：源图
# assets/AppIcon-light-1024.png（浅色定稿、alpha 全
# 不透明已核）由 PIL 切出平铺尺寸组写入 .app；
# 深色定稿 assets/AppIcon-dark-1024.png 留档——平铺
# 图标路径无 appearance 变体机制，深色外观待
# Assets.car 路线再接入。缺源时不中断构建，但
# verify [8] 资源断言会红、出包门拦下。
ICON_SRC="$HERE/assets/AppIcon-light-1024.png"
if [ -f "$ICON_SRC" ]; then
  python3 - "$ICON_SRC" "$APP" <<'PYEOF'
import sys
from PIL import Image
src, app = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
sizes = {
    "AppIcon60x60@2x.png": 120, "AppIcon60x60@3x.png": 180,
    "AppIcon76x76@2x.png": 152, "AppIcon83.5x83.5@2x.png": 167,
    "AppIcon1024.png": 1024,
}
for name, px in sizes.items():
    im.resize((px, px), Image.LANCZOS).save(f"{app}/{name}")
print("app icons generated:", ", ".join(sizes))
PYEOF
else
  echo "app icon source NOT found, bundle without icons"
fi

# 开屏矢量资源（用户素材包 native-splash）：原生开屏
# 视图只读这两份 vector.json（Canvas 矢量绘制，PNG
# 素材同目录留档、位图路径未启用）。
for th in light dark; do
  SJ="$HERE/assets/native-splash/MynoteSplash-$th-vector.json"
  if [ -f "$SJ" ]; then
    cp "$SJ" "$APP/"
    echo "splash vector injected ($th)"
  else
    echo "splash vector NOT found ($th)"
  fi
done

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
