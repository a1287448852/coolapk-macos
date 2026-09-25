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

    // MARK: 扩展信息流(头条/快讯/收藏/关注/历史)

    pub async fn get_headline_feeds(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_headline_feeds(page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_digest_feeds(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_digest_feeds(page).await.map_err(CoolapkError::from_string)?)
    }

    /// 用户收藏列表。client 实际签名是 (fav_type, page, first_item, last_item):
    /// type 支持 feed/apk/album,这里固定 "feed";服务端按 cookie 识别用户,
    /// uid 参数仅为保持 Swift 侧调用形态一致,不参与请求。
    pub async fn get_favorite_list(&self, uid: String, page: u32) -> UniResult<String> {
        let _ = uid;
        to_json_string(
            self.client
                .get_favorite_list("feed", page, "", "")
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    pub async fn get_following_feeds(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_following_feeds(page).await.map_err(CoolapkError::from_string)?)
    }

    /// 浏览历史。client 还支持 first_item/last_item 游标分页,facade 暂不透传(传 None)。
    pub async fn get_recent_history(&self, page: u32) -> UniResult<String> {
        to_json_string(
            self.client
                .get_recent_history(page, None, None)
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    // MARK: 话题

    /// 话题动态列表(游客可用;tag 形如 "数码日常")。
    pub async fn get_topic_feeds(&self, tag: String, page: u32) -> UniResult<String> {
        to_json_string(
            self.client
                .get_topic_feeds(&tag, page, "", "", "", 0)
                .await
                .map_err(CoolapkError::from_string)?,
        )
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

    /// 发布动态(需登录)。pic 为已上传图片的 URL,文字动态传 None。
    pub async fn create_feed(
        &self,
        message: String,
        pic: Option<String>,
        post_token: Option<String>,
    ) -> UniResult<String> {
        to_json_string(
            self.client
                .create_feed(&message, pic.as_deref(), post_token.as_deref())
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    /// 用户主页(/v6/user/space:资料 + 统计)。
    pub async fn get_user_space(&self, uid: String) -> UniResult<String> {
        to_json_string(self.client.get_user_space(&uid).await.map_err(CoolapkError::from_string)?)
    }

    /// 用户动态列表(feed_type: feed/picture/reply/rating/fav)。
    pub async fn get_user_feeds(&self, uid: String, page: u32, feed_type: String) -> UniResult<String> {
        to_json_string(
            self.client
                .get_user_feeds(&uid, page, &feed_type)
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    /// 应用专项搜索(search/all 不含应用分组,应用走独立的 type=apk 搜索)。
    pub async fn search_apks(&self, query: String, page: u32) -> UniResult<String> {
        to_json_string(self.client.search_apks(&query, page).await.map_err(CoolapkError::from_string)?)
    }

    // MARK: 通知

    /// 通知列表。notification_type: list(评论回复)/atMeList(@我)/
    /// atCommentMeList(评论@我)/feedLikeList(点赞)/contactsFollowList(新关注)。
    pub async fn get_notifications(&self, notification_type: String, page: u32) -> UniResult<String> {
        to_json_string(
            self.client
                .get_notifications(&notification_type, page)
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    pub async fn get_notification_count(&self) -> UniResult<String> {
        to_json_string(self.client.get_notification_count().await.map_err(CoolapkError::from_string)?)
    }

    // MARK: 私信

    pub async fn list_messages(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.list_messages(page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn get_recent_chat_users(&self, page: u32) -> UniResult<String> {
        to_json_string(self.client.get_recent_chat_users(page).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn list_chat_history(&self, ukey: String, page: u32) -> UniResult<String> {
        to_json_string(self.client.list_chat_history(&ukey, page).await.map_err(CoolapkError::from_string)?)
    }

    /// 发送私信(需登录;服务端有风控,失败时 message 透传给 UI)。
    pub async fn send_private_message(&self, uid: String, message: String) -> UniResult<String> {
        to_json_string(
            self.client
                .send_private_message(&uid, &message)
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    // MARK: 互动(需登录;写接口受服务端风控约束)

    pub async fn like_feed(&self, feed_id: String) -> UniResult<String> {
        to_json_string(self.client.like_feed(&feed_id).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn unlike_feed(&self, feed_id: String) -> UniResult<String> {
        to_json_string(self.client.unlike_feed(&feed_id).await.map_err(CoolapkError::from_string)?)
    }

    pub async fn favorite_feed(&self, feed_id: String) -> UniResult<String> {
        to_json_string(self.client.favorite_feed(&feed_id).await.map_err(CoolapkError::from_string)?)
    }

    /// 发表评论。rid 非空表示回复某条评论。
    pub async fn reply_feed(&self, feed_id: String, message: String, rid: Option<String>) -> UniResult<String> {
        to_json_string(
            self.client
                .reply_feed(&feed_id, &message, rid.as_deref(), None, None)
                .await
                .map_err(CoolapkError::from_string)?,
        )
    }

    // MARK: APK 下载

    /// 解析包名 → 最新版本的官方下载地址(带 aid/versionCode,配合签名请求头使用)。
    pub async fn resolve_latest_apk_download(&self, package_name: String) -> UniResult<String> {
        let value = self
            .client
            .get_download_version_list(&package_name)
            .await
            .map_err(CoolapkError::from_string)?;
        let aid = value["aid"].as_str().unwrap_or_default();
        let versions = value["data"].as_array().cloned().unwrap_or_default();
        let first = versions.first().cloned().unwrap_or(serde_json::Value::Null);
        let version_code = first
            .get("versionCode")
            .map(|v| match v {
                serde_json::Value::String(text) => text.clone(),
                other => other.to_string(),
            })
            .unwrap_or_default();
        if aid.is_empty() || version_code.is_empty() {
            return Err(CoolapkError::Failed {
                message: "没有找到可下载的版本".into(),
            });
        }
        let url = format!(
            "https://api.coolapk.com/v6/apk/download?pn={}&aid={}&vc={}&extra=",
            package_name, aid, version_code
        );
        let version_name = first
            .get("versionName")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        to_json_string(serde_json::json!({
            "url": url,
            "packageName": package_name,
            "versionName": version_name,
            "versionCode": version_code
        }))
    }

    /// 导出带签名与设备指纹的请求头(JSON 对象),供 Swift URLSession 下载 APK 使用。
    ///
    /// 必须同时带 Dalvik(安卓 App)UA:实测 v6/apk/download 端点对浏览器 UA 返回
    /// 403/567 反爬挑战,只有安卓 App UA + 指纹头组合才返回 200 + APK 流。
    pub fn download_headers(&self) -> UniResult<String> {
        let request = self
            .client
            .apply_download_headers(reqwest::Client::new().get("https://api.coolapk.com/"))
            .map_err(CoolapkError::from_string)?
            .header(
                reqwest::header::USER_AGENT,
                "Dalvik/2.1.0 (Linux; U; Android 16; 23113RKC6C Build/AQ3A.250226.002) +CoolMarket/16.2.0-2604201-universal",
            )
            .header(reqwest::header::REFERER, "https://www.coolapk.com/")
            .build()
            .map_err(|e| CoolapkError::Failed { message: format!("build request failed: {e}") })?;
        let map: serde_json::Map<String, serde_json::Value> = request
            .headers()
            .iter()
            .map(|(name, value)| {
                (
                    name.as_str().to_string(),
                    serde_json::Value::String(value.to_str().unwrap_or_default().to_string()),
                )
            })
            .collect();
        to_json_string(serde_json::Value::Object(map))
    }
}
