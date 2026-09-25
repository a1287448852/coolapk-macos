import SwiftUI

/// 用户主页面板:搜索「用户」结果点入。资料头 + 动态列表(右列 460 内)。
struct UserPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.closeUserProfile()
                } label: {
                    Label("返回热榜", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let space = model.userSpace {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        profileHeader(space)
                        Divider()
                        feedList
                    }
                }
            } else if model.userSpaceError.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "person.slash",
                    description: Text(model.userSpaceError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.userSpace?.username ?? "用户")
        .refreshable { await model.loadUserFeeds(reset: true) }
    }

    private func profileHeader(_ space: UserSpace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(url: space.avatarURL, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(space.username)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        if space.level > 0 {
                            Label("Lv.\(space.level)", systemImage: "shield")
                        }
                        if !space.city.isEmpty {
                            Label(space.city, systemImage: "location")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !space.bio.isEmpty {
                Text(space.bio)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 16) {
                statLabel("动态", space.feedCount)
                statLabel("关注", space.followCount)
                statLabel("粉丝", space.fansCount)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statLabel(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(title)
        }
    }

    private var feedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.userFeeds) { feed in
                FeedRowView(feed: feed)
                    .padding(.horizontal, 16)
                    .onAppear {
                        if feed.id == model.userFeeds.last?.id {
                            Task { await model.loadUserFeeds(reset: false) }
                        }
                    }
                Divider()
            }
            if model.userFeeds.isEmpty {
                ContentUnavailableView("暂无动态", systemImage: "text.bubble", description: Text("下拉刷新试试"))
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
