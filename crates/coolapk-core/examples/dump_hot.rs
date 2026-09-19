/// 调试:打印热门流第一个实体的完整 JSON,用于核对 Swift 侧字段映射。
/// 运行:cargo run --example dump_hot
use coolapk_core::client::CoolapkClient;

#[tokio::main]
async fn main() {
    let client = CoolapkClient::new();
    let value = client.get_hot_feeds(1).await.expect("get_hot_feeds failed");
    let list = value["data"].as_array().expect("data not array");
    println!("count = {}", list.len());
    if let Some(first) = list.first() {
        println!("{}", serde_json::to_string_pretty(first).unwrap());
    }
}
