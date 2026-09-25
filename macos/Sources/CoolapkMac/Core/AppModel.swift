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
    case home = "首页"
    case headline = "头条"
    case hot = "热门"
    case digest = "快讯"
    case month = "月榜"
    case favorite = "收藏榜"
    case reply = "回复榜"
    case picture = "酷图"
    case latest = "最新"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .headline: "newspaper"
        case .hot: "flame"
        case .digest: "bolt"
        case .month: "calendar"
        case .favorite: "star"
        case .reply: "bubble.left.and.bubble.right"
        case .picture: "photo.on.rectangle"
        case .latest: "clock"
        }
    }
}

/// 侧栏入口:信息流分类 + 个人功能区。
enum SidebarEntry: Hashable, Identifiable {
    case feed(FeedCategory)
    case notifications, messages, favorites, following, history, downloads

    var id: String {
        switch self {
        case .feed(let category): "feed-\(category.rawValue)"
        case .notifications: "notifications"
        case .messages: "messages"
        case .favorites: "favorites"
        case .following: "following"
        case .history: "history"
        case .downloads: "downloads"
        }
    }

    var title: String {
        switch self {
        case .feed(let category): category.rawValue
        case .notifications: "通知"
        case .messages: "消息"
        case .favorites: "收藏"
        case .following: "我关注的"
        case .history: "历史"
        case .downloads: "下载"
        }
    }

    var systemImage: String {
        switch self {
        case .feed(let category): category.systemImage
        case .notifications: "bell"
        case .messages: "message"
        case .favorites: "bookmark"
        case .following: "person.2"
        case .history: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        }
    }
}

/// 个人功能区的列表类型(收藏榜信息流之外的个人收藏/关注/历史)。
enum PersonalListKind: String { case favorites, following, history }

/// 详情栏"热门话题"挂件条目(容错解析;实际返回 {"tag","count"})。
struct HotTopicItem: Identifiable, Hashable {
    let id: String
    let title: String
    let hotNum: Int

