import Foundation
import CoolapkCoreSwift
import Observation

extension CoolapkApi {
    /// 单例:cookie/设备码持久化到 Application Support/CoolapkMac。
    static let shared: CoolapkApi = CoolapkApi(cookieStorePath: CoolapkApi.makeStoreURL().path)

    static func makeStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoolapkMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("accounts.json")
    }
}

/// 侧栏信息流分类。
enum FeedCategory: String, CaseIterable, Identifiable, Hashable {
    case recommend = "推荐"
    case hot = "热门"
    case month = "月榜"
    case favorite = "收藏榜"
    case reply = "回复榜"
    case picture = "酷图"
    case latest = "最新"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .recommend: "sparkles"
        case .hot: "flame"
        case .month: "calendar"
        case .favorite: "star"
        case .reply: "bubble.left.and.bubble.right"
        case .picture: "photo.on.rectangle"
        case .latest: "clock"
        }
    }
}

/// 当前登录用户(来自 /user/space)。
struct UserProfile: Hashable {
    let uid: String
    let username: String
    let avatarURL: URL?
}

/// 全局应用模型:分类信息流 + 详情 + 回复 + 登录会话 + 搜索。
@MainActor
@Observable
final class AppModel {
    // MARK: 信息流状态

    var category: FeedCategory = .hot {
        didSet { if category != oldValue { Task { await loadFeeds(reset: true) } } }
    }
    private(set) var feeds: [FeedItem] = []
    private(set) var statusText = ""
    private var page = 1
    private var hasMoreFeeds = true
    private var isLoadingFeeds = false

    // MARK: 搜索

    var searchQuery = ""
    private(set) var searchSections: [SearchResultSection]?
    private(set) var isSearching = false
    private(set) var searchStatusText = ""

    var isSearchActive: Bool { searchSections != nil }

    // MARK: 详情与回复

    var selectedFeedID: String?
    private(set) var detail: FeedDetail?
    private(set) var detailError: String?
    private(set) var replies: [ReplyItem] = []
    private(set) var isLoadingDetail = false
    private(set) var isLoadingMoreReplies = false
    private var repliesPage = 1
    private var hasMoreReplies = true

    private let api = CoolapkApi.shared

    init() {}

    // MARK: 登录会话

    private(set) var userProfile: UserProfile?
    private(set) var loginError: String?

    /// 启动时恢复已保存的登录态(accounts.json 有 cookie 时拉资料)。
    func restoreSession() async {
        guard userProfile == nil, api.getUserCookie() != nil else { return }
        await refreshProfile()
    }

