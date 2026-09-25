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

    // MARK: 通知:点赞/系统通知的字段回落(2026-09-25 实测形态)

    /// feedLikeList 实体是完整动态:作者字段是自己,点赞者在 like* 字段,
    /// 同一动态被多人点赞时实体 id 相同,必须拼 likeUid 去重。
    func testNotificationLikeParseShowsLikerAndUniqueIDs() throws {
        let json = """
        {"code":200,"data":[
          {"id":68265703,"entityType":"feed","username":"绝情闲鱼","userAvatar":"http://avatar.coolapk.com/me.png",
           "title":"绝情闲鱼的动态","message":"分享一下第一次贴UV膜的感受",
           "likeUsername":"十七岁的西蒙","likeUid":"17168206","likeAvatar":"http://avatar.coolapk.com/liker.png",
           "likeTime":1763435740,"dateline":1761740578},
          {"id":68265703,"entityType":"feed","username":"绝情闲鱼","userAvatar":"http://avatar.coolapk.com/me.png",
           "title":"绝情闲鱼的动态","message":"分享一下第一次贴UV膜的感受",
           "likeUsername":"二阶堂真红love","likeUid":"1351398","likeAvatar":"http://avatar.coolapk.com/liker2.png",
           "likeTime":1762349932,"dateline":1761740578}
        ]}
        """
        let items = NotificationItem.parseList(fromJSONString: json)
        XCTAssertEqual(items.count, 2, "两位点赞者都要出现,不能被实体 id 去重吃掉")

        let first = items[0]
        XCTAssertEqual(first.username, "十七岁的西蒙", "应显示点赞者而不是动态作者(自己)")
        XCTAssertEqual(first.avatarURL?.absoluteString, "https://avatar.coolapk.com/liker.png")
        XCTAssertEqual(first.id, "68265703_17168206")
        XCTAssertNotEqual(items[0].id, items[1].id, "同一动态的不同点赞者 id 必须不同")
        XCTAssertEqual(
            first.dateline, Date(timeIntervalSince1970: 1_763_435_740),
            "点赞时间应取 likeTime 而不是动态发布时间"
        )
        XCTAssertEqual(first.feedID, "68265703", "点赞通知应携带可跳转的动态 id")
        XCTAssertTrue(first.note.hasPrefix("赞了你的动态"), "缺 note 时应按官方样式拼接,实际:\(first.note)")
        XCTAssertTrue(first.note.contains("分享一下第一次贴UV膜的感受"), "title 是占位时应回落到正文")
    }

    /// notification 实体(评论回复/系统提醒)的发送方在 from* 字段;
    /// note 里的"点击查看"是 <a href> 外链,清理文案的同时要保出链接。
    func testNotificationSystemNoticeFallsBackToFromUserAndExtractsLink() throws {
        let json = """
        {"code":200,"data":[
          {"id":635338008,"entityType":"notification","dateline":1789831403,
           "fromuid":10086,"fromusername":"酷安小秘书",
           "fromUserAvatar":"http://image.coolapk.com/secretary.png",
           "fromUserInfo":{"uid":10086,"username":"酷安小秘书","userAvatar":"http://image.coolapk.com/secretary.png"},
           "note":"您的账号在陌生设备尝试手机验证码登录,请注意账号安全 登录地点:河南 郑州  登录设备::<a href=\\"https://account.coolapk.com/auth/accountUnusualActivity?messageId=2476134&drawNav=1\\">点击查看</a>",
           "url":"/u/10086"}
        ]}
        """
        let items = NotificationItem.parseList(fromJSONString: json)
        XCTAssertEqual(items.count, 1)

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.username, "酷安小秘书", "应回落到 fromusername")
        XCTAssertEqual(item.avatarURL?.absoluteString, "https://image.coolapk.com/secretary.png", "应回落到 fromUserAvatar")
        XCTAssertFalse(item.note.contains("<a"), "note 应清理 HTML 标签")
        XCTAssertTrue(item.note.contains("点击查看"))
        XCTAssertEqual(
            item.actionURL?.absoluteString,
            "https://account.coolapk.com/auth/accountUnusualActivity?messageId=2476134&drawNav=1",
            "应从 note 的 <a href> 提取外链供点击打开"
        )
        XCTAssertNil(item.feedID, "系统通知没有动态目标,不能误跳详情")
        XCTAssertEqual(item.dateline, Date(timeIntervalSince1970: 1_789_831_403))
    }

    /// 点赞通知 title 是真实标题时,拼接文案优先用标题。
    func testNotificationLikeNotePrefersRealTitle() throws {
        let json = """
        {"code":200,"data":[
          {"id":46000002,"entityType":"feed","username":"甲","title":"广州首出小米18promax",
           "message":"全新拆封,少1200","likeUsername":"乙","likeUid":"2","likeTime":1763435740}
        ]}
        """
        let item = try XCTUnwrap(NotificationItem.parseList(fromJSONString: json).first)
        XCTAssertEqual(item.note, "赞了你的动态:广州首出小米18promax")
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

    // MARK: 应用搜索与详情

    /// APK 专项搜索实体:packageName 是包名,标题/图标齐备,kind 为 .apk。
    func testApkSearchListParse() throws {
        let json = """
        {"code":200,"data":[
          {"id":"10910","title":"微信","packageName":"com.tencent.mm","version":"8.0.78","score":"4.1",
           "logo":"http://pp.myapp.com/ma_icon/0/icon_1/256","entityType":"apk"},
          {"id":"1","title":"酷安","packageName":"com.coolapk.market","score":"4.5",
           "logo":"http://image.coolapk.com/logo.png","entityType":"apk"}
        ]}
        """
        let items = SearchResultSection.parseApkList(fromJSONString: json)
        XCTAssertEqual(items.count, 2, "应解析出 2 个应用,实际 \(items.count)")

        let wechat = items[0]
        XCTAssertEqual(wechat.kind, .apk)
        XCTAssertEqual(wechat.title, "微信")
        XCTAssertEqual(wechat.apkPackage, "com.tencent.mm", "包名应透出供详情/下载使用")
        XCTAssertEqual(wechat.subtitle, "com.tencent.mm", "副标题应显示包名")
        XCTAssertTrue(wechat.avatarURL?.absoluteString.hasPrefix("https://") == true, "图标应升级 https")

        XCTAssertEqual(items[1].apkPackage, "com.coolapk.market")
    }

    func testApkDetailParse() throws {
        let json = """
        {"code":200,"data":{"title":"微信","apkname":"com.tencent.mm",
         "apkversionname":"8.0.78","score":"4.1",
         "logo":"http://pp.myapp.com/ma_icon/0/icon_1/256","description":"<p>即时通讯</p>"}}
        """
        let detail = try XCTUnwrap(ApkDetail.parse(fromJSONString: json))
        XCTAssertEqual(detail.packageName, "com.tencent.mm")
        XCTAssertEqual(detail.title, "微信")
        XCTAssertEqual(detail.version, "8.0.78")
        XCTAssertEqual(detail.intro, "即时通讯", "简介应清理 HTML 标签")
        XCTAssertTrue(detail.logoURL?.absoluteString.hasPrefix("https://") == true)
    }

    func testApkDetailParseRejectsMissingPackage() {
        let json = """
        {"code":200,"data":{"title":"无名应用"}}
        """
        XCTAssertNil(ApkDetail.parse(fromJSONString: json), "缺包名的详情应拒绝解析")
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

    /// recentChatUser 实体只有 uid/userAvatar/userInfo,名字与头像在嵌套 userInfo 里,
    /// 系统会话(官方"酷安小助手")没有 message 与 dateline,不能显示 1970 时间。
    func testChatUserParsesNestedUserInfoAndToleratesMissingDateline() throws {
        let json = """
        {"data":[{"entityId":"10086","entityType":"contacts","uid":"10086",
          "userAvatar":"http://image.coolapk.com/secretary.png",
          "userInfo":{"uid":10086,"username":"酷安小秘书","displayUsername":"酷安小秘书"}}]}
        """
        let users = ChatUser.parseList(fromJSONString: json)
        XCTAssertEqual(users.count, 1)

        let user = try XCTUnwrap(users.first)
        XCTAssertEqual(user.uid, "10086")
        XCTAssertEqual(user.username, "酷安小秘书", "应从嵌套 userInfo 取名字")
        XCTAssertEqual(user.avatarURL?.absoluteString, "https://image.coolapk.com/secretary.png")
        XCTAssertTrue(user.lastMessage.isEmpty, "recentChatUser 无 lastMessage 字段")
        XCTAssertFalse(user.hasValidDateline, "缺 dateline 是 1970 纪元,列表应隐藏时间")
        XCTAssertEqual(user.id, "10086", "ukey 为空时 id 回落到 uid")
    }

    /// message/list 形态的发送方在 from* 字段,id 缺失时回落 entityId。
    func testChatMessageFallsBackToFromFieldsAndEntityID() throws {
        let json = """
        {"data":[{"entityId":"10086_2723818","entityType":"message","dateline":1783339473,
          "fromuid":10086,"fromusername":"酷安小秘书",
          "fromUserAvatar":"http://image.coolapk.com/secretary.png",
          "message":"<b>小米18 Pro Max核心参数曝光</b>"}]}
        """
        let messages = ChatMessage.parseList(fromJSONString: json)
        XCTAssertEqual(messages.count, 1)

        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.id, "10086_2723818", "id 缺失时应回落 entityId")
        XCTAssertEqual(message.uid, "10086", "uid 应回落 fromuid,供 isMine 判定")
        XCTAssertEqual(message.username, "酷安小秘书")
        XCTAssertEqual(message.avatarURL?.absoluteString, "https://image.coolapk.com/secretary.png")
        XCTAssertEqual(message.message, "小米18 Pro Max核心参数曝光")
    }

    // MARK: 浏览历史

    /// recentHistory 实体:target 为用户/话题/数码/动态,头像是 logo,时间是 lastupdate。
    func testHistoryItemParseUserTarget() throws {
        let json = """
        {"code":200,"data":[{"id":203513180,"entityType":"recentHistory",
          "title":"那片梧桐那场雨","logo":"https://avatar.coolapk.com/data/001/08/05/70_avatar_middle.jpg",
          "target_id":1080570,"target_type":"user","target_type_title":"用户",
          "fans_num":85057,"follow_num":60,"lastupdate":1789831376,"url":"/u/1080570"}]}
        """
        let items = HistoryItem.parseList(fromJSONString: json)
        XCTAssertEqual(items.count, 1)

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, "203513180")
        XCTAssertEqual(item.title, "那片梧桐那场雨")
        XCTAssertEqual(item.logoURL?.absoluteString, "https://avatar.coolapk.com/data/001/08/05/70_avatar_middle.jpg")
        XCTAssertEqual(item.subtitle, "用户 · 粉丝 85057")
        XCTAssertEqual(item.lastUpdate, Date(timeIntervalSince1970: 1_789_831_376))
        XCTAssertEqual(item.userTarget, "1080570")
        XCTAssertNil(item.feedTarget)
        XCTAssertNil(item.topicTarget)
    }

    func testHistoryItemTargets() throws {
        let feed = try XCTUnwrap(HistoryItem(entity: [
            "id": "46000001", "title": "某条动态", "target_type_title": "动态",
            "lastupdate": 1_789_831_376, "url": "/feed/46000001",
        ]))
        XCTAssertEqual(feed.feedTarget, "46000001")
        XCTAssertNil(feed.userTarget)
        XCTAssertEqual(feed.subtitle, "动态")

        let topic = try XCTUnwrap(HistoryItem(entity: [
            "id": "125029", "title": "HyperOS4", "target_type_title": "话题",
            "comment_num": 27454, "lastupdate": 1_789_610_516, "url": "/t/HyperOS4",
        ]))
        XCTAssertEqual(topic.topicTarget, "HyperOS4")
        XCTAssertEqual(topic.subtitle, "话题 · 讨论 27454")

        let product = try XCTUnwrap(HistoryItem(entity: [
            "id": "4207", "title": "小米15 Pro", "target_type_title": "数码",
            "comment_num": 99362, "lastupdate": 1_787_894_928, "url": "/product/4207",
        ]))
        XCTAssertNil(product.feedTarget)
        XCTAssertNil(product.userTarget)
        XCTAssertNil(product.topicTarget, "数码产品暂无站内跳转")
        XCTAssertEqual(product.subtitle, "数码 · 讨论 99362")
    }

    func testHistoryItemRejectsMissingTitle() {
        let item = HistoryItem(entity: ["id": "1", "url": "/u/1"])
        XCTAssertNil(item, "缺 title 的历史实体无法展示,应拒绝解析")
    }

    // MARK: 下载版本

    /// getDownloadVersionList:只保留 apk 直链,包名以调用方传入为准,http 升级 https。
    func testDownloadVersionParseList() throws {
        let json = """
        {"code":200,"data":[
          {"url":"http://imtt.dd.qq.com/1689/apk/ABC/weixin.apk","packagenname":"com.tencent.mm","version_name":"8.0.78"},
          {"url":"https://example.com/page","title":"网页,不是安装包"}
        ]}
        """
        let versions = DownloadVersion.parseList(fromJSONString: json, packageName: "com.tencent.mm")
        XCTAssertEqual(versions.count, 1, "非 apk 直链应被过滤")

        let version = try XCTUnwrap(versions.first)
        XCTAssertEqual(version.packageName, "com.tencent.mm", "包名应被调用方传入值覆盖")
        XCTAssertEqual(version.versionName, "8.0.78")
        XCTAssertTrue(version.url.absoluteString.hasPrefix("https://"), "下载地址应升级 https")
        XCTAssertEqual(version.id, "com.tencent.mm@8.0.78")
    }
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
