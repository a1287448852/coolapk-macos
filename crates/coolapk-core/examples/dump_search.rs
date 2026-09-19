/// 调试:打印搜索接口返回结构。
use coolapk_core::client::CoolapkClient;
use serde_json::Value;

#[tokio::main]
async fn main() {
    let client = CoolapkClient::new();
    let result = client.search_all("iphone", 1).await.expect("search failed");
    println!("top keys: {:?}", result.as_object().map(|o| o.keys().collect::<Vec<_>>()));
    let data = &result["data"];
    match data {
        Value::Array(list) => {
            println!("data: array of {}", list.len());
            if let Some(first) = list.first() {
                println!("first: {}", serde_json::to_string(first).unwrap_or_default().chars().take(400).collect::<String>());
            }
        }
        Value::Object(dict) => {
            println!("data object keys: {:?}", dict.keys().collect::<Vec<_>>());
            for key in ["items", "rows", "list", "data", "feed", "apk"] {
                if let Some(inner) = dict.get(key) {
                    println!("  data.{key}: {}", serde_json::to_string(inner).unwrap_or_default().chars().take(300).collect::<String>());
                }
            }
        }
        _ => println!("data: {data}"),
    }
}