    /// 登录窗口带回完整 cookie 后:设置会话 → 拉资料 → 写入账户库。
    func completeLogin(cookie: String) async {
        loginError = nil
        do {
            try api.setUserCookie(cookie: cookie)
            await refreshProfile()
            if userProfile == nil {
                loginError = "登录凭据已收到,但用户资料校验失败,请重试"
            }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { loginError = Self.friendlyError(message) }
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() async {
        try? api.setUserCookie(cookie: "")
        userProfile = nil
        selectedFeedID = nil
        detail = nil
        detailError = nil
        replies = []
    }

    private func refreshProfile() async {
        guard let cookie = api.getUserCookie(),
              let uid = Self.cookieValue(cookie, name: "uid"), uid != "0"
        else {
            userProfile = nil
            return
        }
        do {
            let json = try await api.getUserProfile(uid: uid)
            guard let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entity = root["data"] as? [String: Any]
            else { userProfile = nil; return }

            let username = CoolapkJSON.string(entity["username"]) ?? "酷友"
            let avatar = CoolapkJSON.string(entity["userAvatar"]) ?? ""
            _ = try? await api.saveAccount(
                uid: uid, username: username, userAvatar: avatar, cookie: cookie
            )
            userProfile = UserProfile(
                uid: uid,
                username: username,
                avatarURL: avatar.isEmpty ? nil : CoolapkJSON.httpsURL(avatar)
            )
        } catch {
            userProfile = nil
        }
    }

    private static func cookieValue(_ cookie: String, name: String) -> String? {
        for pair in cookie.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.first.map({ $0.trimmingCharacters(in: .whitespaces) }) == name {
                return parts.last.map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }

    // MARK: 信息流

    func refresh() async {
        await loadFeeds(reset: true)
    }

    func loadMoreIfNeeded(current feed: FeedItem) async {
        guard feed.id == feeds.last?.id, hasMoreFeeds, !isLoadingFeeds else { return }
        await loadFeeds(reset: false)
    }

    func loadFeeds(reset: Bool) async {
        guard !isLoadingFeeds else { return }
        isLoadingFeeds = true
        defer { isLoadingFeeds = false }

        if reset {
            page = 1
            hasMoreFeeds = true
        }
        statusText = ""

        do {
            let json: String
            switch category {
            case .recommend:
                json = try await api.getIndexV8Feeds(page: UInt32(page))
            case .hot:
                json = try await api.getHotFeeds(page: UInt32(page))
            case .latest:
                json = try await api.getLatestFeeds(page: UInt32(page))
            case .month:
                json = try await api.getRankFeeds(rankType: "month", page: UInt32(page))
            case .favorite:
                json = try await api.getRankFeeds(rankType: "favorite", page: UInt32(page))
            case .reply:
                json = try await api.getRankFeeds(rankType: "index", page: UInt32(page))
            case .picture:
                json = try await api.getRankFeeds(rankType: "picture", page: UInt32(page))
            }

            let parsed = CoolapkJSON.entities(fromJSONString: json)
                .compactMap(FeedItem.init(entity:))
            if reset {
                feeds = parsed
            } else {
                let known = Set(feeds.map(\.id))
                feeds += parsed.filter { !known.contains($0.id) }
            }
            hasMoreFeeds = !parsed.isEmpty
            if reset { page = 2 } else { page += 1 }
            if feeds.isEmpty { statusText = "暂无内容" }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { statusText = "加载失败:\(Self.friendlyError(message))" }
        } catch {
            statusText = "加载失败:\(error.localizedDescription)"
        }
    }

    // MARK: 搜索

    func runSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        searchStatusText = ""
        do {
            let json = try await api.searchAll(query: query, page: 1)
            let sections = SearchResultSection.parse(fromJSONString: json)
            searchSections = sections
            if sections.isEmpty { searchStatusText = "没有找到相关内容" }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { searchStatusText = "搜索失败:\(Self.friendlyError(message))" }
        } catch {
            searchStatusText = "搜索失败:\(error.localizedDescription)"
        }
    }

    func clearSearch() {
        searchSections = nil
        searchStatusText = ""
    }

    // MARK: 详情与回复

    func select(feedID: String) async {
        guard selectedFeedID != feedID else { return }
        selectedFeedID = feedID
        detail = nil
        detailError = nil
        replies = []
        // 详情接口偶尔触发服务端风控(403 验证码),评论接口通常可用:
        // 两条链路独立加载,详情失败时依然展示评论。
        await loadDetail(feedID: feedID)
        await loadReplies(reset: true)
    }

    private func loadDetail(feedID: String) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            detail = FeedDetail.parse(fromJSONString: try await api.getFeedDetail(feedId: feedID))
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { detailError = Self.friendlyError(message) }
        } catch {
            detailError = error.localizedDescription
        }
    }

    func loadReplies(reset: Bool) async {
        guard let feedID = selectedFeedID else { return }
        if reset {
            repliesPage = 1
            hasMoreReplies = true
            isLoadingMoreReplies = true
        } else {
            guard hasMoreReplies, !isLoadingMoreReplies else { return }
            isLoadingMoreReplies = true
        }
        defer { isLoadingMoreReplies = false }

        do {
            let json = try await api.getFeedReplies(feedId: feedID, page: UInt32(repliesPage))
            let parsed = CoolapkJSON.entities(fromJSONString: json)
                .compactMap(ReplyItem.init(entity:))
            if reset {
                replies = parsed
            } else {
                let known = Set(replies.map(\.id))
                replies += parsed.filter { !known.contains($0.id) }
            }
            hasMoreReplies = !parsed.isEmpty
            if reset { repliesPage = 2 } else { repliesPage += 1 }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { statusText = "评论加载失败:\(Self.friendlyError(message))" }
        } catch {
            statusText = "评论加载失败:\(error.localizedDescription)"
        }
    }

    /// 服务端错误常把嵌套 JSON 拼在文案里(如 403 验证码),正则提取第一条人话 message。
    nonisolated private static func friendlyError(_ message: String) -> String {
        let pattern = "\"message\":\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return message }
        let nsMessage = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: nsMessage.length)),
              match.numberOfRanges > 1
        else { return message }

        let escaped = nsMessage.substring(with: match.range(at: 1))
        let unescaped = escaped
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\n", with: "\n")
        return unescaped.isEmpty ? message : unescaped
    }
}
