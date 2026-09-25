import XCTest
@testable import CoolapkMac

/// 信息流/详情/评论板块的模型解析单测(纯离线,JSON 对齐真实接口字段)。
/// 转发结构来源:/v6/feed/detail(raw)实体的 forwardSourceFeed;
/// 楼中楼来源:/v6/feed/replyList 的 replyRows / replyRowsCount / replyRowsMore。
final class FeedDetailTests: XCTestCase {
    // MARK: 转发实体解析

    func testForwardedFeedParsesFromForwardSourceFeed() throws {
        let entity: [String: Any] = [
            "id": "100",
            "username": "转发者",
            "userAvatar": "http://a.com/f.jpg",
            "message": "转发理由:太真实了",
            "forwardSourceFeed": [
                "id": "99",
                "username": "原作者",
                "userAvatar": "http://a.com/o.jpg",
                "message": "原帖正文",
                "pics": ["http://image.coolapk.com/a.jpg"],
                "dateline": 1_700_000_000,
            ] as [String: Any],
        ]
        let item = try XCTUnwrap(FeedItem(entity: entity))
        let forward = try XCTUnwrap(item.forward)
        XCTAssertEqual(forward.id, "99")
        XCTAssertEqual(forward.username, "原作者")
        XCTAssertEqual(forward.message, "原帖正文")
        XCTAssertEqual(forward.picURLs.count, 1)
        XCTAssertTrue(forward.picURLs.first?.absoluteString.hasPrefix("https://") ?? false, "图片应升级 https")
    }

    func testFeedItemWithoutForwardHasNilForward() {
        let entity: [String: Any] = [
            "id": "101",
            "username": "普通用户",
            "message": "普通动态",
        ]
        let item = FeedItem(entity: entity)
        XCTAssertNotNil(item)
        XCTAssertNil(item?.forward)
    }

    /// 真实接口的转发原帖对象键名是 sourceFeed(user/space 与详情 raw 实体实测),须优先于 forwardSourceFeed。
    func testForwardedFeedParsesFromSourceFeedKey() throws {
        let entity: [String: Any] = [
            "id": "110",
            "username": "转发者",
            "message": "帮顶",
            "forwardType": 1,
            "forwardid": "99",
            "sourceFeed": [
                "id": "99",
                "username": "原作者",
                "message": "原帖正文",
            ] as [String: Any],
        ]
        let item = try XCTUnwrap(FeedItem(entity: entity))
        let forward = try XCTUnwrap(item.forward)
        XCTAssertEqual(forward.id, "99")
        XCTAssertEqual(forward.username, "原作者")
    }

    /// sourceFeed 是空串/非对象(普通动态)时不得误判为转发。
    func testForwardedFeedIgnoresNonObjectSourceFeed() {
        let entity: [String: Any] = [
            "id": "111",
            "username": "普通用户",
            "message": "普通动态",
            "sourceFeed": "",
        ]
        let item = FeedItem(entity: entity)
        XCTAssertNil(item?.forward)
    }

    /// 转发动态的列表 message 常是 "{username} 的动态" 占位:只有理由文本没有图也不该被丢实体。
    func testForwardOnlyEntitySurvivesInitWithStubMessage() throws {
        let entity: [String: Any] = [
            "id": "102",
            "username": "转发者",
            "message": "转发者 的动态",
            "forwardSourceFeed": [
                "id": "98",
                "username": "原作者",
                "message": "原帖",
            ] as [String: Any],
        ]
        let item = try XCTUnwrap(FeedItem(entity: entity))
        XCTAssertEqual(item.excerpt, "", "占位理由应视为空文本")
        XCTAssertNotNil(item.forward, "仅靠原帖数据也应保留实体")
    }

    // MARK: 挂载标的(targetRow)

    func testRelatedTargetParsesTopicRow() throws {
        let entity: [String: Any] = [
            "id": "103",
            "username": "发帖人",
            "message": "正文",
            "targetRow": [
                "entityType": "feedTarget",
                "targetType": "topic",
                "title": "MagicOS11流光通透",
                "subTitle": "17.7万热度 1308讨论",
                "logo": "http://image.coolapk.com/tag.png",
            ] as [String: Any],
        ]
        let item = try XCTUnwrap(FeedItem(entity: entity))
        let related = try XCTUnwrap(item.related)
        XCTAssertEqual(related.title, "MagicOS11流光通透")
        XCTAssertEqual(related.subtitle, "17.7万热度 1308讨论")
        XCTAssertEqual(related.kind, "topic")
        XCTAssertNotNil(related.logoURL)
    }

    func testRelatedTargetNilForMissingOrHollowRow() {
        let hollow: [String: Any] = ["id": "104", "username": "u", "message": "m", "targetRow": [String: Any]()]
        XCTAssertNil(FeedItem(entity: hollow)?.related)

        let absent: [String: Any] = ["id": "105", "username": "u", "message": "m"]
        XCTAssertNil(FeedItem(entity: absent)?.related)
    }

    // MARK: 类型标签与运营来源

