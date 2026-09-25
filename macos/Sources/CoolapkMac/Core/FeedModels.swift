import Foundation

// MARK: - JSON 容错解析工具

enum CoolapkJSON {
    /// 从接口 JSON 字符串提取实体数组:兼容 `data` 为数组或对象(rows/items/data)。
    static func entities(fromJSONString json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return entities(fromRoot: root)
    }

    static func entities(fromRoot root: [String: Any]) -> [[String: Any]] {
        switch root["data"] {
        case let list as [Any]:
            return list.compactMap { $0 as? [String: Any] }
        case let dict as [String: Any]:
            let rows = (dict["rows"] ?? dict["items"] ?? dict["data"]) as? [Any] ?? []
            return rows.compactMap { $0 as? [String: Any] }
        default:
            return []
        }
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    /// 用户字段:热榜实体是扁平的 username/userAvatar,详情接口是嵌套 user{}。
    static func username(_ entity: [String: Any]) -> String {
        if let flat = string(entity["username"]) { return flat }
        let user = entity["user"] as? [String: Any] ?? [:]
        return string(user["username"]) ?? ""
    }

    static func avatar(_ entity: [String: Any]) -> URL? {
        let raw = string(entity["userAvatar"]) ?? {
            let user = entity["user"] as? [String: Any] ?? [:]
            return string(user["avatar"])
        }()
        return raw.flatMap(httpsURL)
    }

    static func pics(_ entity: [String: Any]) -> [URL] {
        let candidates: [Any?] = [entity["pics"], entity["picArr"], entity["pic"], entity["cover"], entity["logo"]]
            .compactMap { $0 }
        for candidate in candidates {
            if let list = candidate as? [Any] {
                let urls = list.compactMap { string($0) }.compactMap(httpsURL)
                if !urls.isEmpty { return urls }
            } else if let single = string(candidate), let url = httpsURL(single) {
                return [url]
            }
        }
        return []
    }

    /// 酷安图片 CDN 返回的常是 http 明文链接,统一升级 https(ATS 要求,CDN 支持)。
    static func httpsURL(_ raw: String) -> URL? {
        let upgraded = raw.hasPrefix("http://") ? "https://" + raw.dropFirst(7) : raw
        return URL(string: upgraded)
    }

    /// 轻量 HTML 清理:去标签 + 常见实体,列表摘要够用。
    static func cleanHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<br\\s*/?>|</p>|<p[^>]*>",
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, char) in ["&quot;": "\"", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#39;": "'"] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 模型

/// 信息流条目(列表用,容错解析)。
struct FeedItem: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: URL?
    let title: String
    let excerpt: String
    let picURLs: [URL]
    let likeCount: Int
    let replyCount: Int
    let favCount: Int
    let shareCount: Int
    let userLevel: String
    let deviceTitle: String
    let location: String
    let dateline: Date

    init?(entity: [String: Any]) {
        guard let id = CoolapkJSON.string(entity["id"]) else { return nil }
        self.id = id
        self.username = CoolapkJSON.username(entity)
        self.avatarURL = CoolapkJSON.avatar(entity)
        self.title = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["title"]) ?? "")

