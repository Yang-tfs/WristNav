import Foundation
import UserNotifications

/// 通知桥：把转向信息写入 iOS 通知中心
/// 红米 Watch 6 通过 ANCS（Apple Notification Center Service）订阅通知，
/// 因此这里的每条本地通知都会出现在手表上（文字 + 震动）。
final class NotificationBridge: NSObject {

    static let shared = NotificationBridge()
    private override init() { super.init() }

    private let categoryIdentifier = "WNNavigationAlert"
    private let threadIdentifier = "wn-navigation"
    private var lastPostedText: String = ""
    private var lastPostedAt: Date = .distantPast

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// 发送转向通知
    /// - Parameters:
    ///   - text: 腕上显示文字（简短）
    ///   - distance: 距离该转向点的米数
    ///   - force: 是否忽略去重（关键转向建议强制）
    func postTurn(text: String, distance: CLLocationDistance, force: Bool = false) {
        // 去重：同一条指令 3 秒内不重复发送，避免手表震动轰炸
        let now = Date()
        if !force && text == lastPostedText && now.timeIntervalSince(lastPostedAt) < 3 {
            return
        }
        lastPostedText = text
        lastPostedAt = now

        let content = UNMutableNotificationContent()
        content.title = "腕上导航"
        let distanceText = distance >= 1000
            ? String(format: "%.1f公里后", distance / 1000)
            : "\(Int(max(0, distance)))米后"
        content.body = "\(distanceText) \(text)"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        // 每条通知使用独立 identifier 触发 ANCS "added" 事件；
        // threadIdentifier 仅用于 iOS 通知中心归组，结束后可批量清除
        content.threadIdentifier = threadIdentifier

        let request = UNNotificationRequest(
            identifier: "wn-turn-\(UUID().uuidString)",
            content: content,
            trigger: nil   // 立即触发
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[WristNav] 通知发送失败: \(error.localizedDescription)")
            }
        }
    }

    /// 到达通知
    func postArrival(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "腕上导航"
        content.body = "◆ 已到达 \(name)"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.threadIdentifier = threadIdentifier

        let request = UNNotificationRequest(
            identifier: "wn-arrival-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 清除所有导航通知（结束后调用）
    func clear() {
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
            guard let self = self else { return }
            let ids = notifications
                .filter { $0.request.content.threadIdentifier == self.threadIdentifier }
                .map { $0.request.identifier }
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }
}
