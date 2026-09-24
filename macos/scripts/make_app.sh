#!/bin/zsh
# 组装 CoolapkMac.app(release 构建 + 最小 bundle + ad-hoc 签名)
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release

APP="$DIR/build/CoolapkMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CoolapkMac "$APP/Contents/MacOS/CoolapkMac"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CoolapkMac</string>
    <key>CFBundleIdentifier</key><string>com.coolapkmac.desktop</string>
    <key>CFBundleName</key><string>CoolapkMac</string>
    <key>CFBundleDisplayName</key><string>CoolapkMac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License — 非官方酷安客户端,与酷安官方无关</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP" 2>/dev/null
echo "✅ $APP"
