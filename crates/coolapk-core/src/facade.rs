//! uniFFI 导出层:把 CoolapkAuth / CoolapkClient 包装成 Swift 可用的对象。
//!
//! 原始类型保持不动(便于跟随上游合并),跨界一律 JSON 字符串,
//! Swift 侧统一解码为 Codable 模型。

use crate::auth::CoolapkAuth;
use crate::client::CoolapkClient;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

/// 跨界错误:统一单变体,`message` 直接给 Swift 层展示/记录。
#[derive(Debug, uniffi::Error)]
pub enum CoolapkError {
    Failed { message: String },
}

impl std::fmt::Display for CoolapkError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CoolapkError::Failed { message } => write!(f, "{message}"),
        }
    }
}

impl CoolapkError {
    fn from_string(message: String) -> Self {
        CoolapkError::Failed { message }
    }
}

type UniResult<T> = Result<T, CoolapkError>;

fn to_json_string(value: serde_json::Value) -> UniResult<String> {
    serde_json::to_string(&value)
        .map_err(|e| CoolapkError::Failed { message: format!("failed to encode JSON: {e}") })
}

/// Token V3 离线签名器(Swift 侧用于独立签名场景,一般走 CoolapkApi 即可)。
#[derive(uniffi::Object)]
pub struct UniCoolapkAuth {
    inner: RwLock<CoolapkAuth>,
}

#[uniffi::export]
impl UniCoolapkAuth {
    #[uniffi::constructor]
    pub fn new(device_code: String) -> Arc<Self> {
        Arc::new(Self {
            inner: RwLock::new(CoolapkAuth::new(device_code)),
        })
    }

    /// 切换设备码(登录/切换账号/游客态),后续签名使用新设备码。
    pub fn set_device_code(&self, device_code: String) {
        if let Ok(mut auth) = self.inner.write() {
            auth.set_device_code(device_code);
        }
    }

    /// 生成当前时刻的 Token V3。
    pub fn get_app_token(&self) -> UniResult<String> {
        self.inner
            .read()
            .map_err(|_| CoolapkError::Failed { message: "failed to lock auth state".into() })?
            .get_app_token()
            .map_err(CoolapkError::from_string)
    }
}

/// 酷安 API 客户端:一次构造,全局持有。
/// cookie 持久化路径由 Swift 侧传入选定的应用支持目录。
#[derive(uniffi::Object)]
pub struct CoolapkApi {
    client: Arc<CoolapkClient>,
}

#[uniffi::export(async_runtime = "tokio")]
impl CoolapkApi {
    #[uniffi::constructor]
    pub fn new(cookie_store_path: Option<String>) -> Arc<Self> {
        let client = CoolapkClient::new();
        if let Some(path) = cookie_store_path {
            client.persist_cookie_to(PathBuf::from(path));
        }
        client.sync_device_code();
        Arc::new(Self {
            client: Arc::new(client),
        })
    }

    // MARK: 会话状态

    pub fn set_user_cookie(&self, cookie: String) -> UniResult<()> {
        self.client.set_user_cookie(cookie).map_err(CoolapkError::from_string)
    }

    pub fn get_user_cookie(&self) -> Option<String> {
        self.client.get_user_cookie()
    }

    /// 校验当前会话有效性(合并 login_info 与 user/space 数据)。
    pub async fn check_login_status(&self) -> UniResult<String> {
        to_json_string(self.client.check_login_status().await.map_err(CoolapkError::from_string)?)
    }

    /// 把通过校验的登录会话写入账户库并设为当前登录态。
    pub async fn save_account(
        &self,
        uid: String,
        username: String,
        user_avatar: String,
        cookie: String,
    ) -> UniResult<String> {
        to_json_string(
            self.client
                .save_account(&uid, &username, &user_avatar, &cookie)
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    // MARK: 信息流

    pub async fn get_index_v8_feeds(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_index_v8_feeds(page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_hot_feeds(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_hot_feeds(page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_latest_feeds(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_latest_feeds(page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_rank_feeds(&self, rank_type: String, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_rank_feeds(&rank_type, page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_feed_detail(&self, feed_id: String) -> UniResult<String> {
        to_json_string(self.client.get_feed_detail(&feed_id).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_feed_replies(&self, feed_id: String, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_feed_replies(&feed_id, page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_hot_replies(&self, feed_id: String, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_hot_replies(&feed_id, page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_hot_topics(&self) -> UniResult<String> {
        to_json_string(self.client.get_hot_topics().await.map_err(CoolapkError::from_string)?)
    }

    // MARK: 应用与用户

    pub async fn get_app_detail(&self, package_name: String) -> UniResult<String> {
        to_json_string(self.client.get_app_detail(&package_name).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_user_profile(&self, uid: String) -> UniResult<String> {
        to_json_string(self.client.get_user_profile(&uid).await.map_err(CoolapkError::from_string)?)
    }

    // MARK: 搜索

    pub async fn search_all(&self, query: String, page: u32) -> UniResult<String> {
        to_json_string(self.client.search_all(&query, page).await.map_err(CoolapkError::from_string)?)
    }
}
