import SwiftUI
import WebKit

/// 登录窗口:复刻上游 Tauri 登录链路,并叠加两层保险:
/// 1. 每 2 秒轮询 Cookie 存储,站点登录成功后无论跳到哪个页面都能提取会话;
/// 2. 提取后由 AppModel 校验(user/space),弹窗内显示校验中/失败状态,失败可重试。
struct LoginView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var reloadTrigger = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("登录酷安")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ZStack {
                LoginWebView { cookie in
                    Task { await model.completeLogin(cookie: cookie) }
                }
                .id(reloadTrigger)

                if model.isCompletingLogin {
                    ProgressView("校验会话…")
                        .padding(20)
                        .background(.bar, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if let error = model.loginError {
                VStack(spacing: 6) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("重试登录") {
                        model.clearLoginError()
                        reloadTrigger = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.socialGreen)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
        }
        .frame(width: 420, height: 640)
        .onChange(of: model.userProfile) { _, profile in
            if profile != nil { dismiss() }
        }
    }
}

// MARK: - WKWebView 封装

struct LoginWebView: NSViewRepresentable {
    /// 回调参数:登录成功后合并出的完整 cookie 字符串。
    let onCookie: (String) -> Void

    static let appOrigin = "http://127.0.0.1:17520"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // 与上游一致的登出页处理:等"已经退出登录"真正出现后清 Cookie 再跳登录页
        let scriptSource = """
        (function() {
            var APP_ORIGIN = "\(Self.appOrigin)";
            function isLogoutPage() {
                return (window.location.href || "").indexOf('auth/logout') !== -1;
            }
            function clearCoolapkCookies() {
                var expires = "Thu, 01 Jan 1970 00:00:00 GMT";
                var names = (document.cookie || "").split(';');
                for (var i = 0; i < names.length; i++) {
                    var name = (names[i].split('=')[0] || "").trim();
                    if (!name) continue;
                    document.cookie = name + "=; expires=" + expires + "; path=/; domain=.coolapk.com";
                    document.cookie = name + "=; expires=" + expires + "; path=/";
                }
            }
            function checkLogoutPage() {
                var text = (document.body && document.body.innerText) || "";
                if (text.indexOf('已经退出登录') !== -1) {
                    clearCoolapkCookies();
                    window.location.replace("https://account.coolapk.com/auth/login?type=coolapk&forward=" + encodeURIComponent(APP_ORIGIN + "/#/auth_callback"));
                    return true;
                }
                return isLogoutPage();
            }
            if (checkLogoutPage() && !isLogoutPage()) return;
            document.addEventListener('DOMContentLoaded', function() { checkLogoutPage(); });
        })();
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // 先检查持久化存储里的既有会话:上一轮登录可能已经成功但站点没按
        // forward 回跳(跳去了推广页),cookie 仍留在 WKWebsiteDataStore 里。
        // 有有效会话直接完成登录;没有才走 logout 清理 → 登录页链路。
        config.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let hasSession = LoginCoordinator.hasSessionCookies(cookies)
            Task { @MainActor in
                if hasSession {
                    context.coordinator.complete(
                        with: LoginCoordinator.merge(ck: "", webviewCookies: cookies)
                    )
                } else {
                    webView.load(URLRequest(url: Self.logoutChainURL()))
                    context.coordinator.startPolling(store: config.websiteDataStore)
                }
            }
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func logoutChainURL() -> URL {
        // 先 logout 清旧会话,forward 指向登录页,登录页再 forward 回本地回调地址
        let targetLogin = "https://account.coolapk.com/auth/login?type=coolapk&forward="
            + (Self.appOrigin + "/#/auth_callback")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let loginURL = "https://account.coolapk.com/auth/logout?forward="
            + targetLogin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: loginURL)!
    }

    func makeCoordinator() -> LoginCoordinator {
        LoginCoordinator(onCookie: onCookie)
    }
}

@MainActor
final class LoginCoordinator: NSObject, WKNavigationDelegate {
    let onCookie: (String) -> Void
    weak var webView: WKWebView?
    private var captured = false

    init(onCookie: @escaping (String) -> Void) {
        self.onCookie = onCookie
    }

    /// 判定 cookie 存储里是否已有有效登录会话(uid>0 且 SESSID 非占位值)。
    static func hasSessionCookies(_ cookies: [HTTPCookie]) -> Bool {
        let coolapkCookies = cookies.filter { $0.domain.hasSuffix("coolapk.com") }
        let uid = coolapkCookies.first { $0.name == "uid" }?.value ?? ""
        let sessid = coolapkCookies.first { $0.name == "SESSID" }?.value ?? ""
        guard (Int(uid) ?? 0) > 0 else { return false }
        let placeholders = ["", "deleted", "expired", "0"]
        return !placeholders.contains(sessid.lowercased())
    }

    /// 统一的登录完成出口:只执行一次。
    func complete(with cookie: String) {
        guard !captured else { return }
        captured = true
        onCookie(cookie)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // 离开登录域去往本地回调时,阻止真正的加载(本地没有服务在监听)
    }

    /// 每 2 秒检查一次 Cookie 存储:站点登录成功后无论跳到哪个页面(实测会跳
    /// 去推广页而非回调地址),都能在 2 秒内提取到会话。上限 5 分钟。
    func startPolling(store: WKWebsiteDataStore) {
        Task { @MainActor [weak self] in
            for _ in 0..<150 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !self.captured else { return }
                let cookies = await Self.allCookies(from: store)
                if Self.hasSessionCookies(cookies) {
                    self.complete(with: Self.merge(ck: "", webviewCookies: cookies))
                    return
                }
            }
        }
    }

    nonisolated private static func allCookies(from store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // 只有真正导航到本地回调源才算登录完成。登录页自身的 URL 会携带
        // forward=...auth_callback 参数,用字符串 contains 会把登录页误判成回调,
        // 导致弹窗刚打开就被 dismiss(表现为"闪一下")。
        let isLocalCallback = url.host == "127.0.0.1" && url.port == 17520
        if isLocalCallback {
            guard !captured else {
                decisionHandler(.cancel)
                return
            }
            captured = true
            decisionHandler(.cancel)

            let ck = Self.extractCookieParam(from: url.absoluteString) ?? ""
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [onCookie] cookies in
                let merged = Self.merge(ck: ck, webviewCookies: cookies)
                Task { @MainActor in onCookie(merged) }
            }
            return
        }
        decisionHandler(.allow)
    }

    /// 兼容 query 与 fragment 两种回调形态:
    /// `http://127.0.0.1:17520/?ck=...` 或 `http://127.0.0.1:17520/#/auth_callback?ck=...`
    static func extractCookieParam(from url: String) -> String? {
        for segment in url.split(separator: "?", maxSplits: 3, omittingEmptySubsequences: false).dropFirst() {
            for pair in segment.split(separator: "#").first?.split(separator: "&") ?? [] {
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard let name = parts.first, name == "ck" else { continue }
                let value = parts.dropFirst().first.map(String.init) ?? ""
                return value.removingPercentEncoding ?? value
            }
        }
        return nil
    }

    /// ck 参数是服务端下发的完整 cookie;WebView 存储的同名字段覆盖旧值,
    /// 补齐 HttpOnly 拿不到的会话字段。
    static func merge(ck: String, webviewCookies: [HTTPCookie]) -> String {
        var ordered: [(String, String)] = []
        func upsert(_ name: String, _ value: String) {
            guard !name.isEmpty else { return }
            if let index = ordered.firstIndex(where: { $0.0 == name }) {
                ordered[index] = (name, value)
            } else {
                ordered.append((name, value))
            }
        }

        for pair in ck.split(separator: ";") {
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            if let name = parts.first, let value = parts.last, parts.count == 2 {
                upsert(String(name), String(value))
            }
        }
        for cookie in webviewCookies where cookie.domain.hasSuffix("coolapk.com") {
            upsert(cookie.name, cookie.value ?? "")
        }
        return ordered.map { "\($0.0)=\($0.1)" }.joined(separator: ";")
    }
}
