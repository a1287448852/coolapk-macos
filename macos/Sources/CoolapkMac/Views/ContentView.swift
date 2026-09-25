import SwiftUI

/// 酷安品牌绿:全 App 统一使用。
extension Color {
    static let coolapkGreen = Color(red: 0, green: 0.71, blue: 0.27)
}

// MARK: - 根视图:三栏骨架

struct ContentView: View {
    @State private var model = AppModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 380, ideal: 460, max: 560)
        } detail: {
            detailColumn
        }
        .environment(model)
        .overlay {
            // 全窗口图片查看器:所有列表/详情的图片点击都汇聚到这里
            if let payload = model.imageViewer {
                ImageViewerOverlay(payload: payload, model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.imageViewer != nil)
    }

    /// 中列:按侧栏入口路由(社交/我的页由 SocialViews.swift 提供)。
    @ViewBuilder
    private var contentColumn: some View {
        switch model.entry {
        case .feed:
            FeedListView(model: model)
        case .notifications:
            NotificationsView(model: model)
        case .messages:
            MessagesView(model: model)
        case .favorites:
            PersonalListView(model: model)
        case .following:
            PersonalListView(model: model)
        case .history:
            PersonalListView(model: model)
        case .downloads:
            DownloadsView(model: model)
        }
    }

    /// 右列:话题面板 → 详情 → 应用面板 → 用户主页 → 默认热榜挂件面板。
    /// 不限定 entry == .feed:通知/个人列表里点的动态/话题/用户也要能在右列打开。
    /// 面板跨入口保留(Mail 式);退出搜索时由 clearSearch 统一清栈。
    @ViewBuilder
    private var detailColumn: some View {
        if model.selectedTopicTag != nil {
            TopicPanelView(model: model)
        } else if model.selectedFeedID != nil {
            FeedDetailView(model: model)
        } else if model.selectedApkPackage != nil {
            ApkDetailPanelView(model: model)
        } else if model.selectedUserUID != nil {
            UserPanelView(model: model)
        } else {
            HotPanel(model: model)
        }
    }
}

// MARK: - 侧栏

struct SidebarView: View {
    let model: AppModel

    /// 社区分区展示顺序:内容流在前,榜单在后(与网页版一致)。
    private static let feedCategories: [FeedCategory] = [
        .home, .headline, .hot, .digest, .picture, .latest, .month, .favorite, .reply
    ]