    func testFeedTypeNameAndInfoHtmlParsed() throws {
        let entity: [String: Any] = [
            "id": "106",
            "username": "图文作者",
            "title": "图文标题",
            "message": "正文",
            "feedType": "feedArticle",
            "feedTypeName": "图文",
            "infoHtml": "来自头条推荐",
        ]
        let item = try XCTUnwrap(FeedItem(entity: entity))
        XCTAssertEqual(item.feedTypeName, "图文")
        XCTAssertEqual(item.infoHtml, "来自头条推荐")
        XCTAssertEqual(item.displayText, "图文标题", "图文实体优先展示标题")
    }

    // MARK: 详情转发 + 标的

    func testFeedDetailParsesForwardAndRelatedFromRawDetail() throws {
        let json = """
        {"data": {
            "id": "200",
            "username": "转发者",
            "message": "看这个",
            "forwardSourceFeed": {"id": "199", "username": "原作者", "message": "原帖正文", "picArr": ["http://image.coolapk.com/p.jpg"]},
            "targetRow": {"targetType": "product", "title": "REDMI K90 Pro Max", "subTitle": "64.1万热度", "logo": "http://image.coolapk.com/logo.png"}
        }}
        """
        let detail = try XCTUnwrap(FeedDetail.parse(fromJSONString: json))
        let forward = try XCTUnwrap(detail.forward)
        XCTAssertEqual(forward.id, "199")
        XCTAssertEqual(forward.username, "原作者")
        XCTAssertEqual(forward.message, "原帖正文")
        XCTAssertEqual(forward.picURLs.count, 1)

        let related = try XCTUnwrap(detail.related)
        XCTAssertEqual(related.title, "REDMI K90 Pro Max")
        XCTAssertEqual(related.kind, "product")
        XCTAssertEqual(detail.relatedTitle, "REDMI K90 Pro Max", "relatedTitle 语义 = 挂载标的标题")
    }

    func testFeedDetailWithoutForwardAndTargetKeepsLegacyFieldsEmpty() throws {
        let json = """
        {"data": {"id": "201", "username": "u", "message": "普通动态"}}
        """
        let detail = try XCTUnwrap(FeedDetail.parse(fromJSONString: json))
        XCTAssertNil(detail.forward)
        XCTAssertNil(detail.related)
        XCTAssertEqual(detail.relatedTitle, "")
    }

    // MARK: 评论楼中楼

    func testReplyItemParsesSubRepliesAndCounters() throws {
        let entity: [String: Any] = [
            "id": "300",
            "username": "楼主评论",
            "message": "主评论",
            "likenum": 12,
            "deviceTitle": "Xiaomi 18",
            "ipLocation": "浙江",
            "picArr": ["http://image.coolapk.com/r.jpg"],
            "replyRowsCount": 4,
            "replyRowsMore": 57,
            "replyRows": [
                [
                    "id": 301,
                    "username": "子评论甲",
                    "userAvatar": "http://a.com/s1.jpg",
                    "message": "回复内容1",
                    "likenum": 0,
                    "dateline": 1_789_774_710,
                ] as [String: Any],
                [
                    "id": 302,
                    "username": "子评论乙",
                    "message": "回复内容2",
                ] as [String: Any],
            ] as [Any],
        ] as [String: Any]
        let reply = try XCTUnwrap(ReplyItem(entity: entity))
        XCTAssertEqual(reply.subReplies.count, 2, "replyRows 内嵌子回复应就地解析")
        XCTAssertEqual(reply.subReplies.first?.id, "301", "子回复数字 id 应转字符串")
        XCTAssertEqual(reply.subReplyCount, 4)
        XCTAssertEqual(reply.subReplyMore, 57)
        XCTAssertEqual(reply.subReplyTotal, 61, "总数 = 内嵌数 + 未下发数")
        XCTAssertEqual(reply.deviceTitle, "Xiaomi 18")
        XCTAssertEqual(reply.location, "浙江")
        XCTAssertEqual(reply.picURLs.count, 1)
    }

    func testReplyItemFlatReplyHasNoSubReplies() throws {
        let entity: [String: Any] = [
            "id": "310",
            "username": "普通评论",
            "message": "沙发",
        ]
        let reply = try XCTUnwrap(ReplyItem(entity: entity))
        XCTAssertTrue(reply.subReplies.isEmpty)
        XCTAssertEqual(reply.subReplyTotal, 0)
    }

    func testReplyItemNilForMissingID() {
        let entity: [String: Any] = ["username": "无ID"]
        XCTAssertNil(ReplyItem(entity: entity))
        XCTAssertNil(ReplyItem(entity: nil))
    }

    // MARK: 原有占位回落行为不回退

    func testDisplayTextStubFallbackStillWorks() throws {
        // title 缺失且 message 是占位 → 空展示(带图占位实体会保留,只看图)
        let stub: [String: Any] = ["id": "400", "username": "张三", "message": "张三 的动态", "pics": ["http://image.coolapk.com/x.jpg"]]
        let stubItem = try XCTUnwrap(FeedItem(entity: stub))
        XCTAssertEqual(stubItem.displayText, "")

        let real: [String: Any] = ["id": "401", "username": "李四", "message": "真实内容"]
        let realItem = try XCTUnwrap(FeedItem(entity: real))
        XCTAssertEqual(realItem.displayText, "真实内容")
    }
}
