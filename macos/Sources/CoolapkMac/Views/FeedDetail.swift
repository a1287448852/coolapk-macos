import SwiftUI

// MARK: - 详情

struct FeedDetailView: View {
    @Bindable var model: AppModel

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
                            DetailPicGrid(urls: detail.picURLs)
                        }

                        // 挂载的话题/产品标的(targetRow,即原 relatedTitle 的完整形态)
                        if let related = detail.related {
                            RelatedTargetCard(target: related)
                        }

                        // 转发动态:正文是转发理由,原帖内容在嵌套卡里
                        if let forward = detail.forward {
                            ForwardedFeedCard(forward: forward)
                        }

                        DetailInteractionBar(model: model, detail: detail)

                        Divider()

                        commentSection
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composerBar
                }
            } else if model.isLoadingDetail {
                ProgressView("加载详情…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.selectedFeedID != nil {
                // 详情接口被风控(403 验证码)时:用列表实体的摘要渲染轻详情,
                // 风控提示降级为一行小字,评论照常展示。
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let item = model.feeds.first(where: { $0.id == model.selectedFeedID }) {
                            HStack(spacing: 10) {
                                AvatarView(url: item.avatarURL, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.username)
                                        .font(.headline)
                                    Text(item.dateline, format: .coolapkRelative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if !item.displayText.isEmpty {
                                Text(item.displayText)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !item.picURLs.isEmpty {
                                DetailPicGrid(urls: item.picURLs)
                            }
                            if let forward = item.forward {
                                ForwardedFeedCard(forward: forward)
                            }
                            Divider()
                        } else if let id = model.selectedFeedID,
                                  let summary = model.searchItem(forFeedID: id) {
                            // 从搜索结果打开的动态不在 feeds 列表:用搜索实体渲染摘要头部
                            HStack(spacing: 10) {
                                AvatarView(url: summary.avatarURL, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if !summary.subtitle.isEmpty {
                                        Text(summary.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                            Divider()
                        }
                        if let error = model.detailError, !error.isEmpty {
                            Text("完整详情被风控拦截(\(error)),已显示摘要")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        commentSection
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composerBar
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

    /// 评论区:互动状态提示(非空时) + 评论列表。
    @ViewBuilder
    private var commentSection: some View {
        if let status = model.interactionStatus, !status.isEmpty {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ReplyListView(model: model)
    }

    /// 底部评论输入条:登录后可发送;游客显示登录引导。
    private var composerBar: some View {
        HStack(spacing: 10) {
            if model.isLoggedIn {
                TextField("发表评论…", text: $model.replyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("发送") {
                    Task { await model.sendReply() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.coolapkGreen)
                .disabled(model.replyDraft.isEmpty)
            } else {
                Button {
                    model.showLoginSheet = true
                } label: {
                    Label("登录后可点赞与评论", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// 详情页图片网格:自适应方格(对齐 PicGrid),点击弹出大图查看器。
/// 不复用 ContentView.swift 里的 PicGrid:那是禁改文件,且本网格需要点击态。
struct DetailPicGrid: View {
    let urls: [URL]
    @State private var viewer: FeedImageViewerContext?

    var body: some View {
        let shown = Array(urls.prefix(9))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.element.absoluteString) { index, url in
                Color.clear
                    .frame(height: 150)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $viewer) { context in
            FeedImageViewerSheet(context: context)
        }
    }
}

/// 详情互动条:计数 + 点赞/收藏按钮(未登录禁用)。
private struct DetailInteractionBar: View {
    @Bindable var model: AppModel
    let detail: FeedDetail

    private var isLiked: Bool { model.likedFeedIDs.contains(detail.id) }
    private var isFavorited: Bool { model.favoritedFeedIDs.contains(detail.id) }

    var body: some View {
        HStack(spacing: 20) {
            StatLabel(systemImage: "hand.thumbsup", count: detail.likeCount)
            StatLabel(systemImage: "bubble.right", count: detail.replyCount)
            StatLabel(systemImage: "star", count: detail.favCount)
            StatLabel(systemImage: "arrowshape.turn.up.right", count: detail.shareCount)

            Spacer()

            Button {
                Task { await model.toggleLike() }
            } label: {
                Label(
                    isLiked ? "已赞" : "点赞",
                    systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup"
                )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isLiked ? Color.coolapkGreen : Color.secondary)
            .disabled(!model.isLoggedIn)
            .help(model.isLoggedIn ? "点赞" : "登录后可点赞")

            Button {
                Task { await model.toggleFavorite() }
            } label: {
                Label(
                    isFavorited ? "已收藏" : "收藏",
                    systemImage: isFavorited ? "bookmark.fill" : "bookmark"
                )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isFavorited ? Color.coolapkGreen : Color.secondary)
            .disabled(!model.isLoggedIn)
            .help(model.isLoggedIn ? "收藏" : "登录后可收藏")
        }
        .font(.callout)
        .padding(.vertical, 6)
    }
}

struct ReplyListView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 官方口径:头部展示动态的评论总数(replynum 含子回复),列表为空时回落已加载数
            let total = model.detail.flatMap { $0.replyCount > 0 ? $0.replyCount : nil }
                ?? model.replies.count
            Text("评论 \(total)")
                .font(.headline)

            ForEach(model.replies) { reply in
                ReplyItemRow(reply: reply)
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

/// 单条评论:头像 + 用户名 + 时间/设备/属地 + 正文 + 配图 + 楼中楼展开。
struct ReplyItemRow: View {
    let reply: ReplyItem
    @State private var showSubReplies = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: reply.avatarURL, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(reply.username)
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        if !reply.location.isEmpty {
                            Text(reply.location)
                        }
                        if !reply.deviceTitle.isEmpty {
                            Text(reply.deviceTitle)
                        }
                        Text(reply.dateline, format: .coolapkRelative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
                Text(reply.message)
                    .font(.callout)
                    .textSelection(.enabled)

                if !reply.picURLs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(reply.picURLs.prefix(3).enumerated()), id: \.element.absoluteString) { index, url in
                            RemoteImage(url: url)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                subReplyToggle

                if showSubReplies {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(reply.subReplies) { sub in
                            ReplyItemRow(reply: sub)
                        }
                        if reply.subReplyMore > 0 {
                            Text("还有 \(reply.subReplyMore) 条回复未展示(需子评论分页接口)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity)
                }

                StatLabel(systemImage: "hand.thumbsup", count: reply.likeCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: 楼中楼入口

    @ViewBuilder
    private var subReplyToggle: some View {
        if !reply.subReplies.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSubReplies.toggle() }
            } label: {
                Label(
                    showSubReplies ? "收起回复" : "查看 \(reply.subReplyTotal) 条回复",
                    systemImage: showSubReplies ? "chevron.up" : "chevron.down"
                )
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.coolapkGreen)
        } else if reply.subReplyTotal > 0 {
            // 接口未内嵌子回复数据:只提示数量(需 Rust 侧子评论接口才能拉取)
            Text("共 \(reply.subReplyTotal) 条回复")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
