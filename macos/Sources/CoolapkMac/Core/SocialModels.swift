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
/// 实测(2026-09-25 dump_social):
/// - 评论回复(list)是 notification 实体:发件人在 fromusername/fromUserAvatar/fromUserInfo;
/// - 收到点赞(feedLikeList)是完整动态实体:动态作者是自己,点赞者在 likeUsername/likeAvatar/likeTime;
/// - note 可能带 <a href> 外链(如"登录设备:点击查看"),清理文案的同时要保出可点的链接。
struct NotificationItem: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: URL?
    let note: String
    let dateline: Date
    /// 通知对应的信息流 id(点赞/@我类实体本身是动态),点击通知跳详情用。
    let feedID: String?
    /// note 里的站外链接(如账号安全通知的"点击查看"),无对应动态时点击走浏览器。
    let actionURL: URL?

    /// 酷安的 reltime 转换等场景缺 dateline 时是 1970 纪元,相对时间会显示"56年前"。
    var hasValidDateline: Bool {
        dateline.timeIntervalSince1970 > 100_000_000
    }

    init?(entity: [String: Any]) {
        guard let rawID = CoolapkJSON.string(entity["id"]) ?? CoolapkJSON.string(entity["entityId"])
        else { return nil }
        let likeUser = CoolapkJSON.string(entity["likeUsername"])
        let likeUID = CoolapkJSON.string(entity["likeUid"])
        // 同一条动态可能被多人点赞:实体 id 相同,拼上点赞者 uid 才不会被去重吃掉
        self.id = likeUID.map { rawID + "_" + $0 } ?? rawID

        let fromInfo = entity["fromUserInfo"] as? [String: Any] ?? [:]
        let flatUsername = CoolapkJSON.username(entity)
        self.username = likeUser
            ?? CoolapkJSON.string(entity["fromusername"])
            ?? (flatUsername.isEmpty ? nil : flatUsername)
            ?? CoolapkJSON.string(fromInfo["username"])
            ?? CoolapkJSON.string(fromInfo["displayUsername"])
            ?? ""

        let avatarRaw = CoolapkJSON.string(entity["likeAvatar"])
            ?? CoolapkJSON.string(entity["fromUserAvatar"])
            ?? CoolapkJSON.string(entity["userAvatar"])
            ?? CoolapkJSON.string(fromInfo["userAvatar"])
        self.avatarURL = avatarRaw.flatMap(CoolapkJSON.httpsURL) ?? CoolapkJSON.avatar(entity)

        let message = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["message"]) ?? "")
        let rawNote = CoolapkJSON.string(entity["note"])
        self.note = Self.displayNote(
            rawNote: rawNote, likeUser: likeUser, title: CoolapkJSON.string(entity["title"]), message: message
        )
        // 时间:点赞通知的实体 dateline 是动态发布时间,likeTime 才是点赞时间
        let likeTime = CoolapkJSON.int(entity["likeTime"])
        self.dateline = Date(timeIntervalSince1970: TimeInterval(
            likeTime != 0 ? likeTime : CoolapkJSON.int(entity["dateline"])
        ))

        let entityType = CoolapkJSON.string(entity["entityType"]) ?? ""
        let isFeedEntity = likeUser != nil || entityType.contains("feed")
        self.feedID = isFeedEntity ? rawID : nil
        self.actionURL = rawNote.flatMap(Self.firstLink(in:))
            ?? CoolapkJSON.string(entity["url"]).flatMap {
                $0.hasPrefix("http") ? CoolapkJSON.httpsURL($0) : nil
            }
        if note.isEmpty { return nil }
    }

    /// 展示文案:服务端 note 优先;点赞通知缺 note 时按官方样式拼"赞了你的动态:…"。
    private static func displayNote(rawNote: String?, likeUser: String?, title: String?, message: String) -> String {
        if let rawNote { return CoolapkJSON.cleanHTML(rawNote) }
        guard likeUser != nil else { return message }
        let cleanedTitle = CoolapkJSON.cleanHTML(title ?? "")
        let target: String
        if !cleanedTitle.isEmpty, !isStubTitle(cleanedTitle) {
            target = cleanedTitle
        } else {
            target = String(message.prefix(80))
        }
        return target.isEmpty ? "赞了你的动态" : "赞了你的动态:\(target)"
    }

    /// 动态列表 title 常是服务端拼的"{username} 的动态"占位(与 FeedItem 同规则)。
    private static func isStubTitle(_ text: String) -> Bool {
        guard text.count <= 30 else { return false }
        return text.range(of: "^.{0,24} ?的动态$", options: .regularExpression) != nil
    }

    /// 从含 <a href> 的原始文案里提取第一条站外链接。
    static func firstLink(in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "https?://[\\w\\-./?%&=#:~]+") else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 0
        else { return nil }
        return URL(string: ns.substring(with: match.range))
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

    /// 系统会话(如官方"酷友")可能没有 dateline,1970 纪元显示"56年前"
    var hasValidDateline: Bool {
        dateline.timeIntervalSince1970 > 100_000_000
    }

    init?(entity: [String: Any]) {
        let uid = CoolapkJSON.string(entity["uid"]) ?? CoolapkJSON.string(entity["id"]) ?? ""
        guard !uid.isEmpty else { return nil }
        self.uid = uid
        self.ukey = CoolapkJSON.string(entity["ukey"]) ?? ""
        // recentChatUser 实体只有 uid/userAvatar/userInfo,名字在嵌套的 userInfo 里
        let info = entity["userInfo"] as? [String: Any] ?? [:]
        let flatUsername = CoolapkJSON.username(entity)
        self.username = (flatUsername.isEmpty ? nil : flatUsername)
            ?? CoolapkJSON.string(info["username"])
            ?? CoolapkJSON.string(info["displayUsername"])
            ?? ""
        let avatarRaw = CoolapkJSON.string(entity["userAvatar"])
            ?? CoolapkJSON.string(info["userAvatar"])
        self.avatarURL = avatarRaw.flatMap(CoolapkJSON.httpsURL) ?? CoolapkJSON.avatar(entity)
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
        guard let id = CoolapkJSON.string(entity["id"]) ?? CoolapkJSON.string(entity["entityId"])
        else { return nil }
        self.id = id
        // 聊天实体形态未固定:历史接口与 message/list 都可能用 from* 字段标记发送方
        let messageInfo = entity["messageUserInfo"] as? [String: Any] ?? [:]
        self.uid = CoolapkJSON.string(entity["uid"])
            ?? CoolapkJSON.string(entity["fromuid"])
            ?? CoolapkJSON.string(messageInfo["uid"])
            ?? ""
        let flatUsername = CoolapkJSON.username(entity)
        self.username = (flatUsername.isEmpty ? nil : flatUsername)
            ?? CoolapkJSON.string(entity["fromusername"])
            ?? CoolapkJSON.string(messageInfo["username"])
            ?? CoolapkJSON.string(messageInfo["displayUsername"])
            ?? ""
        let avatarRaw = CoolapkJSON.string(entity["userAvatar"])
            ?? CoolapkJSON.string(entity["fromUserAvatar"])
            ?? CoolapkJSON.string(entity["messageUserAvatar"])
            ?? CoolapkJSON.string(messageInfo["userAvatar"])
        self.avatarURL = avatarRaw.flatMap(CoolapkJSON.httpsURL) ?? CoolapkJSON.avatar(entity)
        self.message = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["message"]) ?? "")
        self.dateline = Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["dateline"])))
    }

    static func parseList(fromJSONString json: String) -> [ChatMessage] {
        CoolapkJSON.entities(fromJSONString: json).compactMap(ChatMessage.init(entity:))
    }
}

