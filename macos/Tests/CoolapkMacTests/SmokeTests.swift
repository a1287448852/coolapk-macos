import XCTest
@testable import CoolapkCoreSwift
@testable import CoolapkMac

/// FFI 冒烟测试:验证 Rust 核心 ↔ Swift 绑定链路。
final class SmokeTests: XCTestCase {
    func testTokenGeneration() throws {
        let auth = UniCoolapkAuth(deviceCode: "smoke-test-device")
        let token = try auth.getAppToken()
        XCTAssertTrue(token.hasPrefix("v3"), "Token V3 应以 v3 开头,实际:\(token.prefix(10))")
        XCTAssertGreaterThan(token.count, 70)
    }

    func testTokenChangesWithDeviceCode() throws {
        let auth = UniCoolapkAuth(deviceCode: "device-a")
        let tokenA = try auth.getAppToken()
        auth.setDeviceCode(deviceCode: "device-b")
        let tokenB = try auth.getAppToken()
        XCTAssertNotEqual(tokenA, tokenB, "设备码切换后签名应变化")
    }

    /// 真实网络用例:热门流拉取 + 容错解析。依赖外网,失败时看 message 判断网络/风控。
    func testHotFeedsLiveAPI() async throws {
        let api = CoolapkApi(cookieStorePath: nil)
        let json = try await api.getHotFeeds(page: 1)
        let count = FeedItemListTestHook.parse(json)
        XCTAssertGreaterThan(count, 0, "热门流不应为空,原始长度:\(json.count) 字节")
    }
}

/// 登录回调的 cookie 提取与合并逻辑(纯离线)。
@MainActor
final class LoginCookieTests: XCTestCase {
    func testExtractCKFromFragmentQuery() {
        let url = "http://127.0.0.1:17520/#/auth_callback?ck=uid%3D123%3BSESSID%3Dab%3Dcd"
        XCTAssertEqual(LoginCoordinator.extractCookieParam(from: url), "uid=123;SESSID=ab=cd")
    }

    func testExtractCKFromPlainQuery() {
        let url = "http://127.0.0.1:17520/?ck=uid%3D123"
        XCTAssertEqual(LoginCoordinator.extractCookieParam(from: url), "uid=123")
    }

    func testExtractCKMissing() {
        XCTAssertNil(LoginCoordinator.extractCookieParam(from: "http://127.0.0.1:17520/#/auth_callback"))
    }

    func testMergePrefersWebviewValuesAndPreservesCKOnlyFields() {
        let ck = "uid=123;username=old;SESSID=s1"
        let cookies = [
            HTTPCookie(properties: [
                .domain: ".coolapk.com", .path: "/", .name: "username", .value: "new",
            ])!,
            HTTPCookie(properties: [
                .domain: ".example.com", .path: "/", .name: "evil", .value: "x",
            ])!,
        ]
        let merged = LoginCoordinator.merge(ck: ck, webviewCookies: cookies)
        XCTAssertTrue(merged.contains("uid=123"))
        XCTAssertTrue(merged.contains("username=new"), "WebView 同名字段应覆盖 ck 旧值")
        XCTAssertTrue(merged.contains("SESSID=s1"))
        XCTAssertFalse(merged.contains("evil"), "第三方域 cookie 严禁混入")
    }
}

/// 测试辅助:复用 App 的解析逻辑(跨 target 把解析器放这里避免 @testable 依赖 App 可执行目标)。
enum FeedItemListTestHook {
    static func parse(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        switch root["data"] {
        case let list as [Any]:
            return list.count
        case let dict as [String: Any]:
            return ((dict["rows"] ?? dict["items"]) as? [Any])?.count ?? 0
        default:
            return 0
        }
    }
}