        let rawMessage = CoolapkJSON.string(entity["message"]) ?? ""
        let message = CoolapkJSON.cleanHTML(rawMessage)
        // 转发/图片类动态的列表占位是 "{username} 的动态",不显示文本,只看图
        let isStub = message == "\(username) 的动态" || message == "\(username)的动态"
        self.excerpt = isStub ? "" : message
        self.picURLs = CoolapkJSON.pics(entity)
        self.likeCount = CoolapkJSON.int(entity["likenum"])
        self.replyCount = CoolapkJSON.int(entity["replynum"])
        self.favCount = CoolapkJSON.int(entity["favnum"])
        self.shareCount = CoolapkJSON.int(entity["sharenum"])
        // userLevel 服务端可能是数字也可能是字符串,CoolapkJSON.string 两者都能吃
        self.userLevel = CoolapkJSON.string(entity["userLevel"]) ?? ""
        self.deviceTitle = CoolapkJSON.string(entity["deviceTitle"]) ?? ""
        self.location = CoolapkJSON.string(entity["location"]) ?? ""
        self.dateline = Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["dateline"])))
        // 运营卡片等非内容实体:没有文本也没有图,跳过
        if title.isEmpty && excerpt.isEmpty && picURLs.isEmpty { return nil }
    }

    /// 展示主文本:优先标题,否则正文摘要。
    /// 快讯等实体的 title 是服务端拼的"{username}的动态"占位,真文案在 message:
    /// title 是占位时回落到正文,两者都是占位才返回空。
    var displayText: String {
        let primary = title.isEmpty ? excerpt : title
        if !Self.isStubText(primary) { return primary }
        let fallback = primary == title ? excerpt : title
        if !Self.isStubText(fallback) { return fallback }
        return ""
    }

    private static func isStubText(_ text: String) -> Bool {
        guard text.count <= 30 else { return false }
        return text.range(of: "^.{0,24} ?的动态$", options: .regularExpression) != nil
    }

    /// 实体缺 dateline 时是 1970 纪元,相对时间会显示"56年前",视为无效。
    var hasValidDateline: Bool {
        dateline.timeIntervalSince1970 > 100_000_000
    }
}

/// 搜索结果分组(接口按 话题/应用/用户/帖子 分组返回)。
struct SearchResultSection: Identifiable, Hashable {
    let title: String
    let items: [SearchResultItem]
    var id: String { title }

    /// 从 search/all 的分组 JSON 解析;兼容 data 为平铺数组的形态。
    static func parse(fromJSONString json: String) -> [SearchResultSection] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        let groups: [[String: Any]]
        switch root["data"] {
        case let list as [Any]:
            groups = list.compactMap { $0 as? [String: Any] }
        case let dict as [String: Any]:
            groups = [dict]
        default:
            groups = []
        }

        return groups.compactMap { group in
            guard let list = group["entities"] as? [Any] else { return nil }
            let rawTitle = CoolapkJSON.string(group["title"])
                ?? CoolapkJSON.string(group["description"])
                ?? "结果"
            let title = rawTitle.hasPrefix("更多相关") ? String(rawTitle.dropPrefix("更多相关")) : rawTitle
            let items = list.compactMap { $0 as? [String: Any] }.compactMap(SearchResultItem.init(entity:))
            return items.isEmpty ? nil : SearchResultSection(title: title, items: items)
        }
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

/// 搜索结果条目:按实体类型分型渲染(对齐原版搜索行为)。
enum SearchResultKind: String, Hashable {
    case feed, apk, topic, user, other

    var label: String {
        switch self {
        case .feed: "动态"
        case .apk: "应用"
        case .topic: "话题"
        case .user: "用户"
        case .other: "结果"
        }
    }
}

struct SearchResultItem: Identifiable, Hashable {
    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String
    let avatarURL: URL?
    let likeCount: Int
    let replyCount: Int
    let feedID: String?

