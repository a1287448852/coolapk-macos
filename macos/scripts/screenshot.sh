#!/bin/zsh
# 截取 CoolapkMac 窗口截图:scripts/screenshot.sh 输出路径
set -e
OUT="${1:-/tmp/coolapkmac.png}"

WID=$(swift - <<'SWIFT'
import CoreGraphics
import Foundation
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    if owner == "CoolapkMac" {
        if let num = w[kCGWindowNumber as String] as? Int {
            print(num)
            break
        }
    }
}
SWIFT
)

if [ -z "$WID" ]; then
  echo "未找到 CoolapkMac 窗口" >&2
  exit 1
fi
screencapture -x -o -l "$WID" "$OUT"
echo "✅ $OUT (window $WID)"
