import ManagedSettings
import Foundation

/// Shield 화면의 버튼 액션 처리.
/// primary 버튼 = "과제 수행하기" → 메인 앱 딥링크
/// Shield Action Extension은 직접 다른 앱을 열 수 없으므로
/// .defer를 리턴하고 사용자가 Safari/스프링보드 통해 열도록 안내하는 방식,
/// 또는 NotificationCenter를 통해 메인 앱이 처리하게 하는 우회 필요.
///
/// 가장 안정적 패턴: primary 버튼 누르면 .defer + UNUserNotification 발송 →
/// 사용자가 notification 탭하면 todolock:// 딥링크로 메인 앱 진입.
final class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            postUnlockNotification()
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.none)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            postUnlockNotification()
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.none)
        }
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            postUnlockNotification()
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.none)
        }
    }

    /// App Group에 저장된 활성 세션 ID 중 첫 번째에 대한 알림을 보냄.
    /// 사용자가 알림 탭 → 메인 앱이 todolock://task?sessionId=... 처리.
    private func postUnlockNotification() {
        let content = UNMutableNotificationContent()
        content.title = "TodoLock"
        content.body = "탭해서 과제을 수행하세요"
        content.sound = .default

        if let sessionId = ActiveSessionIDStore.shared.firstActiveSessionId() {
            content.userInfo = ["sessionId": sessionId.uuidString]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

import UserNotifications

/// App Group의 UserDefaults에서 현재 활성 세션 ID 읽기.
/// 메인 앱이 세션 시작/종료 시 갱신.
final class ActiveSessionIDStore {
    static let shared = ActiveSessionIDStore()

    static let appGroupId = "group.hime.app.todolock"
    private let key = "activeSessionIds"

    var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupId)
    }

    func firstActiveSessionId() -> UUID? {
        guard let strings = defaults?.array(forKey: key) as? [String] else { return nil }
        return strings.compactMap(UUID.init).first
    }

    func setActiveSessionIds(_ ids: [UUID]) {
        defaults?.set(ids.map(\.uuidString), forKey: key)
    }
}
