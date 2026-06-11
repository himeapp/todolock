import Foundation
import UserNotifications
import UIKit

/// Shield Action Extension이 보낸 알림을 탭했을 때 호출됨.
/// userInfo의 sessionId를 DeepLinkHandler에 주입.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// 앱 구동 시점엔 delegate만 연결한다. 알림 권한 요청은 스크린타임 권한과
    /// 같은 타이밍(권한 화면에서 사용자가 직접 누를 때)에 띄우기 위해 분리했다.
    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// 스크린타임 권한 요청 직후 호출. 이미 결정된 상태면 시스템이 다이얼로그를 띄우지 않는다.
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let idString = response.notification.request.content.userInfo["sessionId"] as? String,
           let id = UUID(uuidString: idString) {
            DispatchQueue.main.async {
                DeepLinkHandler.shared.pendingSessionId = id
            }
        }
        completionHandler()
    }
}
