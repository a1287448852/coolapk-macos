import SwiftUI

/// 信息流卡片:信息密度对齐酷安网页版。
/// 结构:头像(44) + 用户名 + Lv 徽章 / 相对时间 + 设备·位置芯片 /
/// 正文(话题高亮,最多 6 行) / 自适应图片网格 / 四项动作条。
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

    // MARK: 元信息行:相对时间 + 设备芯片 + 位置芯片

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(feed.dateline, format: .coolapkRelative)
                .lineLimit(1)

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

// MARK: - 卡片图片网格

/// 自适应图片网格:单张横排大图(高 300,≤320 上限);
/// 2-3 张等宽横排;>3 张 3 列方格;最多展示 9 张。
private struct FeedCardImageGrid: View {
    let urls: [URL]

    var body: some View {
        let shown = Array(urls.prefix(9))
        Group {
            if shown.count == 1, let only = shown.first {
                RemoteImage(url: only)
                    .frame(height: 300)
                    .frame(maxWidth: 520, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if shown.count <= 3 {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(shown, id: \.absoluteString) { url in
                        RemoteImage(url: url)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    ForEach(shown, id: \.absoluteString) { url in
                        RemoteImage(url: url)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(minWidth: 0)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
