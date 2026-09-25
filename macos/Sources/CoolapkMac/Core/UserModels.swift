import Foundation

/// 用户主页资料(/v6/user/space,容错解析)。
struct UserSpace: Identifiable {
    let uid: String
    let username: String
    let avatarURL: URL?
    let bio: String
    let city: String
    let level: Int
    let fansCount: Int
    let followCount: Int
    let feedCount: Int

    var id: String { uid }

    static func parse(fromJSONString json: String) -> UserSpace? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entity = root["data"] as? [String: Any],
              let uid = CoolapkJSON.string(entity["uid"])
        else { return nil }
        return UserSpace(
            uid: uid,
            username: CoolapkJSON.username(entity),
            avatarURL: CoolapkJSON.avatar(entity),
            bio: CoolapkJSON.cleanHTML(CoolapkJSON.string(entity["bio"]) ?? ""),
            city: CoolapkJSON.string(entity["city"]) ?? "",
            level: CoolapkJSON.int(entity["level"]),
            fansCount: CoolapkJSON.int(entity["fans"]),
            followCount: CoolapkJSON.int(entity["follow"]),
            feedCount: CoolapkJSON.int(entity["feed"])
        )
    }
}