    init?(entity: [String: Any]) {
        let rawKind = (CoolapkJSON.string(entity["entityType"]) ?? "").lowercased()
        let hasFans = CoolapkJSON.int(entity["fansnum"]) > 0
        let hasScore = CoolapkJSON.string(entity["score"]) != nil
            || CoolapkJSON.string(entity["apkname"]) != nil

        if rawKind.contains("user") || (!rawKind.isEmpty && hasFans) {
            kind = .user
        } else if rawKind.contains("apk") || rawKind.contains("app") || hasScore {
            kind = .apk
        } else if rawKind.contains("topic") {
            kind = .topic
        } else if rawKind.contains("feed") {
            kind = .feed
        } else if CoolapkJSON.string(entity["fansnum"]) != nil {
            kind = .user
        } else {
            kind = .other
        }

        guard let id = CoolapkJSON.string(entity["id"]) else { return nil }
        self.id = kind.rawValue + "_" + id

        var rawTitle = ""
        var rawSubtitle = ""
        var rawAvatar: URL?

        switch kind {
        case .user:
            rawTitle = CoolapkJSON.username(entity)
            rawSubtitle = CoolapkJSON.int(entity["fansnum"]) > 0
                ? "粉丝 \(CoolapkJSON.int(entity["fansnum"]))" : ""
            rawAvatar = CoolapkJSON.avatar(entity)
        case .apk:
            rawTitle = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["title"]) ?? "")
            rawSubtitle = CoolapkJSON.string(entity["apkname"]) ?? ""
            rawAvatar = CoolapkJSON.pics(entity).first
        case .topic:
            rawTitle = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["title"]) ?? "")
            rawSubtitle = CoolapkJSON.int(entity["commentnum"]) > 0
                ? "讨论 \(CoolapkJSON.int(entity["commentnum"]))" : ""
            rawAvatar = CoolapkJSON.pics(entity).first
        default:
            rawTitle = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["title"]) ?? "")
            rawSubtitle = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["message"]) ?? "")
            rawAvatar = CoolapkJSON.avatar(entity)
        }
        self.likeCount = CoolapkJSON.int(entity["likenum"])
        self.replyCount = CoolapkJSON.int(entity["replynum"])

        let finalTitle = rawTitle.isEmpty ? rawSubtitle : rawTitle
        self.title = finalTitle
        self.subtitle = rawTitle.isEmpty ? "" : rawSubtitle
        self.avatarURL = rawAvatar

        feedID = (kind == .feed && !finalTitle.isEmpty) ? id : nil
        if finalTitle.isEmpty && kind != .feed { return nil }
        if kind == .feed && finalTitle.isEmpty && CoolapkJSON.pics(entity).isEmpty { return nil }
    }
}

/// 帖子详情(完整实体)。
struct FeedDetail: Identifiable {
    let id: String
    let username: String
    let avatarURL: URL?
    let message: String
    let picURLs: [URL]
    let deviceTitle: String
    let likeCount: Int
    let replyCount: Int
    let favCount: Int
    let shareCount: Int
    let dateline: Date
    let relatedTitle: String

    /// 详情正文:推荐流实体常带 markdown(**加粗**、# 标题),能解析就富文本渲染。
    var attributedMessage: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: message, options: options) {
            return attributed
        }
        return AttributedString(message)
    }

    static func parse(fromJSONString json: String) -> FeedDetail? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // 详情接口把实体放在 data 里(可能是对象或含 rows 的分页结构)。
        let entity: [String: Any]
        if let dict = root["data"] as? [String: Any], dict["id"] != nil {
            entity = dict
        } else if let dict = root["data"] as? [String: Any],
                  let rows = (dict["rows"] ?? dict["data"]) as? [Any],
                  let first = rows.first as? [String: Any] {
            entity = first
        } else {
            entity = root
        }
        guard let id = CoolapkJSON.string(entity["id"]) else { return nil }

        let related = (entity["targetRow"] as? [String: Any]).flatMap { CoolapkJSON.string($0["title"]) } ?? ""

        return FeedDetail(
            id: id,
            username: CoolapkJSON.username(entity),
            avatarURL: CoolapkJSON.avatar(entity),
            message: CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["message"]) ?? ""),
            picURLs: CoolapkJSON.pics(entity),
            deviceTitle: CoolapkJSON.string(entity["deviceTitle"]) ?? "",
            likeCount: CoolapkJSON.int(entity["likenum"]),
            replyCount: CoolapkJSON.int(entity["replynum"]),
            favCount: CoolapkJSON.int(entity["favnum"]),
            shareCount: CoolapkJSON.int(entity["sharenum"]),
            dateline: Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["dateline"]))),
            relatedTitle: related
        )
    }
}

/// 回复条目。
struct ReplyItem: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: URL?
    let message: String
    let likeCount: Int
    let dateline: Date

    init?(entity: [String: Any]) {
        guard let id = CoolapkJSON.string(entity["id"]) else { return nil }
        self.id = id
        self.username = CoolapkJSON.username(entity)
        self.avatarURL = CoolapkJSON.avatar(entity)
        self.message = CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["message"]) ?? "")
        self.likeCount = CoolapkJSON.int(entity["likenum"])
        self.dateline = Date(timeIntervalSince1970: TimeInterval(CoolapkJSON.int(entity["dateline"])))
    }
}