    init?(entity: [String: Any]) {
        guard let id = CoolapkJSON.string(entity["id"]) ?? CoolapkJSON.string(entity["tag"]),
              let title = CoolapkJSON.string(entity["tag"]) ?? CoolapkJSON.string(entity["title"])
        else { return nil }
        self.id = id
        self.title = CoolapkJSON.cleanHTML(title)
        self.hotNum = CoolapkJSON.int(entity["count"])
            ?? CoolapkJSON.int(entity["hot_num"])
            ?? CoolapkJSON.int(entity["hotNum"])
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

    var category: FeedCategory = .home {
        didSet { if category != oldValue { Task { await loadFeeds(reset: true) } } }
    }
    private(set) var feeds: [FeedItem] = []
    private(set) var statusText = ""
    private var page = 1
    private var hasMoreFeeds = true
    // 代数计数:快速切换分类/会话/话题时,只有最新一次请求的结果落地
    private var feedsGeneration = 0
    private var activeFeedLoads = 0
    private var isLoadingFeeds = false

    // MARK: 侧栏导航

    /// 当前侧栏选中项。切到其他信息流分类时同步 category(由其 didSet 触发加载);
    /// 切到收藏/关注/历史时同步 personalKind 并在列表为空时加载。
    var entry: SidebarEntry = .feed(.home) {
        didSet {
            guard entry != oldValue else { return }
            switch entry {
            case .feed(let newCategory):
                if newCategory != category { category = newCategory }
            case .favorites:
                setPersonalKind(.favorites)
            case .following:
                setPersonalKind(.following)
            case .history:
                setPersonalKind(.history)
            case .notifications, .messages, .downloads:
                break
            }
        }
    }

    var showLoginSheet = false
    var isLoggedIn: Bool { userProfile != nil }

    /// 当前用户 uid:优先已拉取的资料,否则从 cookie 里解析。
    var currentUID: String? {
        if let uid = userProfile?.uid, !uid.isEmpty { return uid }
        guard let cookie = api.getUserCookie(),
              let uid = Self.cookieValue(cookie, name: "uid"),
              uid != "0"
        else { return nil }
        return uid
    }

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

    // MARK: 详情栏热榜挂件

    private(set) var hotPanelFeeds: [FeedItem] = []
    private(set) var hotPanelTopics: [HotTopicItem] = []
    private var hasLoadedHotPanel = false

    private let api = CoolapkApi.shared

    init() {}

    /// 详情栏默认挂件:本月热榜 + 热门话题(整个会话只拉一次)。
    func loadHotPanel() async {
        guard !hasLoadedHotPanel else { return }
        hasLoadedHotPanel = true
        if let json = try? await api.getRankFeeds(rankType: "month", page: 1) {
            hotPanelFeeds = Array(CoolapkJSON.entities(fromJSONString: json)
                .compactMap(FeedItem.init(entity:)).prefix(8))
        }
        if let json = try? await api.getHotTopics() {
            hotPanelTopics = Array(CoolapkJSON.entities(fromJSONString: json)
                .compactMap(HotTopicItem.init(entity:)).prefix(10))
        }
    }

    // MARK: 话题动态(点热门话题挂件进入)

    private(set) var selectedTopicTag: String?
    private(set) var topicFeeds: [FeedItem] = []
    private(set) var topicStatus = ""
    private var topicPage = 1

    func openTopic(tag: String) async {
        guard selectedTopicTag != tag else { return }
        selectedTopicTag = tag
        // 话题面板优先于其它详情:点话题即退出详情/应用/用户浏览
        selectedFeedID = nil
        detail = nil
        detailError = nil
        replies = []
        selectedApkPackage = nil
        apkDetail = nil
        apkDetailError = ""
        selectedUserUID = nil
        userSpace = nil
        userFeeds = []
        topicFeeds = []
        await loadTopicFeeds(reset: true)
    }

    func closeTopic() {
        selectedTopicTag = nil
        topicFeeds = []
    }

    func loadTopicFeeds(reset: Bool) async {
        guard let tag = selectedTopicTag else { return }
        if reset { topicPage = 1 }
        topicStatus = ""
        do {
            let json = try await api.getTopicFeeds(tag: tag, page: UInt32(topicPage))
            let parsed = CoolapkJSON.entities(fromJSONString: json)
                .compactMap(FeedItem.init(entity:))
            if reset {
                topicFeeds = parsed
            } else {
                let known = Set(topicFeeds.map(\.id))
                topicFeeds += parsed.filter { !known.contains($0.id) }
            }
            if reset { topicPage = 2 } else { topicPage += 1 }
            if topicFeeds.isEmpty { topicStatus = "该话题暂无动态" }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { topicStatus = "加载失败:\(Self.friendlyError(message))" }
        } catch {
            topicStatus = "加载失败:\(error.localizedDescription)"
        }
    }

    // MARK: 登录会话

    private(set) var userProfile: UserProfile?
    private(set) var loginError: String?

    /// 弹窗内"重试登录"前清掉上次的错误。
    func clearLoginError() {
        loginError = nil
    }
    private(set) var isCompletingLogin = false

    /// 启动时恢复已保存的登录态(accounts.json 有 cookie 时拉资料)。
    func restoreSession() async {
        guard userProfile == nil, api.getUserCookie() != nil else { return }
        await refreshProfile()
        await refreshNotificationBadge()
    }

    /// 登录窗口带回完整 cookie 后:设置会话 → 拉资料 → 写入账户库。
    /// 校验结果落在 loginError / userProfile 上,弹窗据此决定关闭还是显示错误。
    func completeLogin(cookie: String) async {
        loginError = nil
        isCompletingLogin = true
        defer { isCompletingLogin = false }
        do {
            try api.setUserCookie(cookie: cookie)
            await refreshProfile()
            if userProfile == nil {
                loginError = "会话已提取,但资料校验失败(可能被风控拦截)。请点击重试重新登录。"
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
        guard feed.id == feeds.last?.id, hasMoreFeeds else { return }
        await loadFeeds(reset: false)
    }

    func loadFeeds(reset: Bool) async {
        // 代数模式:快速切换分类时新旧请求并发,只有最新一代的结果落地
        feedsGeneration += 1
        let generation = feedsGeneration
        activeFeedLoads += 1
        isLoadingFeeds = true

        if reset {
            page = 1
            hasMoreFeeds = true
        }
        statusText = ""

        do {
            let json: String
            switch category {
            case .home:
                json = try await api.getIndexV8Feeds(page: UInt32(page))
            case .headline:
                json = try await api.getHeadlineFeeds(page: UInt32(page))
            case .digest:
                json = try await api.getDigestFeeds(page: UInt32(page))
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

            defer { activeFeedLoads -= 1 }
            guard generation == feedsGeneration else { return }
            if activeFeedLoads == 0 { isLoadingFeeds = false }

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
        } catch {
            defer { activeFeedLoads -= 1 }
            guard generation == feedsGeneration else { return }
            if activeFeedLoads == 0 { isLoadingFeeds = false }
            if let error = error as? CoolapkError, case .Failed(let message) = error {
                statusText = "加载失败:\(Self.friendlyError(message))"
            } else {
                statusText = "加载失败:\(error.localizedDescription)"
            }
        }
    }

    // MARK: 搜索

    func runSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        searchStatusText = ""
        // search/all 只有话题/数码/用户/帖子;应用分组来自独立的 type=apk 搜索
        async let allTask = api.searchAll(query: query, page: 1)
        async let apkTask = api.searchApks(query: query, page: 1)
        do {
            var sections = SearchResultSection.parse(fromJSONString: try await allTask)
            if let apkJSON = try? await apkTask {
                let apps = SearchResultSection.parseApkList(fromJSONString: apkJSON)
                if !apps.isEmpty {
                    sections.insert(SearchResultSection(title: "应用", items: apps), at: 0)
                }
            }
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
        searchQuery = ""
        // 退出搜索时连带清掉详情/话题/应用/用户栈,否则右列会残留搜索期间打开的僵尸面板
        selectedFeedID = nil
        detail = nil
        detailError = nil
        replies = []
        selectedTopicTag = nil
        topicFeeds = []
        selectedApkPackage = nil
        apkDetail = nil
        apkDetailError = ""
        selectedUserUID = nil
        userSpace = nil
        userFeeds = []
    }

    /// 搜索结果里打开的动态不在 feeds 列表中,风控降级时从搜索结果里找摘要。
    func searchItem(forFeedID feedID: String) -> SearchResultItem? {
        searchSections?.flatMap(\.items).first { $0.feedID == feedID }
    }

    /// 数码产品名不是话题名("小米18 Pro Max" vs 话题"小米18ProMax"),
    /// 直接拉话题流会得到空列表;先在同一次搜索结果里找同名话题实体。
    func topicTag(forProductTitle title: String) -> String? {
        let key = title.filter { !$0.isWhitespace }
        return searchSections?.flatMap(\.items).first {
            $0.kind == .topic && $0.title.filter { !$0.isWhitespace } == key
        }?.title
    }

    // MARK: 详情与回复

    func select(feedID: String) async {
        guard selectedFeedID != feedID else { return }
        selectedFeedID = feedID
        // 详情优先于其它面板:点卡片即退出话题/应用/用户浏览
        selectedTopicTag = nil
        topicFeeds = []
        selectedApkPackage = nil
        apkDetail = nil
        apkDetailError = ""
        selectedUserUID = nil
        userSpace = nil
        userFeeds = []
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
            let json = try await api.getFeedDetail(feedId: feedID)
            // 用户已点开另一条动态:丢弃过期结果
            guard selectedFeedID == feedID else { return }
            detail = FeedDetail.parse(fromJSONString: json)
        } catch let error as CoolapkError {
            guard selectedFeedID == feedID else { return }
            if case .Failed(let message) = error { detailError = Self.friendlyError(message) }
        } catch {
            guard selectedFeedID == feedID else { return }
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
            // 已切换到别的动态:丢弃过期结果
            guard selectedFeedID == feedID else { return }
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
        } catch {
            // 过期结果静默丢弃,不打扰当前浏览
        }
    }

    // MARK: 通知

    var notificationType: NotificationType = .atMe {
        didSet {
            if notificationType != oldValue { Task { await loadNotifications(reset: true) } }
        }
    }
    private(set) var notifications: [NotificationItem] = []
    private(set) var notificationsStatus = ""
    private(set) var notificationBadge = 0
    private var notificationsPage = 1
    private var hasMoreNotifications = true
    private var isLoadingNotifications = false

    func loadNotifications(reset: Bool) async {
        guard !isLoadingNotifications else { return }
        isLoadingNotifications = true
        defer { isLoadingNotifications = false }

        if reset {
            notificationsPage = 1
            hasMoreNotifications = true
        }
        notificationsStatus = ""

        do {
            let json = try await api.getNotifications(
                notificationType: notificationType.rawValue,
                page: UInt32(notificationsPage)
            )
            let parsed = NotificationItem.parseList(fromJSONString: json)
            if reset {
                notifications = parsed
            } else {
                let known = Set(notifications.map(\.id))
                notifications += parsed.filter { !known.contains($0.id) }
            }
            hasMoreNotifications = !parsed.isEmpty
            if reset { notificationsPage = 2 } else { notificationsPage += 1 }
            if notifications.isEmpty { notificationsStatus = "暂无通知" }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { notificationsStatus = "加载失败:\(Self.friendlyError(message))" }
        } catch {
            notificationsStatus = "加载失败:\(error.localizedDescription)"
        }
    }

    func loadMoreNotificationsIfNeeded(current item: NotificationItem) async {
        guard item.id == notifications.last?.id, hasMoreNotifications, !isLoadingNotifications else { return }
        await loadNotifications(reset: false)
    }

    /// 角标:checkCount 的 data 可能是数字也可能是含 total 的对象,失败静默归零。
    func refreshNotificationBadge() async {
        guard isLoggedIn else {
            notificationBadge = 0
            return
        }
        do {
            notificationBadge = Self.parseBadge(fromJSONString: try await api.getNotificationCount())
        } catch {
            notificationBadge = 0
        }
    }

    private static func parseBadge(fromJSONString json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        // count 接口:{"data":{"atme":1,"commentme":0,...,"dateline":<时间戳>}}
        // 已知计数键求和;dateline 是时间戳,绝不能计入
        let counters = ["atme", "atcommentme", "commentme", "feedlike", "notification", "message"]
        guard let payload = root["data"] as? [String: Any] else { return 0 }
        let total = counters.reduce(0) { sum, key in
            sum + ((payload[key] as? NSNumber)?.intValue ?? 0)
        }
        return min(total, 99)
    }

    // MARK: 发布动态

    var showComposer = false
    var publishDraft = ""
    private(set) var isPublishingFeed = false
    private(set) var publishStatus: String?

    func clearPublishStatus() {
        publishStatus = nil
    }

    /// 发布文字动态(图片上传链路未接,pic 传 nil;成功后回首页刷新)。
    func publishFeed() async {
        let message = publishDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLoggedIn, !message.isEmpty, !isPublishingFeed else { return }
        isPublishingFeed = true
        defer { isPublishingFeed = false }
        do {
            _ = try await api.createFeed(message: message, pic: nil, postToken: nil)
            publishDraft = ""
            publishStatus = nil
            showComposer = false
            if case .feed(let category) = entry, category != .home {
                entry = .feed(.home)
            } else {
                await refresh()
            }
        } catch let error as CoolapkError {
            if case .Failed(let failure) = error { publishStatus = Self.friendlyError(failure) }
        } catch {
            publishStatus = error.localizedDescription
        }
    }

    // MARK: 用户主页(搜索用户点入)

    var selectedUserUID: String? {
        didSet {
            guard selectedUserUID != oldValue else { return }
            userSpace = nil
            userSpaceError = ""
            userFeeds = []
        }
    }
    private(set) var userSpace: UserSpace?
    private(set) var userSpaceError = ""
    private(set) var userFeeds: [FeedItem] = []
    private var userPage = 1
    private var isLoadingUserFeeds = false

    /// 打开用户主页:右列一次一种面板,先清掉话题/动态/应用栈。
    func selectUser(uid: String) async {
        guard selectedUserUID != uid else { return }
        selectedUserUID = uid
        selectedTopicTag = nil
        topicFeeds = []
        selectedFeedID = nil
        detail = nil
        detailError = nil
        replies = []
        selectedApkPackage = nil
        apkDetail = nil
        apkDetailError = ""
        await loadUserSpace()
        await loadUserFeeds(reset: true)
    }

    func closeUserProfile() {
        selectedUserUID = nil
        userSpace = nil
        userSpaceError = ""
        userFeeds = []
    }

    private func loadUserSpace() async {
        guard let uid = selectedUserUID else { return }
        do {
            let json = try await api.getUserSpace(uid: uid)
            guard selectedUserUID == uid else { return }
            userSpace = UserSpace.parse(fromJSONString: json)
        } catch let error as CoolapkError {
            guard selectedUserUID == uid else { return }
            if case .Failed(let message) = error { userSpaceError = Self.friendlyError(message) }
        } catch {
            guard selectedUserUID == uid else { return }
            userSpaceError = error.localizedDescription
        }
    }

    func loadUserFeeds(reset: Bool) async {
        guard let uid = selectedUserUID, !isLoadingUserFeeds else { return }
        isLoadingUserFeeds = true
        defer { isLoadingUserFeeds = false }
        if reset { userPage = 1 }
        do {
            let json = try await api.getUserFeeds(uid: uid, page: UInt32(userPage), feedType: "feed")
            guard selectedUserUID == uid else { return }
            let parsed = CoolapkJSON.entities(fromJSONString: json)
                .compactMap(FeedItem.init(entity:))
            if reset {
                userFeeds = parsed
            } else {
                let known = Set(userFeeds.map(\.id))
                userFeeds += parsed.filter { !known.contains($0.id) }
            }
            if reset { userPage = 2 } else { userPage += 1 }
        } catch {
            // 用户动态拉取失败静默:列表空态兜底
        }
    }

    // MARK: 私信

    private(set) var chatUsers: [ChatUser] = []
    private(set) var chatListStatus = ""
    var selectedChat: ChatUser? {
        didSet {
            guard selectedChat != nil, selectedChat != oldValue else { return }
            chatMessages = []
            hasMoreChatHistory = true
            Task { await loadChatHistory(reset: true) }
        }
    }
    private(set) var chatMessages: [ChatMessage] = []
    private(set) var isLoadingChat = false
    var chatDraft = ""
    private(set) var chatSendStatus: String?
    private var chatsPage = 1
    private var hasMoreChats = true
    private var isLoadingChats = false
    private var chatHistoryPage = 1
    private var hasMoreChatHistory = true

    func loadChats(reset: Bool) async {
        guard !isLoadingChats else { return }
        isLoadingChats = true
        defer { isLoadingChats = false }

        if reset {
            chatsPage = 1
            hasMoreChats = true
        }
        chatListStatus = ""

        do {
            let json = try await api.getRecentChatUsers(page: UInt32(chatsPage))
            let parsed = ChatUser.parseList(fromJSONString: json)
            if reset {
                chatUsers = parsed
            } else {
                let known = Set(chatUsers.map(\.id))
                chatUsers += parsed.filter { !known.contains($0.id) }
            }
            hasMoreChats = !parsed.isEmpty
            if reset { chatsPage = 2 } else { chatsPage += 1 }
            if chatUsers.isEmpty { chatListStatus = "暂无私信" }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { chatListStatus = "加载失败:\(Self.friendlyError(message))" }
        } catch {
            chatListStatus = "加载失败:\(error.localizedDescription)"
        }
    }

    func loadChatHistory(reset: Bool) async {
        guard let chat = selectedChat, !isLoadingChat else { return }
        isLoadingChat = true
        defer { isLoadingChat = false }

        if reset {
            chatHistoryPage = 1
            hasMoreChatHistory = true
        }

        do {
            // ukey 为空时直接用 uid 试
            let ukey = chat.ukey.isEmpty ? chat.uid : chat.ukey
            let json = try await api.listChatHistory(ukey: ukey, page: UInt32(chatHistoryPage))
            let parsed = ChatMessage.parseList(fromJSONString: json)
            if reset {
                chatMessages = parsed
            } else {
                let known = Set(chatMessages.map(\.id))
                chatMessages += parsed.filter { !known.contains($0.id) }
            }
            hasMoreChatHistory = !parsed.isEmpty
            if reset { chatHistoryPage = 2 } else { chatHistoryPage += 1 }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { chatListStatus = "聊天记录加载失败:\(Self.friendlyError(message))" }
        } catch {
            chatListStatus = "聊天记录加载失败:\(error.localizedDescription)"
        }
    }

    func sendChatMessage() async {
        guard isLoggedIn, let chat = selectedChat else { return }
        let message = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        chatSendStatus = nil
        do {
            _ = try await api.sendPrivateMessage(uid: chat.uid, message: message)
            chatDraft = ""
            await loadChatHistory(reset: true)
        } catch let error as CoolapkError {
            if case .Failed(let failure) = error { chatSendStatus = Self.friendlyError(failure) }
        } catch {
            chatSendStatus = error.localizedDescription
        }
    }

    // MARK: 互动(点赞/收藏/回复)

    var replyDraft = ""
    private(set) var likedFeedIDs: Set<String> = []
    private(set) var favoritedFeedIDs: Set<String> = []
    private(set) var interactionStatus: String?

    /// 点赞/取消点赞:先乐观更新集合,失败回滚并给出错误提示。
    func toggleLike() async {
        guard isLoggedIn, let feedID = selectedFeedID else { return }
        let wasLiked = likedFeedIDs.contains(feedID)
        if wasLiked {
            likedFeedIDs.remove(feedID)
        } else {
            likedFeedIDs.insert(feedID)
        }
        do {
            if wasLiked {
                _ = try await api.unlikeFeed(feedId: feedID)
            } else {
                _ = try await api.likeFeed(feedId: feedID)
            }
            interactionStatus = nil
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { interactionStatus = Self.friendlyError(message) }
            if wasLiked { likedFeedIDs.insert(feedID) } else { likedFeedIDs.remove(feedID) }
        } catch {
            interactionStatus = error.localizedDescription
            if wasLiked { likedFeedIDs.insert(feedID) } else { likedFeedIDs.remove(feedID) }
        }
    }

    /// 收藏。facade 暂无取消收藏接口:已收藏时不再调用,直接视为成功态。
    func toggleFavorite() async {
        guard isLoggedIn, let feedID = selectedFeedID else { return }
        guard !favoritedFeedIDs.contains(feedID) else { return }
        favoritedFeedIDs.insert(feedID)
        do {
            _ = try await api.favoriteFeed(feedId: feedID)
            interactionStatus = nil
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { interactionStatus = Self.friendlyError(message) }
            favoritedFeedIDs.remove(feedID)
        } catch {
            interactionStatus = error.localizedDescription
            favoritedFeedIDs.remove(feedID)
        }
    }

    /// 发表评论(rid 固定 nil,评论楼中楼暂未接)。
    func sendReply() async {
        guard isLoggedIn, let feedID = selectedFeedID else { return }
        let message = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        do {
            _ = try await api.replyFeed(feedId: feedID, message: message, rid: nil)
            replyDraft = ""
            interactionStatus = nil
            await loadReplies(reset: true)
        } catch let error as CoolapkError {
            if case .Failed(let failure) = error { interactionStatus = Self.friendlyError(failure) }
        } catch {
            interactionStatus = error.localizedDescription
        }
    }

    // MARK: 个人列表(收藏/关注/历史)

    private(set) var personalKind: PersonalListKind?
    private(set) var personalFeeds: [FeedItem] = []
    private(set) var personalStatus = ""
    private var personalPage = 1
    private var hasMorePersonalFeeds = true
    private var isLoadingPersonal = false

    /// 切换个人列表类型:类型变化(或列表为空)时重新拉取,避免显示上一个列表的数据。
    /// 历史实体不是动态(recentHistory,由 HistoryListView 自管),不走 loadPersonalList。
    func setPersonalKind(_ kind: PersonalListKind) {
        guard personalKind != kind || personalFeeds.isEmpty else { return }
        personalKind = kind
        personalFeeds = []
        guard kind != .history else { return }
        Task { await loadPersonalList(reset: true) }
    }

    func loadPersonalList(reset: Bool) async {
        guard !isLoadingPersonal, let kind = personalKind else { return }
        isLoadingPersonal = true
        defer { isLoadingPersonal = false }

        if reset {
            personalPage = 1
            hasMorePersonalFeeds = true
        }
        personalStatus = ""

        do {
            let json: String
            switch kind {
            case .favorites:
                guard let uid = currentUID, !uid.isEmpty else {
                    personalStatus = "请先登录"
                    return
                }
                json = try await api.getFavoriteList(uid: uid, page: UInt32(personalPage))
            case .following:
                json = try await api.getFollowingFeeds(page: UInt32(personalPage))
            case .history:
                json = try await api.getRecentHistory(page: UInt32(personalPage))
            }

            let parsed = CoolapkJSON.entities(fromJSONString: json)
                .compactMap(FeedItem.init(entity:))
            if reset {
                personalFeeds = parsed
            } else {
                let known = Set(personalFeeds.map(\.id))
                personalFeeds += parsed.filter { !known.contains($0.id) }
            }
            hasMorePersonalFeeds = !parsed.isEmpty
            if reset { personalPage = 2 } else { personalPage += 1 }
            if personalFeeds.isEmpty { personalStatus = "暂无内容" }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { personalStatus = "加载失败:\(Self.friendlyError(message))" }
        } catch {
            personalStatus = "加载失败:\(error.localizedDescription)"
        }
    }

    func loadMorePersonalIfNeeded(current feed: FeedItem) async {
        guard feed.id == personalFeeds.last?.id, hasMorePersonalFeeds, !isLoadingPersonal else { return }
        await loadPersonalList(reset: false)
    }

    // MARK: 应用详情(搜索 APK 结果点入)

    var selectedApkPackage: String? {
        didSet {
            guard selectedApkPackage != oldValue else { return }
            apkDetail = nil
            apkDetailError = ""
        }
    }
    private(set) var apkDetail: ApkDetail?
    private(set) var apkDetailError = ""

    /// 打开应用详情:同时清掉话题/动态栈(右列一次只显示一种面板)。
    func selectApk(packageName: String) async {
        guard selectedApkPackage != packageName else { return }
        selectedApkPackage = packageName
        selectedTopicTag = nil
        topicFeeds = []
        selectedFeedID = nil
        detail = nil
        detailError = nil
        replies = []
        selectedUserUID = nil
        userSpace = nil
        userFeeds = []
        await loadApkDetail()
    }

    func closeApkDetail() {
        selectedApkPackage = nil
        apkDetail = nil
        apkDetailError = ""
    }

    private func loadApkDetail() async {
        guard let packageName = selectedApkPackage else { return }
        do {
            let json = try await api.getAppDetail(packageName: packageName)
            guard selectedApkPackage == packageName else { return }
            apkDetail = ApkDetail.parse(fromJSONString: json)
            if apkDetail == nil { apkDetailError = "详情解析失败" }
        } catch let error as CoolapkError {
            guard selectedApkPackage == packageName else { return }
            if case .Failed(let message) = error { apkDetailError = Self.friendlyError(message) }
        } catch {
            guard selectedApkPackage == packageName else { return }
            apkDetailError = error.localizedDescription
        }
    }

    /// 下载当前应用详情对应的 APK(解析官方直链入下载队列)。
    func downloadSelectedApk() async {
        guard let packageName = selectedApkPackage else { return }
        await startDownload(packageName: packageName)
    }

    // MARK: APK 下载

    let downloads = DownloadManager.shared
    var newPackageName = ""

    /// 包名 → Rust 侧解析 aid + 最新版本 → 组官方 v6/apk/download 地址入下载队列。
    func resolveAndDownload() async {
        let packageName = newPackageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !packageName.isEmpty else { return }
        await startDownload(packageName: packageName)
    }

    private func startDownload(packageName: String) async {
        do {
            let json = try await api.resolveLatestApkDownload(packageName: packageName)
            guard let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = CoolapkJSON.string(root["url"]),
                  let url = URL(string: urlString)
            else {
                downloads.statusText = "解析结果异常"
                return
            }
            let versionName = CoolapkJSON.string(root["versionName"]) ?? ""
            downloads.start(url: url, packageName: packageName, versionName: versionName)
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { downloads.statusText = "解析失败:\(Self.friendlyError(message))" }
        } catch {
            downloads.statusText = "解析失败:\(error.localizedDescription)"
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
