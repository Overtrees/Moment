#!/bin/bash
# 阶段 1 spike 双壳构建：build-spike.sh web|native
# web    = WKWebView 壳（包内 Web dist、moment:// scheme）
# native = SwiftUI 原生壳（moment-ffi 数据 + UITextView）
# 链路口径同 build-ipa.sh（ios-dev-linux 技能）：swift-
# frontend 编目标文件 → clang18 + ld64.lld 链接 → 组 .app
# → check-macho → 手工 Payload 打包（探针壳无 Assets.car，
# pack-ipa 核包必挂该项，故直接手工打包）。
set -euo pipefail
KIND=${1:?usage: build-spike.sh web|native}
TC=$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04
SDK=$HOME/ios-native/iPhoneOS27.2.sdk
RD=$HOME/ios-native/swift-resource
MODS=$HOME/ios-native/mods
SKILL=$HOME/workspace/custom-skills/ios-dev-linux
HERE=$(cd "$(dirname "$0")" && pwd)
IOSDIR=$(dirname "$HERE")
OUT=$HERE/build-$KIND
mkdir -p "$OUT"
CLANG=/usr/lib/llvm-18/bin/clang

if [ "$KIND" = web ]; then
  MODNAME=SpikeWeb; APPNAME=MomentWeb
  BUNDLE_ID=com.canopies.moment.spikeweb
  DISPLAY=此刻·Web壳
  SRC=$HERE/web/WebShell.swift
else
  MODNAME=SpikeNative; APPNAME=MomentNative
  BUNDLE_ID=com.canopies.moment.spikenative
  DISPLAY=此刻·原生壳
  SRC=$HERE/native/NativeShell.swift
fi

XCC="-Xcc -I$SDK/usr/include -Xcc -fmodule-map-file=$SDK/usr/include/dispatch.modulemap"
if [ "$KIND" = native ]; then
  XCC="$XCC -Xcc -fmodule-map-file=$IOSDIR/bindings/moment_ffiFFI.modulemap"
fi
COMMON="-target arm64-apple-ios16.0 -sdk $SDK -resource-dir $RD -module-cache-path $HOME/ios-native/swift-cache -module-name $MODNAME -swift-version 5 -parse-as-library -O -I$MODS -I$IOSDIR/bindings $XCC"

if [ "$KIND" = native ]; then
  $TC/usr/bin/swift-frontend -frontend -c \
    -primary-file "$IOSDIR/bindings/moment_ffi.swift" "$SRC" \
    $COMMON -o "$OUT/moment_ffi.o"
  $TC/usr/bin/swift-frontend -frontend -c \
    "$IOSDIR/bindings/moment_ffi.swift" -primary-file "$SRC" \
    $COMMON -o "$OUT/app.o"
  OBJS="$OUT/app.o $OUT/moment_ffi.o"
else
  $TC/usr/bin/swift-frontend -frontend -c \
    -primary-file "$SRC" $COMMON -o "$OUT/app.o"
  OBJS="$OUT/app.o"
fi
echo "objects ok: $KIND"

"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" -c \
  "$IOSDIR/src/stub.c" -o "$OUT/stub.o"
export PATH=/usr/lib/llvm-18/bin:$PATH
LINK_OBJS="$OBJS $OUT/stub.o"
if [ "$KIND" = native ]; then
  LINK_OBJS="$LINK_OBJS $IOSDIR/../../target/aarch64-apple-ios/ios/libmoment_ffi.a"
fi
"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -fuse-ld=lld -Wl,-adhoc_codesign \
  -L$SDK/usr/lib/swift -Wl,-rpath,/usr/lib/swift \
  -framework SwiftUI -framework WebKit -framework UIKit -framework Foundation \
  -o "$OUT/$APPNAME" $LINK_OBJS
python3 "$SKILL/scripts/check-macho.py" "$OUT/$APPNAME"

APP=$OUT/$APPNAME.app
rm -rf "$APP" && mkdir -p "$APP"
cp "$OUT/$APPNAME" "$APP/$APPNAME"
chmod 755 "$APP/$APPNAME"
if [ "$KIND" = web ]; then
  cp -r "$IOSDIR/../web/dist" "$APP/web"
fi
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY</string>
  <key>CFBundleExecutable</key><string>$APPNAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APPNAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UILaunchScreen</key><dict/>
</dict>
</plist>
PLIST

rm -rf "$OUT/Payload" && mkdir -p "$OUT/Payload"
cp -r "$APP" "$OUT/Payload/"
IPA=$OUT/Moment-spike-$KIND.ipa
(cd "$OUT" && rm -f "$IPA" && zip -qr "$IPA" Payload)
ls -la "$IPA"
