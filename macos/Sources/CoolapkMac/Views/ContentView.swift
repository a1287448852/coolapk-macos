import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } content: {
            FeedListView(model: model)
                .navigationSplitViewColumnWidth(min: 380, ideal: 460, max: 560)
        } detail: {
            FeedDetailView(model: model)
        }
        .environment(model)
    }
}

// MARK: - 侧栏

struct SidebarView: View {
    let model: AppModel

    var body: some View {
        List(selection: Binding(
            get: { model.category },
            set: { model.category = $0 ?? model.category }
        )) {
            Section("信息流") {
                ForEach(FeedCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.systemImage)
                        .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CoolapkMac")
    }
}

// MARK: - 信息流列表

struct FeedListView: View {
    @Bindable var model: AppModel
    @State private var showLogin = false

    var body: some View {
        List(selection: Binding(
            get: { model.selectedFeedID },
            set: { id in
                guard let id else { return }
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
        .navigationTitle(model.isSearchActive ? "搜索结果" : model.category.rawValue)

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
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .disabled(model.isSearchActive)
            }
            ToolbarItem(placement: .primaryAction) {
                if let profile = model.userProfile {
                    Menu {
                        Button("登出", role: .destructive) {
                            Task { await model.logout() }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            AvatarView(url: profile.avatarURL, size: 22)
                            Text(profile.username)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Label("登录", systemImage: "person.crop.circle")
                    }
                }
            }
        }
        .refreshable { await model.refresh() }
        .searchable(
            text: $model.searchQuery,
            placement: .toolbar,
            prompt: "搜索酷安"
        )
        .onSubmit(of: .search) {
            Task { await model.runSearch() }
        }
        .autocorrectionDisabled()
        .task {
            await model.restoreSession()
            if model.feeds.isEmpty { await model.loadFeeds(reset: true) }
            // 调试:COOLAPKMAC_AUTO_LOGIN=1 启动时自动弹出登录窗口
            if ProcessInfo.processInfo.environment["COOLAPKMAC_AUTO_LOGIN"] == "1" {
                showLogin = true
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView { cookie in
                Task { await model.completeLogin(cookie: cookie) }
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        ForEach(model.feeds) { feed in
            FeedRowView(feed: feed)
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
                    ForEach(section.items) { feed in
                        FeedRowView(feed: feed)
                            .tag(feed.id)
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

// MARK: - 列表行

struct FeedRowView: View {
    let feed: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: feed.avatarURL, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if !feed.username.isEmpty {
                        Text(feed.username)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(feed.dateline, format: .coolapkRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if !feed.displayText.isEmpty {
                    Text(feed.displayText)
                        .font(.subheadline)
                        .lineLimit(3)
                }

                if !feed.picURLs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(feed.picURLs.prefix(3), id: \.absoluteString) { url in
                            RemoteImage(url: url)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                HStack(spacing: 14) {
                    StatLabel(systemImage: "hand.thumbsup", count: feed.likeCount)
                    StatLabel(systemImage: "bubble.right", count: feed.replyCount)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 详情

struct FeedDetailView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let detail = model.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            AvatarView(url: detail.avatarURL, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.username)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    if !detail.deviceTitle.isEmpty {
                                        Text(detail.deviceTitle)
                                    }
                                    Text(detail.dateline, format: .coolapkRelative)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        Text(detail.attributedMessage)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !detail.picURLs.isEmpty {
                            PicGrid(urls: detail.picURLs)
                        }

                        HStack(spacing: 20) {
                            StatLabel(systemImage: "hand.thumbsup", count: detail.likeCount)
                            StatLabel(systemImage: "bubble.right", count: detail.replyCount)
                            StatLabel(systemImage: "star", count: detail.favCount)
                            StatLabel(systemImage: "arrowshape.turn.up.right", count: detail.shareCount)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)

                        Divider()

                        ReplyListView(model: model)
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else if model.isLoadingDetail {
                ProgressView("加载详情…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.selectedFeedID != nil {
                // 详情可能因服务端风控(403 验证码)失败:错误提示 + 照常展示评论
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let error = model.detailError {
                            Label(error, systemImage: "exclamationmark.shield")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        }
                        ReplyListView(model: model)
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "选择一条动态",
                    systemImage: "text.bubble",
                    description: Text("从左侧列表选择一条动态查看详情和评论")
                )
            }
        }
        .navigationTitle("详情")
    }
}

struct ReplyListView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论 \(model.replies.count)")
                .font(.headline)

            ForEach(model.replies) { reply in
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(url: reply.avatarURL, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(reply.username)
                                .font(.callout.weight(.medium))
                            Spacer(minLength: 8)
                            Text(reply.dateline, format: .coolapkRelative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(reply.message)
                            .font(.callout)
                            .textSelection(.enabled)
                        StatLabel(systemImage: "hand.thumbsup", count: reply.likeCount)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                Divider()
            }

            if model.replies.isEmpty && model.isLoadingDetail {
                ProgressView()
            }

            if !model.replies.isEmpty {
                Button {
                    Task { await model.loadReplies(reset: false) }
                } label: {
                    if model.isLoadingMoreReplies {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("加载更多评论")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingMoreReplies)
            }
        }
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
    }

    /// 酷安图片 CDN 有反爬:需要浏览器 UA + 官方 Referer,直连 URLSession 即可。
    private func load() async {
        guard let url else { return }
        if let cached = CDNImageCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        do {
            let (data, response) = try await CDNImageCache.session.data(for: CDNImageCache.request(for: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let decoded = NSImage(data: data)
            else { return }
            CDNImageCache.shared.setObject(decoded, forKey: url as NSURL)
            image = decoded
        } catch {
            // 静默:占位图兜底,避免列表被单图失败刷屏
        }
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
}

struct PicGrid: View {
    let urls: [URL]
    private let maxDisplay = 9

    var body: some View {
        let shown = urls.prefix(maxDisplay)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(shown, id: \.absoluteString) { url in
                RemoteImage(url: url)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 0)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxHeight: 220)
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
