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

    // MARK: 快讯实体文案(title 占位回落 message)

    /// 快讯实体的 title 是服务端拼的"{username}的动态"占位,真文案在 message;
    /// displayText 必须回落,否则卡片只剩图片(2026-09-25 线上回归)。
    func testFeedDisplayTextFallsBackToMessageWhenTitleIsStub() throws {
        let entity: [String: Any] = [
            "id": "46000001",
            "username": "Iris向前冲",
            "title": "Iris向前冲的动态",
            "message": "给键盘也过上了中秋节🐰节日快乐宝子们！<a class=\"feed-link-tag\" href=\"https://www.coolapk.com\">#小艺输入法#</a>",
            "picArr": ["http://image.coolapk.com/a.jpg"],
            "dateline": 1_789_700_000,
        ]
        let feed = try XCTUnwrap(FeedItem(entity: entity))
        XCTAssertEqual(
            feed.displayText,
            "给键盘也过上了中秋节🐰节日快乐宝子们！#小艺输入法#",
            "title 为占位时应展示 message 清理后的正文"
        )
    }

    func testFeedDisplayTextKeepsRealTitle() throws {
        let entity: [String: Any] = [
            "id": "46000002",
            "username": "甲",
            "title": "广州首出小米18promax 16加512g白色",
            "message": "全新拆封,少1200",
            "dateline": 1_789_700_000,
        ]
        let feed = try XCTUnwrap(FeedItem(entity: entity))
        XCTAssertEqual(feed.displayText, "广州首出小米18promax 16加512g白色", "真实标题应优先展示")
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

}

/// 搜索结果分型解析(话题/应用/用户/动态,对齐原版搜索行为)。
final class SearchResultParseTests: XCTestCase {
    private let fixture = """
    {"code":200,"data":[
      {"description":"更多相关话题","entities":[
        {"id":"10","entityType":"topic","title":"数码日常","commentnum":11701},
        {"id":"11","entityType":"topic","title":"小米天气"}]},
      {"description":"更多相关应用","entities":[
        {"id":"20","entityType":"apk","title":"小米运动健康","apkname":"运动健康","score":"9.2"}]},
      {"description":"更多相关用户","entities":[
        {"id":"30","entityType":"user","username":"雷军","userAvatar":"http://image.coolapk.com/a.png","fansnum":100}]},
      {"description":"更多相关动态","entities":[
        {"id":"40","entityType":"feed","username":"某人","message":"小米太强了","likenum":88,"replynum":9,"dateline":1789700000}]}
    ]}
    """

    func testParseGroupsAndKinds() {
        let sections = SearchResultSection.parse(fromJSONString: fixture)
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(sections[0].title, "话题")
        XCTAssertEqual(sections[0].items[0].kind, .topic)
        XCTAssertEqual(sections[0].items[0].title, "数码日常")
        XCTAssertTrue(sections[0].items[0].subtitle.contains("11701"))

        XCTAssertEqual(sections[1].items[0].kind, .apk)
        XCTAssertEqual(sections[1].items[0].title, "小米运动健康")

        XCTAssertEqual(sections[2].items[0].kind, .user)
        XCTAssertEqual(sections[2].items[0].title, "雷军")
        XCTAssertTrue(sections[2].items[0].subtitle.contains("100"))
        XCTAssertNotNil(sections[2].items[0].avatarURL, "用户头像应升级为 https")
        XCTAssertTrue(sections[2].items[0].avatarURL?.absoluteString.hasPrefix("https://") == true)

        XCTAssertEqual(sections[3].items[0].kind, .feed)
        XCTAssertEqual(sections[3].items[0].title, "小米太强了")
        XCTAssertNotNil(sections[3].items[0].feedID, "feed 类型保留可点开的动态 ID")
    }

    func testEntityWithoutTitleAndKindFiltered() {
        let json = """
        {"code":200,"data":[{"description":"更多相关话题","entities":[
          {"entityType":"topic","commentnum":5}]}]}
        """
        XCTAssertTrue(SearchResultSection.parse(fromJSONString: json).isEmpty)
    }
}
