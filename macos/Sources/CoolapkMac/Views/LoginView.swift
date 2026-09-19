import SwiftUI
import WebKit

/// 登录窗口:复刻上游 Tauri 登录链路。
/// logout(清网页旧会话) → login?type=coolapk → 服务端带 `ck` 参数回跳本地 auth_callback,
/// WKWebView 在导航层拦截回调 URL,同时合并 Cookie 存储里的会话字段(覆盖 HttpOnly 丢失问题)。
struct LoginView: View {
    let onCookie: (String) -> Void
    @Environment(\.dismiss) private var dismiss

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

            LoginWebView { cookie in
                onCookie(cookie)
                dismiss()
            }
        }
        .frame(width: 420, height: 640)
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

        // 先 logout 清旧会话,forward 指向登录页,登录页再 forward 回本地回调地址
        let targetLogin = "https://account.coolapk.com/auth/login?type=coolapk&forward="
            + (Self.appOrigin + "/#/auth_callback")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let loginURL = "https://account.coolapk.com/auth/logout?forward="
            + targetLogin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        webView.load(URLRequest(url: URL(string: loginURL)!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> LoginCoordinator {
        LoginCoordinator(onCookie: onCookie)
    }
}

@MainActor
final class LoginCoordinator: NSObject, WKNavigationDelegate {
    let onCookie: (String) -> Void
    private var captured = false

    init(onCookie: @escaping (String) -> Void) {
        self.onCookie = onCookie
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let absolute = url.absoluteString
        if absolute.contains("auth_callback") {
            guard !captured else {
                decisionHandler(.cancel)
                return
            }
            captured = true
            decisionHandler(.cancel)

            let ck = Self.extractCookieParam(from: absolute) ?? ""
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
