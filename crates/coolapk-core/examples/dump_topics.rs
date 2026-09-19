/// 调试:热门话题返回结构。
use coolapk_core::client::CoolapkClient;
use serde_json::Value;

#[tokio::main]
async fn main() {
    let client = CoolapkClient::new();
    let value = client.get_hot_topics().await.expect("hot topics failed");
    println!("top keys: {:?}", value.as_object().map(|o| o.keys().collect::<Vec<_>>()));
    let data = &value["data"];
    match data {
        Value::Array(list) => {
            println!("data: array of {}", list.len());
            if let Some(first) = list.first() {
                println!("first: {}", serde_json::to_string(first).unwrap_or_default().chars().take(400).collect::<String>());
            }
        }
        Value::Object(dict) => {
            println!("data object keys: {:?}", dict.keys().collect::<Vec<_>>());
            for key in ["rows", "items", "list", "data"] {
                if let Some(inner) = dict.get(key) {
                    println!("  data.{key}: {}", serde_json::to_string(inner).unwrap_or_default().chars().take(400).collect::<String>());
                }
            }
        }
        _ => println!("data: {data}"),
    }
}
