// 核心实现已抽到 crates/coolapk-core,这里 re-export 保持既有路径
// (`crate::coolapk::auth` / `crate::coolapk::client`)不变,便于跟随上游合并。
pub use coolapk_core::auth;
pub use coolapk_core::client;
pub mod commands;
