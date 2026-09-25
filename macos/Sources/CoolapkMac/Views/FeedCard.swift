import SwiftUI

/// 信息流卡片:信息密度对齐酷安网页版。
/// 结构:头像(44) + 用户名 + Lv 徽章 / 相对时间 + 类型·来源·设备·位置芯片 /
/// 正文(话题高亮,最多 6 行) / 自适应图片网格 / 挂载标的 / 转发嵌套卡 / 四项动作条。
struct FeedCardView: View {
    let feed: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: feed.avatarURL, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                headerRow
                metaRow

                if !feed.displayText.isEmpty {
                    Text(Self.topicAttributed(feed.displayText))
                        .font(.subheadline)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !feed.picURLs.isEmpty {
                    FeedCardImageGrid(urls: feed.picURLs)
                }

                // 挂载的话题/产品标的(官方 app 正文下方的小卡)
                if let related = feed.related {
                    RelatedTargetCard(target: related)
                }

                // 转发动态:正文是转发理由,原帖内容在嵌套卡里
                if let forward = feed.forward {
                    ForwardedFeedCard(forward: forward)
                }

                actionBar
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: 头行:用户名 + 等级徽章

    private var headerRow: some View {
        HStack(spacing: 6) {
            if !feed.username.isEmpty {
                Text(feed.username)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            if let level = levelBadgeText {
                Text(level)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.coolapkGreen.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.coolapkGreen)
            }
        }
    }

    /// Lv 徽章:接口缺失或 "0" 时不显示。
    private var levelBadgeText: String? {
        let level = feed.userLevel.trimmingCharacters(in: .whitespaces)
        guard !level.isEmpty, level != "0" else { return nil }
        return "Lv.\(level)"
    }

    // MARK: 元信息行:相对时间 + 类型/来源/设备/位置芯片

    private var metaRow: some View {
        HStack(spacing: 6) {
            if feed.hasValidDateline {
                Text(feed.dateline, format: .coolapkRelative)
                    .lineLimit(1)
            }

            // 非默认类型才渲染:图文/二手/点评等,解释卡片形态差异
            let typeName = feed.feedTypeName.trimmingCharacters(in: .whitespaces)
            if !typeName.isEmpty, typeName != "动态" {
                metaChip(typeName, systemImage: "square.grid.2x2")
            }
            if !feed.infoHtml.isEmpty {
                metaChip(feed.infoHtml, systemImage: "sparkles")
            }
            if !feed.deviceTitle.isEmpty {
                metaChip(feed.deviceTitle, systemImage: "smartphone")
            }
            if !feed.location.isEmpty {
                metaChip(feed.location, systemImage: "location")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    private func metaChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }

    // MARK: 动作条:点赞 / 评论 / 转发 / 收藏

    private var actionBar: some View {
        HStack(spacing: 16) {
            StatLabel(systemImage: "hand.thumbsup", count: feed.likeCount)
            StatLabel(systemImage: "bubble.right", count: feed.replyCount)
            StatLabel(systemImage: "arrowshape.turn.up.right", count: feed.shareCount)
            StatLabel(systemImage: "bookmark", count: feed.favCount)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: 话题高亮

    /// 把正文里的 #话题# 片段染成酷安绿,其余保持默认样式。
    static func topicAttributed(_ text: String) -> AttributedString {
        guard let regex = try? NSRegularExpression(pattern: "#[^#\\n]{1,30}#") else {
            return AttributedString(text)
        }
        let nsText = text as NSString
        var result = AttributedString()
        var cursor = text.startIndex

        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            if range.lowerBound > cursor {
                result += AttributedString(String(text[cursor..<range.lowerBound]))
            }
            var topic = AttributedString(String(text[range]))
            topic.foregroundColor = .coolapkGreen
            result += topic
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result += AttributedString(String(text[cursor...]))
        }
        return result
    }
}

// MARK: - 挂载标的卡(话题/产品)

/// 动态关联的话题/产品:logo + 标题 + 热度副标题,对齐官方正文下的小卡。
struct RelatedTargetCard: View {
    let target: FeedRelatedTarget

    var body: some View {
        HStack(spacing: 8) {
            RemoteImage(url: target.logoURL)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(target.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !target.subtitle.isEmpty {
                    Text(target.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 转发嵌套卡

/// 被转发的原帖卡:头像 + 用户名 + 原帖正文 + 原帖图片(可点进查看器)。
/// 列表实体需 Rust 清洗放行 forwardSourceFeed 后才有数据;详情接口(raw)总有。
struct ForwardedFeedCard: View {
    let forward: ForwardedFeed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AvatarView(url: forward.avatarURL, size: 22)
                Text(forward.username.isEmpty ? "原动态" : forward.username)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if forward.hasValidDateline {
                    Text(forward.dateline, format: .coolapkRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if !forward.message.isEmpty {
                Text(FeedCardView.topicAttributed(forward.message))
                    .font(.caption)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !forward.picURLs.isEmpty {
                FeedCardImageGrid(urls: forward.picURLs)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension ForwardedFeed {
    /// 原帖时间无效(1970 纪元)时不渲染时间。
    var hasValidDateline: Bool {
        dateline.timeIntervalSince1970 > 100_000_000
    }
}

// MARK: - 卡片图片网格

/// 自适应图片网格:单张横幅大图;2-3 张等宽横排;>3 张 3 列方格;最多展示 9 张。
/// 所有格子用 Color.clear 吸收布局提案宽度,贴图 overlay + clipped,
/// 杜绝 scaledToFill 大图按原始尺寸撑爆卡片。点击任意格子弹出大图查看器。
struct FeedCardImageGrid: View {
    let urls: [URL]
    @State private var viewer: FeedImageViewerContext?

    var body: some View {
        let shown = Array(urls.prefix(9))
        Group {
            if shown.count == 1, let only = shown.first {
                boundedCell(url: only, index: 0, shown: shown, height: 200)
                    .frame(maxWidth: 460, alignment: .leading)
            } else if shown.count <= 3 {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.element.absoluteString) { index, url in
                        boundedCell(url: url, index: index, shown: shown, height: 140)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ],
                    spacing: 6
                ) {
                    ForEach(Array(shown.enumerated()), id: \.element.absoluteString) { index, url in
                        boundedCell(url: url, index: index, shown: shown, height: 110)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $viewer) { context in
            FeedImageViewerSheet(context: context)
        }
    }

    /// 固定高度 + 宽度由布局提案决定;图片 fill 后强制裁切。
    private func boundedCell(url: URL, index: Int, shown: [URL], height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .overlay {
                RemoteImage(url: url)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                viewer = FeedImageViewerContext(urls: shown, index: index)
            }
            .help("查看大图")
    }
}

// MARK: - 图片查看器(卡片/详情共用)

/// sheet(item:) 的载荷:要看的图组 + 起始下标。
struct FeedImageViewerContext: Identifiable {
    let urls: [URL]
    let index: Int
    var id: String { urls.map(\.absoluteString).joined(separator: "|") + "#\(index)" }
}

/// 轻量大图查看器:左右翻页(箭头按钮/方向键),Esc 或点击背景关闭。
struct FeedImageViewerSheet: View {
    let context: FeedImageViewerContext
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(context: FeedImageViewerContext) {
        self.context = context
        // clamp 防御越界
        _index = State(initialValue: min(max(0, context.index), max(0, context.urls.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack {
                    Text("\(index + 1) / \(context.urls.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(12)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .padding(12)
                }

                ViewerImage(url: context.urls[index])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(context.urls[index])

                HStack {
                    // 隐藏的方向键按钮:方向键翻页(窗口为 key 时生效)
                    Button("上一张") { move(-1) }
                        .keyboardShortcut(.leftArrow)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                    Button("下一张") { move(1) }
                        .keyboardShortcut(.rightArrow)
                        .opacity(0)
                        .frame(width: 0, height: 0)

                    Spacer()

                    Button {
                        move(-1)
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title)
                            .foregroundStyle(index == 0 ? .white.opacity(0.25) : .white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Spacer()

                    Button {
                        move(1)
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title)
                            .foregroundStyle(index == context.urls.count - 1 ? .white.opacity(0.25) : .white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(index == context.urls.count - 1)

                    Spacer()
                }
                .padding(.vertical, 14)
            }
        }
    }

    private func move(_ delta: Int) {
        let next = index + delta
        guard context.urls.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { index = next }
    }
}

/// 查看器大图:独立加载(scaledToFit),复用 CDNImageCache 与列表共享内存缓存。
private struct ViewerImage: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView("加载大图…")
                    .controlSize(.large)
            }
        }
        .task(id: url) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        if let cached = CDNImageCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        for attempt in 0..<3 {
            do {
                let (data, response) = try await CDNImageCache.session.data(for: CDNImageCache.request(for: url))
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let decoded = NSImage(data: data)
                else {
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                        continue
                    }
                    return
                }
                CDNImageCache.shared.setObject(decoded, forKey: url as NSURL)
                image = decoded
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000) << attempt)
                    continue
                }
                return
            }
        }
    }
}

// MARK: - 旧版列表行(话题面板/个人列表用)

/// 旧版列表行:保留给潜在外部引用(搜索结果等已改用 FeedCardView)。
struct FeedRowView: View {
    let feed: FeedItem
    @State private var viewer: FeedImageViewerContext?

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
                    if feed.hasValidDateline {
                        Text(feed.dateline, format: .coolapkRelative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                if !feed.displayText.isEmpty {
                    Text(feed.displayText)
                        .font(.subheadline)
                        .lineLimit(3)
                }

                if !feed.picURLs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(feed.picURLs.prefix(3).enumerated()), id: \.element.absoluteString) { index, url in
                            RemoteImage(url: url)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewer = FeedImageViewerContext(urls: feed.picURLs, index: index)
                                }
                        }
                    }
                    .sheet(item: $viewer) { context in
                        FeedImageViewerSheet(context: context)
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