// MARK: - 浏览历史

/// 浏览历史(get_recent_history)条目。
/// 实测(2026-09-25 dump_social):实体类型是 recentHistory,不是动态——
/// 无 username/message/userAvatar/dateline,只有 title/logo/target_* 和 lastupdate,
/// target 覆盖 用户(/u/id)/话题(/t/名)/数码(/product/id)/动态(/feed/id),所以不能用 FeedItem 渲染。
struct HistoryItem: Identifiable, Hashable {
    let id: String
    let title: String
    /// target 的展示图:用户头像/话题封面/产品图,历史页当圆形头像用。
    let logoURL: URL?
    /// target 类型名(用户/话题/数码/动态)。
    let kindTitle: String
    let fansNum: Int
    let commentNum: Int
    let lastUpdate: Date
    /// 站内路径,形如 /u/1080570、/t/HyperOS4、/product/4207、/feed/46000001。
    let path: String?

    var hasValidTime: Bool {
        lastUpdate.timeIntervalSince1970 > 100_000_000
    }

    /// 副标题:类型 + 一个最有信息量的计数(用户看粉丝,话题/产品看讨论)。
    var subtitle: String {
        var parts: [String] = []
        if !kindTitle.isEmpty { parts.append(kindTitle) }
        if fansNum > 0 {
            parts.append("粉丝 \(fansNum)")
        } else if commentNum > 0 {
            parts.append("讨论 \(commentNum)")
        }
        return parts.joined(separator: " · ")
    }

    private static func targetID(path: String?, prefix: String) -> String? {
        guard let path, path.hasPrefix(prefix) else { return nil }
        let value = String(path.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    var feedTarget: String? { Self.targetID(path: path, prefix: "/feed/") }
    var userTarget: String? { Self.targetID(path: path, prefix: "/u/") }
    /// 话题 target 是话题名,openTopic 按名拉流。
    var topicTarget: String? { Self.targetID(path: path, prefix: "/t/") }

    init?(entity: [String: Any]) {
        guard let id = CoolapkJSON.string(entity["id"]) ?? CoolapkJSON.string(entity["entityId"])
        else { return nil }
        let title = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["title"]) ?? "")
        guard !title.isEmpty else { return nil }
        self.id = id
        self.title = title
        self.logoURL = CoolapkJSON.string(entity["logo"]).flatMap(CoolapkJSON.httpsURL)
        self.kindTitle = CoolapkJSON.string(entity["target_type_title"]) ?? ""
        self.fansNum = CoolapkJSON.int(entity["fans_num"])
        self.commentNum = CoolapkJSON.int(entity["comment_num"])
        self.lastUpdate = Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["lastupdate"])))
        let rawPath = CoolapkJSON.string(entity["url"]) ?? ""
        self.path = rawPath.hasPrefix("/") ? rawPath : nil
    }

    static func parseList(fromJSONString json: String) -> [HistoryItem] {
        CoolapkJSON.entities(fromJSONString: json).compactMap(HistoryItem.init(entity:))
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
