import XCTest
@testable import CoolapkCoreSwift
@testable import CoolapkMac

/// 通知/私信/下载版本解析单测:全部纯离线 synthetic JSON,不依赖网络与 AppModel。
final class PersonalTests: XCTestCase {
    private let dateline: TimeInterval = 1_789_700_000

    // MARK: 通知

    func testNotificationParseListCleansHTMLAndUpgradesAvatarToHTTPS() throws {
        let json = """
        {"code":200,"data":[{"id":"1","username":"甲","userAvatar":"http://image.coolapk.com/a.png","note":"赞了你的动态<b>加粗</b>","dateline":1789700000}]}
        """
        let items = NotificationItem.parseList(fromJSONString: json)
        XCTAssertEqual(items.count, 1, "应解析出 1 条通知,实际 \(items.count)")

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, "1")
        XCTAssertEqual(item.username, "甲")
        XCTAssertEqual(item.note, "赞了你的动态加粗", "note 应去掉 HTML 标签")
        XCTAssertEqual(item.dateline, Date(timeIntervalSince1970: dateline))
        let avatar = try XCTUnwrap(item.avatarURL)
        XCTAssertTrue(
            avatar.absoluteString.hasPrefix("https://"),
            "头像应升级为 https,实际:\(avatar.absoluteString)"
        )
    }

    func testNotificationWithoutNoteIsFiltered() {
        let json = """
        {"code":200,"data":[{"id":"2","username":"甲","dateline":1789700000}]}
        """
        let items = NotificationItem.parseList(fromJSONString: json)
        XCTAssertTrue(items.isEmpty, "缺 note 的实体应被过滤,实际 \(items.count) 条")
    }

    // MARK: 私信会话

    func testChatUserParseList() throws {
        let json = """
        {"data":[{"uid":"123","ukey":"u_abc","username":"乙","userAvatar":"https://image.coolapk.com/b.png","message":"你好","dateline":1789700000}]}
        """
        let users = ChatUser.parseList(fromJSONString: json)
        XCTAssertEqual(users.count, 1, "应解析出 1 个会话,实际 \(users.count)")

        let user = try XCTUnwrap(users.first)
        XCTAssertEqual(user.uid, "123")
        XCTAssertEqual(user.ukey, "u_abc")
        XCTAssertEqual(user.username, "乙")
        XCTAssertEqual(user.lastMessage, "你好")
    }

    func testChatMessageParseListCleansMessageAndConvertsDateline() throws {
        let json = """
        {"data":[{"id":"9","uid":"123","username":"乙","userAvatar":"https://image.coolapk.com/b.png","message":"<b>你好</b>","dateline":1789700000}]}
        """
        let messages = ChatMessage.parseList(fromJSONString: json)
        XCTAssertEqual(messages.count, 1, "应解析出 1 条消息,实际 \(messages.count)")

        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.id, "9")
        XCTAssertEqual(message.uid, "123")
        XCTAssertEqual(message.message, "你好", "message 应去掉 HTML 标签")
        XCTAssertEqual(message.dateline, Date(timeIntervalSince1970: dateline), "dateline 应转为时间点")
    }

    func testChatUserWithoutUIDAndIDIsFiltered() {
        let json = """
        {"data":[{"ukey":"u_only","username":"乙"}]}
        """
        let users = ChatUser.parseList(fromJSONString: json)
        XCTAssertTrue(users.isEmpty, "缺 uid 与 id 的会话应被过滤,实际 \(users.count) 条")
    }

    // MARK: 下载版本

    func testDownloadVersionParseListOverridesPackageNameAndUpgradesURLToHTTPS() throws {
        let json = """
        {"data":[{"url":"http://apk.coolapk.com/x.apk","version_name":"v1.0"}]}
        """
        let versions = DownloadVersion.parseList(fromJSONString: json, packageName: "com.test")
        XCTAssertEqual(versions.count, 1, "应解析出 1 个版本,实际 \(versions.count)")

        let version = try XCTUnwrap(versions.first)
        XCTAssertEqual(version.packageName, "com.test", "packageName 应被入参覆盖")
        XCTAssertEqual(version.versionName, "v1.0")
        XCTAssertEqual(
            version.url.absoluteString,
            "https://apk.coolapk.com/x.apk",
            "下载地址应升级为 https"
        )
    }

    func testDownloadVersionWithoutAPKSuffixIsFiltered() {
        let json = """
        {"data":[{"url":"https://example.com/page","version_name":"v1.0"}]}
        """
        let versions = DownloadVersion.parseList(fromJSONString: json, packageName: "com.test")
        XCTAssertTrue(versions.isEmpty, "非 .apk 下载地址应被过滤,实际 \(versions.count) 条")
    }
}
