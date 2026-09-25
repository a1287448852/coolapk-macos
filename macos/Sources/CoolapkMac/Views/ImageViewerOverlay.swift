import SwiftUI
import Observation

/// 全窗口图片查看器:挂在 ContentView 根部 overlay。
/// 设计要点:图片占满整窗(不再有小 sheet 的黑边),工具条悬浮在图上;
/// 双击 1x↔2x 缩放,缩放后可拖拽平移;相邻图预取,翻页秒开。
struct ImageViewerOverlay: View {
    let payload: ImageViewerPayload
    @Bindable var model: AppModel
    @State private var index: Int
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero

    init(payload: ImageViewerPayload, model: AppModel) {
        self.payload = payload
        self.model = model
        _index = State(initialValue: payload.index)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.closeImageViewer() }

            photoArea

            chrome
        }
        .overlay {
            // 隐藏方向键按钮:←/→ 翻页,Esc 关闭(窗口为 key 时生效)
            Button("上一张") { move(-1) }
                .keyboardShortcut(.leftArrow)
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("下一张") { move(1) }
                .keyboardShortcut(.rightArrow)
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("关闭") { model.closeImageViewer() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .transition(.opacity)
        .task(id: index) { prefetchNeighbors() }
    }

    // MARK: 图片区

    private var photoArea: some View {
        ViewerPhoto(url: payload.urls[index], zoom: zoom, offset: offset)
            .id(payload.urls[index])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    zoom = zoom > 1 ? 1 : 2
                    if zoom == 1 { offset = .zero }
                }
            }
            .simultaneousGesture(dragGesture)
            .overlay {
                // 左右半屏热区:点边缘翻页(不影响双击缩放落在图片中央)
                HStack(spacing: 0) {
                    Rectangle().fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { move(-1) }
                        .frame(width: 90)
                    Spacer(minLength: 0)
                    Rectangle().fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { move(1) }
                        .frame(width: 90)
                }
                .opacity(zoom > 1 ? 0 : 1)
            }
    }

    /// 缩放后拖拽平移;1x 时拖拽无效(交给点击/双击)。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: zoom > 1 ? 1 : 20)
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(width: value.translation.width, height: value.translation.height)
            }
            .onEnded { _ in
                // 松手不回弹:保持位置,双击复位
            }
    }

    // MARK: 悬浮工具条

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(index + 1) / \(payload.urls.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())

                Spacer()

                if zoom > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            zoom = 1
                            offset = .zero
                        }
                    } label: {
                        Label("适应窗口", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    model.closeImageViewer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("关闭 (Esc)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .frame(maxHeight: 60, alignment: .top)

            Spacer()

            HStack {
                pagerButton(isEnabled: index > 0, systemImage: "chevron.left") { move(-1) }
                Spacer()
                pagerButton(isEnabled: index < payload.urls.count - 1, systemImage: "chevron.right") { move(1) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .frame(maxHeight: 80, alignment: .bottom)
            .opacity(zoom > 1 ? 0 : 1)
        }
    }

    private func pagerButton(isEnabled: Bool, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 0.9 : 0.25)
        .help(systemImage == "chevron.left" ? "上一张 (←)" : "下一张 (→)")
    }

    private func move(_ delta: Int) {
        let next = index + delta
        guard payload.urls.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            index = next
            zoom = 1
            offset = .zero
        }
    }

    /// 相邻图预取:翻页时高分辨率变体已在缓存,体感秒开。
    private func prefetchNeighbors() {
        for neighbor in [index + 1, index - 1] where payload.urls.indices.contains(neighbor) {
            let url = payload.urls[neighbor]
            Task.detached(priority: .utility) {
                _ = await CDNImageCache.image(for: url, pixelWidth: 2400)
            }
        }
    }
}

/// 查看器单图:先展示列表已在缓存的缩放变体(秒开),后台加载 2400px 高清版淡入。
private struct ViewerPhoto: View {
    let url: URL
    let zoom: CGFloat
    let offset: CGSize
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .offset(offset)
                    .animation(.easeInOut(duration: 0.15), value: image)
            } else {
                ProgressView("加载大图…")
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .task(id: url) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        // 1) 列表同 URL 的 720px 变体大概率已在缓存:先秒开
        if let cached = await CDNImageCache.image(for: url, pixelWidth: 720) {
            if image == nil { image = cached }
        }
        // 2) 2400px 高清版覆盖(相同缓存键跳过)
        if let hiRes = await CDNImageCache.image(for: url, pixelWidth: 2400) {
            image = hiRes
        }
    }
}
