import Foundation

// MARK: - 通知

/// 通知类型(与 Rust 侧 get_notifications 的类型白名单一致)。
enum NotificationType: String, CaseIterable, Identifiable, Hashable {
    case reply = "list"
    case atMe = "atMeList"
    case commentAtMe = "atCommentMeList"
    case feedLike = "feedLikeList"
    case follow = "contactsFollowList"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reply: "评论回复"
        case .atMe: "@我"
        case .commentAtMe: "评论@我"
        case .feedLike: "收到点赞"
        case .follow: "新关注"
        }
    }
}

/// 通知条目:服务端形态未完全固定,全部容错解析。
struct NotificationItem: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: URL?
    let note: String
    let dateline: Date

    init?(entity: [String: Any]) {
        guard let id = CoolapkJSON.string(entity["id"]) else { return nil }
        self.id = id
        self.username = CoolapkJSON.username(entity)
        self.avatarURL = CoolapkJSON.avatar(entity)
        self.note = CoolapkJSON.cleanHTML(
            CoolapkJSON.string(entity["note"]) ?? CoolapkJSON.string(entity["message"]) ?? ""
        )
        self.dateline = Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["dateline"])))
        if note.isEmpty { return nil }
    }

    static func parseList(fromJSONString json: String) -> [NotificationItem] {
        CoolapkJSON.entities(fromJSONString: json).compactMap(NotificationItem.init(entity:))
    }
}

// MARK: - 私信

/// 私信会话(来自 recentChatUser / message list)。
struct ChatUser: Identifiable, Hashable {
    let uid: String
    let ukey: String
    let username: String
    let avatarURL: URL?
    let lastMessage: String
    let dateline: Date

    var id: String { ukey.isEmpty ? uid : ukey }

    init?(entity: [String: Any]) {
        let uid = CoolapkJSON.string(entity["uid"]) ?? CoolapkJSON.string(entity["id"]) ?? ""
        guard !uid.isEmpty else { return nil }
        self.uid = uid
        self.ukey = CoolapkJSON.string(entity["ukey"]) ?? ""
        self.username = CoolapkJSON.username(entity)
        self.avatarURL = CoolapkJSON.avatar(entity)
        self.lastMessage = CoolapkJSON.cleanHTML(
            CoolapkJSON.string(entity["message"]) ?? CoolapkJSON.string(entity["lastMessage"]) ?? ""
        )
        self.dateline = Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["dateline"])))
    }

    static func parseList(fromJSONString json: String) -> [ChatUser] {
        CoolapkJSON.entities(fromJSONString: json).compactMap(ChatUser.init(entity:))
    }
}

/// 私信消息(来自 chat history)。
struct ChatMessage: Identifiable, Hashable {
    let id: String
    let uid: String
    let username: String
    let avatarURL: URL?
    let message: String
    let dateline: Date

    init?(entity: [String: Any]) {
        guard let id = CoolapkJSON.string(entity["id"]) else { return nil }
        self.id = id
        self.uid = CoolapkJSON.string(entity["uid"]) ?? ""
        self.username = CoolapkJSON.username(entity)
        self.avatarURL = CoolapkJSON.avatar(entity)
        self.message = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["message"]) ?? "")
        self.dateline = Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["dateline"])))
    }

    static func parseList(fromJSONString json: String) -> [ChatMessage] {
        CoolapkJSON.entities(fromJSONString: json).compactMap(ChatMessage.init(entity:))
    }
}

// MARK: - APK 下载版本

/// getDownloadVersionList 结果里的可下载版本。
struct DownloadVersion: Identifiable, Hashable {
    /// parseList 会用调用方传入的包名覆盖实体里的包名,所以需要 var。
    var packageName: String
    let versionName: String
    let url: URL

    var id: String { packageName + "@" + versionName }

    init?(entity: [String: Any]) {
        guard let url = CoolapkJSON.httpsURL(CoolapkJSON.string(entity["url"]) ?? ""),
              url.absoluteString.hasSuffix(".apk") || url.absoluteString.contains("/apk/")
        else { return nil }
        self.url = url
        self.packageName = CoolapkJSON.string(entity["packagenname"])
            ?? CoolapkJSON.string(entity["apkname"])
            ?? CoolapkJSON.string(entity["name"])
            ?? url.lastPathComponent
        self.versionName = CoolapkJSON.string(entity["version_name"])
            ?? CoolapkJSON.string(entity["versionname"])
            ?? CoolapkJSON.string(entity["version"])
            ?? "未知版本"
    }

    static func parseList(fromJSONString json: String, packageName: String) -> [DownloadVersion] {
        CoolapkJSON.entities(fromJSONString: json).compactMap { entity in
            var version = DownloadVersion(entity: entity)
            version?.packageName = packageName
            return version
        }
    }
}
