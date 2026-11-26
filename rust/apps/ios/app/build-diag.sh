#!/bin/bash
# 定位梯子包：DiagApp.swift + MomentApp.swift（剥 @main）
# 同链路构建，bundle id com.canopies.moment.diag。
set -euo pipefail
TC=$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04
SDK=$HOME/ios-native/iPhoneOS27.2.sdk
RD=$HOME/ios-native/swift-resource
MODS=$HOME/ios-native/mods
SKILL=$HOME/workspace/custom-skills/ios-dev-linux
HERE=$(cd "$(dirname "$0")" && pwd)
IOSDIR=$(dirname "$HERE")
OUT=$HERE/build-diag
mkdir -p "$OUT"
CLANG=/usr/lib/llvm-18/bin/clang

sed '/^@main$/,$d' "$HERE/MomentApp.swift" > "$OUT/AppNoMain.swift"

XCC="-Xcc -I$SDK/usr/include -Xcc -fmodule-map-file=$SDK/usr/include/dispatch.modulemap -Xcc -fmodule-map-file=$IOSDIR/bindings/moment_ffiFFI.modulemap"
COMMON="-target arm64-apple-ios16.0 -sdk $SDK -resource-dir $RD -module-cache-path $HOME/ios-native/swift-cache -module-name MomentDiag -swift-version 5 -parse-as-library -Onone -I$MODS -I$IOSDIR/bindings $XCC"

$TC/usr/bin/swift-frontend -frontend -c \
  -primary-file "$IOSDIR/bindings/moment_ffi.swift" \
  "$OUT/AppNoMain.swift" "$HERE/DiagApp.swift" $COMMON -o "$OUT/moment_ffi.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  -primary-file "$OUT/AppNoMain.swift" "$HERE/DiagApp.swift" \
  $COMMON -o "$OUT/app.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" "$OUT/AppNoMain.swift" \
  -primary-file "$HERE/DiagApp.swift" \
  $COMMON -o "$OUT/diag.o"
echo "objects ok"

"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" -c \
  "$IOSDIR/src/stub.c" -o "$OUT/stub.o"
export PATH=/usr/lib/llvm-18/bin:$PATH
"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -fuse-ld=lld -Wl,-adhoc_codesign \
  -L$SDK/usr/lib/swift -Wl,-rpath,/usr/lib/swift \
  -framework SwiftUI -framework WebKit -framework UIKit -framework Foundation \
  -o "$OUT/MomentDiag" "$OUT/app.o" "$OUT/diag.o" "$OUT/moment_ffi.o" \
  "$IOSDIR/../../target/aarch64-apple-ios/ios/libmoment_ffi.a" \
  "$OUT/stub.o"
python3 "$SKILL/scripts/check-macho.py" "$OUT/MomentDiag"

APP=$OUT/MomentDiag.app
rm -rf "$APP" && mkdir -p "$APP"
cp "$OUT/MomentDiag" "$APP/MomentDiag"
chmod 755 "$APP/MomentDiag"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>此刻·梯子</string>
  <key>CFBundleExecutable</key><string>MomentDiag</string>
  <key>CFBundleIdentifier</key><string>com.canopies.moment.diag</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MomentDiag</string>
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
IPA=$OUT/Moment-diag.ipa
(cd "$OUT" && rm -f "$IPA" && zip -qr "$IPA" Payload)
ls -la "$IPA"