    var body: some View {
        List(selection: Binding(
            get: { model.entry },
            set: { newValue in
                // 任何侧栏点击都先退出搜索态:否则中栏停留在搜索结果,
                // 看起来像"点了首页却切不过去"
                if model.isSearchActive { model.clearSearch() }
                model.entry = newValue ?? model.entry
            }
        )) {
            Section("社区") {
                ForEach(Self.feedCategories) { category in
                    Label(category.rawValue, systemImage: category.systemImage)
                        .tag(SidebarEntry.feed(category))
                }
            }

            Section("社交") {
                if model.notificationBadge > 0 {
                    Label("通知", systemImage: "bell")
                        .badge(model.notificationBadge)
                        .tag(SidebarEntry.notifications)
                } else {
                    Label("通知", systemImage: "bell")
                        .tag(SidebarEntry.notifications)
                }
                Label("消息", systemImage: "envelope")
                    .tag(SidebarEntry.messages)
            }

            Section("我的") {
                Label("收藏", systemImage: "star")
                    .tag(SidebarEntry.favorites)
                Label("我关注的", systemImage: "person.2")
                    .tag(SidebarEntry.following)
                Label("历史", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarEntry.history)
                Label("下载", systemImage: "arrow.down.circle")
                    .tag(SidebarEntry.downloads)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CoolapkMac")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            accountFooter
        }
    }

    /// 列表底部登录态一行:已登录显示用户名(点击展开登出);游客整行可点,拉起登录窗。
    @ViewBuilder
    private var accountFooter: some View {
        if let profile = model.userProfile {
            Menu {
                Button("登出", role: .destructive) {
                    Task { await model.logout() }
                }
            } label: {
                Label {
                    Text("已登录:\(profile.username)")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.coolapkGreen)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        } else {
            Button {
                model.showLoginSheet = true
            } label: {
                Label("游客模式 · 点击登录", systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

// MARK: - 信息流列表

struct FeedListView: View {
    @Bindable var model: AppModel

    private var currentTitle: String {
        model.isSearchActive ? "搜索结果" : model.category.rawValue
    }

    var body: some View {
        List(selection: Binding(
            get: { model.selectedFeedID },
            set: { id in
                // 搜索结果行的隐式选择值是 "topic_xxx" 这类前缀 id,
                // 不能当 feedID 用;搜索行一律走 SearchResultRow 自己的按钮路由
                guard let id, !model.isSearchActive else { return }
                Task { await model.select(feedID: id) }
            }
        )) {
            if model.isSearchActive {
                searchContent
            } else {
                feedContent
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top, spacing: 0) {
            // 站内搜索条:macOS 26 工具栏 TextField 的玻璃透镜尺寸失控(巨圆 bug),
            // 因此放列内而不是工具栏
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索应用、动态、用户、话题", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await model.runSearch() }
                    }
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                        model.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.45), in: Capsule())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .overlay {
            if !model.isSearchActive && model.feeds.isEmpty {
                ContentUnavailableView(
                    model.category.rawValue,
                    systemImage: "flame",
                    description: Text(model.statusText.isEmpty ? "下拉刷新试试" : model.statusText)
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.statusText.isEmpty && !model.feeds.isEmpty && !model.isSearchActive {
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
        }
        .navigationTitle(currentTitle)
        .toolbar {
            if model.isSearchActive {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.clearSearch()
                    } label: {
                        Label("取消搜索", systemImage: "xmark.circle")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                publishButton
            }
            ToolbarItem(placement: .primaryAction) {
                notificationButton
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.entry = .messages
                } label: {
                    Label("消息", systemImage: "envelope")
                }
                .help("消息")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .disabled(model.isSearchActive)
            }
            // 账号菜单已移至侧栏底部登录态行(工具栏 Menu 的玻璃背景
            // 在 macOS 26 上尺寸失控,会渲染成巨型液态玻璃圆)
        }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $model.showLoginSheet) {
            LoginView(model: model)
        }
        .sheet(isPresented: $model.showComposer) {
            ComposerView(model: model)
        }
        .task {
            await model.restoreSession()
            if model.isLoggedIn {
                await model.refreshNotificationBadge()
            }
            if model.feeds.isEmpty { await model.loadFeeds(reset: true) }
            // 调试:COOLAPKMAC_AUTO_LOGIN=1 启动时自动弹出登录窗口
            if ProcessInfo.processInfo.environment["COOLAPKMAC_AUTO_LOGIN"] == "1" {
                model.showLoginSheet = true
            }
        }
        .sheet(isPresented: $model.showLoginSheet) {
            LoginView(model: model)
        }
    }

    /// 绿色"发布动态":未登录引导登录,已登录打开发布弹窗。
    private var publishButton: some View {
        Button {
            if model.isLoggedIn {
                model.showComposer = true
            } else {
                model.showLoginSheet = true
            }
        } label: {
            Label("发布动态", systemImage: "pencil.and.list.clipboard")
        }
        .foregroundStyle(Color.coolapkGreen)
        .help("发布动态")
    }

    /// 通知铃铛:未读 > 0 时叠红色角标数字。
    private var notificationButton: some View {
        Button {
            model.entry = .notifications
        } label: {
            Label("通知", systemImage: "bell")
        }
        .overlay(alignment: .trailing) {
            if model.notificationBadge > 0 {
                Text("\(model.notificationBadge)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
                    .offset(x: 9, y: -9)
                    .help("未读通知 \(model.notificationBadge) 条")
            }
        }
        .help("通知")
    }

    @ViewBuilder
    private var feedContent: some View {
        ForEach(model.feeds) { feed in
            FeedCardView(feed: feed)
                .tag(feed.id)
                .onAppear {
                    Task { await model.loadMoreIfNeeded(current: feed) }
                }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if let sections = model.searchSections, !sections.isEmpty {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        SearchResultRow(item: item, label: section.title) {
                            switch item.kind {
                            case .feed:
                                if let feedID = item.feedID {
                                    Task { await model.select(feedID: feedID) }
                                }
                            case .apk:
                                if let packageName = item.apkPackage {
                                    Task { await model.selectApk(packageName: packageName) }
                                }
                            case .user:
                                if let uid = item.userUID {
                                    Task { await model.selectUser(uid: uid) }
                                }
                            default:
                                // 话题直接用标题;数码产品先匹配同名话题实体再进话题面板
                                Task {
                                    if let tag = model.topicTag(forProductTitle: item.title) {
                                        await model.openTopic(tag: tag)
                                    } else {
                                        await model.openTopic(tag: item.title)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else if model.isSearching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("搜索中…").foregroundStyle(.secondary)
            }
        } else {
            Text(model.searchStatusText.isEmpty ? "输入关键词后回车搜索" : model.searchStatusText)
                .foregroundStyle(.secondary)
        }
    }
}

/// 搜索结果行:按实体类型分型渲染(话题/应用/用户/动态),对齐原版搜索行为。
struct SearchResultRow: View {
    let item: SearchResultItem
    var label: String = "结果"
    let onOpen: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                switch item.kind {
                case .user, .apk, .topic:
                    RemoteImage(url: item.avatarURL)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: item.kind == .user ? 18 : 8))
                default:
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if item.kind == .feed {
                    HStack(spacing: 12) {
                        StatLabel(systemImage: "hand.thumbsup", count: item.likeCount)
                        StatLabel(systemImage: "bubble.right", count: item.replyCount)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.kind == .user)
    }
}

// MARK: - 组件

struct AvatarView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        RemoteImage(url: url)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

struct RemoteImage: View {
    let url: URL?
    /// 请求的 CDN 缩放宽度和解码上限:列表小格子不再解码整幅原图(4000px)。
    var pixelWidth: Int = 720
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) { await load() }
        // 装饰性图片对旁白和 AX 巡检都是噪音:整棵无障碍树会因列表大图超时
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let url else { return }
        let decoded = await CDNImageCache.image(for: url, pixelWidth: pixelWidth)
        image = decoded
    }
}

@MainActor
enum CDNImageCache {
    static let shared = NSCache<NSURL, NSImage>()

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.coolapk.com/", forHTTPHeaderField: "Referer")
        request.cachePolicy = .returnCacheDataElseLoad
        return request
    }

    /// 酷安图片 CDN 是阿里云 OSS:追加 x-oss-process 服务端缩放,
    /// 4000px 原图(数百 KB→数 MB)在列表场景 10 倍瘦身。非本 CDN 域名原样返回。
    static func sizedURL(_ url: URL, pixelWidth: Int) -> URL {
        guard url.host == "image.coolapk.com" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let process = "x-oss-process=image/resize,m_lfit,w_\(pixelWidth)"
        if let existing = components?.query, !existing.isEmpty {
            components?.query = existing + "&" + process
        } else {
            components?.query = process
        }
        return components?.url ?? url
    }

    /// 取图(带内存缓存 + 重试):按 pixelWidth 请求缩放变体,
    /// 并用 ImageIO 降采样解码,杜绝 4000 万像素原图整幅解码。
    static func image(for url: URL, pixelWidth: Int) async -> NSImage? {
        let sized = sizedURL(url, pixelWidth: pixelWidth)
        if let cached = shared.object(forKey: sized as NSURL) {
            return cached
        }
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request(for: sized))
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let decoded = downsampledImage(from: data, maxPixel: pixelWidth * 2)
                else {
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                        continue
                    }
                    return nil
                }
                shared.setObject(decoded, forKey: sized as NSURL)
                return decoded
            } catch {
                // 静默:占位图兜底,避免列表被单图失败刷屏
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                    continue
                }
                return nil
            }
        }
        return nil
    }

    /// ImageIO 降采样解码:maxPixel 限制最长边,解码内存从数百 MB 降到几 MB。
    private static func downsampledImage(from data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}

struct PicGrid: View {
    let urls: [URL]
    private let maxDisplay = 9

    var body: some View {
        let shown = urls.prefix(maxDisplay)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(shown, id: \.absoluteString) { url in
                Color.clear
                    .frame(height: 150)
                    .overlay {
                        RemoteImage(url: url)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatLabel: View {
    let systemImage: String
    let count: Int

    var body: some View {
        Label(count == 0 ? "" : "\(count)", systemImage: systemImage)
    }
}

extension FormatStyle where Self == Date.RelativeFormatStyle {
    static var coolapkRelative: Date.RelativeFormatStyle {
        var style = Date.RelativeFormatStyle()
        style.locale = Locale(identifier: "zh_CN")
        style.presentation = .named
        return style
    }
}
