import SwiftUI

/// 详情列默认面板:本月热榜 + 热门话题 两块挂件卡片(两列网格)。
/// 数据来自 model.loadHotPanel()(已加载过则内部跳过)。
struct HotPanel: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            // 上下堆叠、固定宽度,像原版右栏一样从顶部排列
            VStack(alignment: .leading, spacing: 16) {
                rankCard
                topicsCard
            }
            .padding(20)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("发现")
        .task {
            await model.loadHotPanel()
        }
    }

    // MARK: 本月热榜(1-8)

    private var rankCard: some View {
        panelCard {
            Label("本月热榜", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(Color.coolapkGreen)

            if model.hotPanelFeeds.isEmpty {
                loadingPlaceholder
            } else {
                rankList
            }
        }
    }

    private var rankList: some View {
        let feeds: [FeedItem] = Array(model.hotPanelFeeds.prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(feeds.indices, id: \.self) { index in
                rankRow(rank: index + 1, feed: feeds[index])
                if index < feeds.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func rankRow(rank: Int, feed: FeedItem) -> some View {
        Button {
            Task { await model.select(feedID: feed.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(rank)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(rankColor(rank))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.displayText.isEmpty ? feed.title : feed.displayText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 12) {
                        StatLabel(systemImage: "hand.thumbsup", count: feed.likeCount)
                        StatLabel(systemImage: "bubble.right", count: feed.replyCount)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 名次色:1 红 2 橙 3 黄,其余次级灰。
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: .red
        case 2: .orange
        case 3: .yellow
        default: .secondary
        }
    }

    // MARK: 热门话题

    private var topicsCard: some View {
        panelCard {
            Label("热门话题", systemImage: "number")
                .font(.headline)
                .foregroundStyle(Color.coolapkGreen)

            if model.hotPanelTopics.isEmpty {
                loadingPlaceholder
            } else {
                ForEach(model.hotPanelTopics, id: \.id) { topic in
                    Button {
                        Task { await model.openTopic(tag: topic.title) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(topic.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Label("\(topic.hotNum)", systemImage: "flame")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: 容器与占位

    /// 挂件卡片容器:12 圆角 + 四分之一底色。
    private func panelCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("加载中…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}

// MARK: - 应用详情面板

/// 从搜索「应用」分组点入:图标/版本/评分 + 应用简介 + APK 下载按钮。
struct ApkDetailPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.closeApkDetail()
                } label: {
                    Label("返回热榜", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let detail = model.apkDetail {
                        HStack(spacing: 12) {
                            RemoteImage(url: detail.logoURL)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                HStack(spacing: 10) {
                                    if !detail.version.isEmpty {
                                        Label(detail.version, systemImage: "number")
                                    }
                                    if !detail.score.isEmpty {
                                        Label(detail.score, systemImage: "star.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Text(detail.packageName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                        if !detail.intro.isEmpty {
                            Divider()
                            Text(detail.intro)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if model.apkDetailError.isEmpty {
                        ProgressView("加载详情…")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        Text("详情加载失败:\(model.apkDetailError)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: 460, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            downloadBar
        }
        .navigationTitle("应用")
    }

    /// 底部下载条:点击解析官方直链入下载队列;已有任务时显示进度。
    private var downloadBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.downloadSelectedApk() }
            } label: {
                Label("下载 APK", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.coolapkGreen)
            .disabled(model.selectedApkPackage == nil)

            if let task = model.downloads.tasks.first(where: { $0.packageName == model.selectedApkPackage }) {
                taskStatusLine(task)
            } else if !model.downloads.statusText.isEmpty {
                Text(model.downloads.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("下载进度也可在侧栏「下载」页查看")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func taskStatusLine(_ task: DownloadManager.DownloadTask) -> some View {
        switch task.state {
        case .running:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(
                    value: task.totalBytes > 0
                        ? Double(task.downloadedBytes) / Double(task.totalBytes)
                        : 0
                )
                Text("正在下载…可在「下载」页暂停或取消")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .paused:
            Text("已暂停,可在「下载」页继续")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .completed:
            Text("下载完成,可在「下载」页打开安装")
                .font(.caption2)
                .foregroundStyle(Color.coolapkGreen)
        case .failed:
            Text("下载失败,可重试")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - 话题动态面板

/// 从热门话题挂件点入:展示该话题下的动态列表。
struct TopicPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.closeTopic()
                } label: {
                    Label("返回热榜", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text("#\(model.selectedTopicTag ?? "")#")
                    .font(.headline)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            List(model.topicFeeds) { feed in
                FeedRowView(feed: feed)
                    .onAppear {
                        if feed.id == model.topicFeeds.last?.id {
                            Task { await model.loadTopicFeeds(reset: false) }
                        }
                    }
            }
            .listStyle(.inset)
            .overlay {
                if model.topicFeeds.isEmpty {
                    ContentUnavailableView(
                        "#\(model.selectedTopicTag ?? "")#",
                        systemImage: "number",
                        description: Text(model.topicStatus.isEmpty ? "加载中…" : model.topicStatus)
                    )
                }
            }
        }
        .navigationTitle("#\(model.selectedTopicTag ?? "")#")
        .refreshable { await model.loadTopicFeeds(reset: true) }
        .task {
            if model.topicFeeds.isEmpty { await model.loadTopicFeeds(reset: true) }
        }
    }
}
