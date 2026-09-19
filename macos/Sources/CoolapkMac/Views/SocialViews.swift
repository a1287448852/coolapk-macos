import SwiftUI

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
                        emptyState
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
                NotificationRowView(item: item)
                    .onAppear {
                        // 触达末条时翻页:分页状态由 Core 层管理,这里只管调用。
                        if item.id == model.notifications.last?.id {
                            Task { await model.loadNotifications(reset: false) }
                        }
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
        if model.notificationsStatus.isEmpty {
            ContentUnavailableView("暂无通知", systemImage: "bell", description: Text("下拉刷新试试"))
        } else {
            ContentUnavailableView("暂无通知", systemImage: "bell", description: Text(model.notificationsStatus))
        }
    }
}

private struct NotificationRowView: View {
    let item: NotificationItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: item.avatarURL, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.username.isEmpty ? "酷友" : item.username)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.dateline, format: .coolapkRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(item.note)
                    .font(.callout)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
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
        if model.chatListStatus.isEmpty {
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
                    Text(chat.dateline, format: .coolapkRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("‹ 会话列表") { onBack() }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if model.chatMessages.isEmpty, model.isLoadingChat {
                ProgressView("加载消息…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.chatMessages.isEmpty {
                ContentUnavailableView(
                    "暂无消息",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("发送第一条消息吧")
                )
            } else {
                messageList
            }

            Divider()
            composer
        }
        .navigationTitle(model.selectedChat?.username ?? "对话")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.chatMessages) { message in
                        MessageBubbleView(
                            message: message,
                            isMine: message.uid == model.currentUID
                        )
                        .id(message.id)
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                TextField("发消息…", text: $model.chatDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await model.sendChatMessage() }
                    }
                Button("发送") {
                    Task { await model.sendChatMessage() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.socialGreen)
                .disabled(model.chatDraft.isEmpty)
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
        Group {
            if model.isLoggedIn {
                if model.personalFeeds.isEmpty {
                    emptyState
                } else {
                    List(model.personalFeeds) { feed in
                        FeedRowView(feed: feed)
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
        if model.personalStatus.isEmpty {
            ContentUnavailableView(title, systemImage: "person", description: Text("下拉刷新试试"))
        } else {
            ContentUnavailableView(title, systemImage: "person", description: Text(model.personalStatus))
        }
    }
}
