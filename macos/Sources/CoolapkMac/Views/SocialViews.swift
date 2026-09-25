import SwiftUI
import CoolapkCoreSwift

// 酷安绿(本文件内独立命名,避免与 ContentView 侧的定义重名冲突)。
extension Color {
    static let socialGreen = Color(red: 0, green: 0.71, blue: 0.27)
}

// MARK: - 登录兜底

/// 通知/私信/个人列表在未登录时的统一占位,引导弹出登录窗口。
struct LoginRequiredView: View {
    @Bindable var model: AppModel
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label("请先登录", systemImage: "lock")
        } description: {
            Text("登录后才能查看\(title)")
        } actions: {
            Button("登录") { model.showLoginSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(.socialGreen)
        }
    }
}

// MARK: - 通知

struct NotificationsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.isLoggedIn {
                VStack(spacing: 0) {
                    Picker("通知类型", selection: $model.notificationType) {
                        ForEach(NotificationType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    if model.notifications.isEmpty {
                        // 撑满剩余空间:标签条钉在顶部,空态在余下区域垂直居中
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        notificationList
                    }
                }
            } else {
                LoginRequiredView(model: model, title: "通知", systemImage: "bell")
            }
        }
        .navigationTitle("通知")
        .refreshable {
            await model.loadNotifications(reset: true)
            await model.refreshNotificationBadge()
        }
        // 绑定登录态:登录成功后自动补一次首载。
        .task(id: model.isLoggedIn) {
            guard model.isLoggedIn, model.notifications.isEmpty else { return }
            await model.loadNotifications(reset: true)
        }
    }

    private var notificationList: some View {
        List {
            ForEach(model.notifications) { item in
                NotificationRowView(item: item, model: model)
                    .onAppear {
                        // 触达末条时翻页:hasMore 判定收在 Core 层,避免无意义的追尾请求。
                        Task { await model.loadMoreNotificationsIfNeeded(current: item) }
                    }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.notificationsStatus.isEmpty {
                Text(model.notificationsStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.notificationsStatus.isEmpty || model.notificationsStatus == "暂无通知" {
            ContentUnavailableView("暂无通知", systemImage: "bell", description: Text("下拉刷新试试"))
        } else {
            ContentUnavailableView("暂无通知", systemImage: "bell", description: Text(model.notificationsStatus))
        }
    }
}

private struct NotificationRowView: View {
    let item: NotificationItem
    let model: AppModel

    var body: some View {
        Button {
            openTarget()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(url: item.avatarURL, size: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.username.isEmpty ? "酷友" : item.username)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        // 系统通知(如账号安全提醒)可能缺 dateline,1970 显示"56年前"
                        if item.hasValidDateline {
                            Text(item.dateline, format: .coolapkRelative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Text(item.note)
                        .font(.callout)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 点赞/@我 通知带动态目标 → 跳站内详情;其余(如账号安全"点击查看")开 note 里的外链。
    private func openTarget() {
        if let feedID = item.feedID {
            Task { await model.select(feedID: feedID) }
        } else if let url = item.actionURL {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 私信

struct MessagesView: View {
    @Bindable var model: AppModel
    @State private var showConversation = false

    var body: some View {
        Group {
            if model.isLoggedIn {
                if showConversation, model.selectedChat != nil {
                    ConversationView(model: model) {
                        showConversation = false
                        model.selectedChat = nil
                    }
                } else {
                    chatList
                }
            } else {
                LoginRequiredView(model: model, title: "私信", systemImage: "message")
            }
        }
        .navigationTitle("消息")
        .refreshable {
            if showConversation, model.selectedChat != nil {
                await model.loadChatHistory(reset: true)
            } else {
                await model.loadChats(reset: true)
            }
        }
        .task(id: model.isLoggedIn) {
            guard model.isLoggedIn, model.chatUsers.isEmpty, !showConversation else { return }
            await model.loadChats(reset: true)
        }
    }

    private var chatList: some View {
        Group {
            if model.chatUsers.isEmpty {
                emptyState
            } else {
                List(model.chatUsers) { chat in
                    Button {
                        // selectedChat 的 didSet 会自动加载历史消息。
                        model.selectedChat = chat
                        showConversation = true
                    } label: {
                        ChatUserRowView(chat: chat)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.loadChats(reset: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.chatListStatus.isEmpty || model.chatListStatus == "暂无私信" {
            ContentUnavailableView("暂无私信", systemImage: "message", description: Text("下拉刷新试试"))
        } else {
            ContentUnavailableView("暂无私信", systemImage: "message", description: Text(model.chatListStatus))
        }
    }
}

private struct ChatUserRowView: View {
    let chat: ChatUser

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: chat.avatarURL, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.username.isEmpty ? "酷友" : chat.username)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if chat.hasValidDateline {
                        Text(chat.dateline, format: .coolapkRelative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Text(chat.lastMessage.isEmpty ? "(无内容)" : chat.lastMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// 单条会话:消息气泡列表 + 底部输入条。
private struct ConversationView: View {
    @Bindable var model: AppModel
    let onBack: () -> Void

    // 更早消息的分页:AppModel 的 chatMessages 只承载第一页(最新一页),
    // 更早的页在视图内向前拼接,避免 Core 层把旧消息追加到列表尾部打乱顺序。
    @State private var olderMessages: [ChatMessage] = []
    @State private var olderPage = 2
    @State private var hasMoreOlder = true
    @State private var isLoadingOlder = false
    @State private var olderError = ""
    @State private var isSending = false
    /// 第一页首条消息:变化说明 Core 侧整体重载过(切换会话/发送后刷新),旧分页作废。
    @State private var firstSeen: ChatMessage?
    /// 上次向前拼接的时间:拼页后视口锚到顶部会再次触发首条 onAppear,
    /// 1 秒冷却防止自动翻页一路加载完整段历史。
    @State private var lastPrependAt = Date.distantPast
    private let api = CoolapkApi.shared

    private var displayMessages: [ChatMessage] {
        olderMessages + model.chatMessages
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("‹ 会话列表") { onBack() }
                    .buttonStyle(.borderless)
                if let name = model.selectedChat?.username, !name.isEmpty {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if model.chatMessages.isEmpty, model.isLoadingChat {
                ProgressView("加载消息…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.chatMessages.isEmpty {
                // 撑满剩余空间:返回条贴顶、composer 贴底,空态居中,
                // 否则整个 VStack 收缩后垂直居中,返回键和输入框悬在半空
                ContentUnavailableView(
                    "暂无消息",
                    systemImage: "bubble.left.and.bubble.right",
                    // 聊天记录加载失败(如官方小助手会话"你无法查看该私信")只落在 chatListStatus,
                    // 这里必须透出,否则失败被误读成"没有消息"
                    description: Text(
                        model.chatListStatus.isEmpty ? "发送第一条消息吧" : model.chatListStatus
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageList
            }

            Divider()
            composer
        }
        .navigationTitle(model.selectedChat?.username ?? "对话")
        .onChange(of: model.chatMessages) { _, messages in
            resetOlderPages(ifFirstPageChanged: messages.first)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    olderPagesFooter

                    ForEach(displayMessages) { message in
                        MessageBubbleView(
                            message: message,
                            isMine: message.uid == model.currentUID
                        )
                        .id(message.id)
                        .onAppear {
                            if message.id == displayMessages.first?.id {
                                Task { await loadOlderMessages(scrollAnchor: message.id, proxy: proxy) }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: model.chatMessages.count) { _, _ in
                if let last = model.chatMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = model.chatMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var olderPagesFooter: some View {
        if isLoadingOlder {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else if !olderError.isEmpty {
            // 点击重试:首条消息已出现,不会再触发 onAppear
            Button("更早的消息加载失败,点击重试") {
                olderError = ""
                Task { await loadOlderMessages(scrollAnchor: nil, proxy: nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        } else if !olderMessages.isEmpty, !hasMoreOlder {
            Text("已经到最前面了")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }

    /// 拉更早的一页:触达当前最早一条消息时触发;成功后把视口锚回首条,避免跳到底部。
    private func loadOlderMessages(scrollAnchor anchorID: String?, proxy: ScrollViewProxy?) async {
        guard let chat = model.selectedChat,
              hasMoreOlder, !isLoadingOlder,
              !model.chatMessages.isEmpty,
              Date().timeIntervalSince(lastPrependAt) > 1.0
        else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        olderError = ""

        // ukey 为空时直接用 uid 试(与 Core 层第一页的取数规则一致)
        let ukey = chat.ukey.isEmpty ? chat.uid : chat.ukey
        do {
            let json = try await api.listChatHistory(ukey: ukey, page: UInt32(olderPage))
            let parsed = ChatMessage.parseList(fromJSONString: json)
            let known = Set(displayMessages.map(\.id))
            let fresh = parsed.filter { !known.contains($0.id) }
            if fresh.isEmpty {
                hasMoreOlder = false
            } else {
                olderMessages = fresh + olderMessages
                olderPage += 1
                lastPrependAt = Date()
                if let anchorID, let proxy {
                    proxy.scrollTo(anchorID, anchor: .top)
                }
            }
        } catch {
            // 会话里静默降级:页脚提示,不打断当前浏览
            olderError = "load-failed"
        }
    }

    private func resetOlderPages(ifFirstPageChanged first: ChatMessage?) {
        guard first != firstSeen else { return }
        firstSeen = first
        olderMessages = []
        olderPage = 2
        hasMoreOlder = true
        olderError = ""
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                TextField("发消息…", text: $model.chatDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await send() }
                    }
                Button("发送") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.socialGreen)
                .disabled(model.chatDraft.isEmpty || isSending)
            }
            .padding(10)

            if let status = model.chatSendStatus, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
    }

    /// 发送期间锁按钮:回车和点击共用一条链路,防连点造成重复私信。
    private func send() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        await model.sendChatMessage()
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isMine {
                AvatarView(url: message.avatarURL, size: 30)
            }
            Text(message.message)
                .font(.callout)
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isMine ? Color.socialGreen : Color.secondary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .frame(maxWidth: 420, alignment: isMine ? .trailing : .leading)
            if isMine {
                AvatarView(url: message.avatarURL, size: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}

// MARK: - 下载

/// 下载页:游客可用,无需登录。
struct DownloadsView: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            Section("新建任务") {
                HStack(spacing: 10) {
                    TextField("应用包名,如 com.coolapk.market", text: $model.newPackageName)
                        .textFieldStyle(.roundedBorder)
                    Button("解析并下载") {
                        Task { await model.resolveAndDownload() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.socialGreen)
                    .disabled(model.newPackageName.isEmpty)
                }
                .padding(.vertical, 2)

                if !model.downloads.statusText.isEmpty {
                    Text(model.downloads.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("任务") {
                ForEach(model.downloads.tasks) { task in
                    DownloadTaskRowView(manager: model.downloads, task: task)
                }
                if model.downloads.tasks.isEmpty {
                    Text("暂无下载任务,输入应用包名后解析下载")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("下载")
    }
}

private struct DownloadTaskRowView: View {
    let manager: DownloadManager
    let task: DownloadManager.DownloadTask

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.packageName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Text(task.versionName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            progressLine

            HStack(spacing: 10) {
                actions
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var progressLine: some View {
        switch task.state {
        case .running:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(
                    value: task.totalBytes > 0
                        ? Double(task.downloadedBytes) / Double(task.totalBytes)
                        : 0
                )
                Text(
                    "\(Self.byteFormatter.string(fromByteCount: task.downloadedBytes)) / "
                        + "\(Self.byteFormatter.string(fromByteCount: task.totalBytes))"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        case .paused:
            stateLabel("已暂停")
        case .completed:
            stateLabel("已完成")
        case .failed:
            stateLabel("失败")
        }
    }

    private func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var actions: some View {
        switch task.state {
        case .running:
            iconButton("pause.circle", "暂停") { manager.pause(task.id) }
            iconButton("xmark.circle", "取消") { manager.cancel(task.id) }
        case .paused:
            iconButton("play.circle", "继续") { manager.resume(task.id) }
            iconButton("xmark.circle", "取消") { manager.cancel(task.id) }
        case .completed:
            iconButton("arrow.up.forward.app", "打开") { manager.open(task) }
            iconButton("folder", "在访达中显示") { manager.reveal(task) }
            iconButton("trash", "删除记录") { manager.removeCompletedFile(task.id) }
        case .failed:
            iconButton("trash", "删除记录") { manager.cancel(task.id) }
        }
    }

    private func iconButton(
        _ systemImage: String,
        _ help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - 个人列表(收藏/关注/历史)

struct PersonalListView: View {
    @Bindable var model: AppModel

    private var title: String {
        switch model.personalKind {
        case .favorites: "收藏"
        case .following: "我关注的"
        case .history: "历史"
        case nil: "个人内容"
        }
    }

    var body: some View {
        // 历史实体是 recentHistory(target 为用户/话题/数码/动态),不是动态,
        // FeedItem 解析不出头像/时间/类型,走专属列表
        if model.personalKind == .history {
            HistoryListView(model: model)
        } else {
            feedList
        }
    }

    private var feedList: some View {
        Group {
            if model.isLoggedIn {
                if model.personalFeeds.isEmpty {
                    emptyState
                } else {
                    List(model.personalFeeds) { feed in
                        Button {
                            Task { await model.select(feedID: feed.id) }
                        } label: {
                            FeedRowView(feed: feed)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // 触达末条翻页:hasMore/防抖判定收在 Core 层
                            Task { await model.loadMorePersonalIfNeeded(current: feed) }
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                LoginRequiredView(model: model, title: title, systemImage: "person")
            }
        }
        .navigationTitle(title)
        .refreshable { await model.loadPersonalList(reset: true) }
        .task(id: model.isLoggedIn) {
            guard model.isLoggedIn, model.personalFeeds.isEmpty else { return }
            await model.loadPersonalList(reset: true)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.personalStatus.isEmpty || model.personalStatus == "暂无内容" {
            ContentUnavailableView(title, systemImage: "person", description: Text("下拉刷新试试"))
        } else {
            ContentUnavailableView(title, systemImage: "person", description: Text(model.personalStatus))
        }
    }
}

/// 浏览历史:target 是用户/话题/数码/动态,行内展示 logo 圆头像 + 类型/计数 + 时间,
/// 可点击跳转(动态→详情,话题→话题面板,用户→用户主页)。
private struct HistoryListView: View {
    @Bindable var model: AppModel
    @State private var items: [HistoryItem] = []
    @State private var status = ""
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    private let api = CoolapkApi.shared

    var body: some View {
        Group {
            if model.isLoggedIn {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(items) { item in
                            HistoryRowView(item: item, model: model)
                                .onAppear {
                                    if item.id == items.last?.id {
                                        Task { await load(reset: false) }
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                LoginRequiredView(model: model, title: "历史", systemImage: "person")
            }
        }
        .navigationTitle("历史")
        .refreshable { await load(reset: true) }
        .task(id: model.isLoggedIn) {
            guard model.isLoggedIn, items.isEmpty else { return }
            await load(reset: true)
        }
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if reset {
            page = 1
            hasMore = true
        }
        status = ""

        do {
            let json = try await api.getRecentHistory(page: UInt32(page))
            let parsed = HistoryItem.parseList(fromJSONString: json)
            if reset {
                items = parsed
            } else {
                let known = Set(items.map(\.id))
                items += parsed.filter { !known.contains($0.id) }
            }
            hasMore = !parsed.isEmpty
            page = reset ? 2 : page + 1
            if items.isEmpty { status = "暂无浏览记录" }
        } catch let error as CoolapkError {
            if case .Failed(let message) = error { status = "加载失败:\(message)" }
        } catch {
            status = "加载失败:\(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if status.isEmpty || status == "暂无浏览记录" {
            ContentUnavailableView("历史", systemImage: "person", description: Text("下拉刷新试试"))
        } else {
            ContentUnavailableView("历史", systemImage: "person", description: Text(status))
        }
    }
}

private struct HistoryRowView: View {
    let item: HistoryItem
    let model: AppModel

    var body: some View {
        Button {
            openTarget()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if item.hasValidTime {
                            Text(item.lastUpdate, format: .coolapkRelative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// logo 缺失时的体面占位:标题首字圆形徽标(酷安绿),不露灰块。
    @ViewBuilder
    private var avatar: some View {
        if let url = item.logoURL {
            AvatarView(url: url, size: 40)
        } else {
            Text(String(item.title.prefix(1)))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.socialGreen.opacity(0.8), in: Circle())
        }
    }

    private func openTarget() {
        if let feedID = item.feedTarget {
            Task { await model.select(feedID: feedID) }
        } else if let tag = item.topicTarget {
            Task { await model.openTopic(tag: tag) }
        } else if let uid = item.userTarget {
            Task { await model.selectUser(uid: uid) }
        }
    }
}
