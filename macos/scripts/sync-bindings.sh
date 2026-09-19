#!/bin/zsh
# 同步 Rust 核心 → Swift 侧:构建 release 静态库,生成 uniFFI 绑定,拷贝到 macos/ 包内。
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE="$ROOT/crates/coolapk-core"
MAC="$ROOT/macos"

cd "$CORE"
cargo build --release
cargo run --quiet --bin uniffi-bindgen -- generate \
  --library target/release/libcoolapk_core.dylib \
  --crate coolapk_core --language swift --out-dir bindings

mkdir -p "$MAC/Vendor/lib" "$MAC/Sources/CoolapkCoreFFI/include" "$MAC/Sources/CoolapkCoreSwift"
cp target/release/libcoolapk_core.a "$MAC/Vendor/lib/"
cp bindings/coolapk_coreFFI.h "$MAC/Sources/CoolapkCoreFFI/include/"
cp bindings/coolapk_core.swift "$MAC/Sources/CoolapkCoreSwift/"

cat > "$MAC/Sources/CoolapkCoreFFI/include/module.modulemap" <<'MM'
module coolapk_coreFFI {
    header "coolapk_coreFFI.h"
    export *
}
MM

echo "✅ bindings synced to macos/"
