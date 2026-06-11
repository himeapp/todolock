import Foundation

/// 세션별 잠금 대상(FamilyActivitySelection 인코딩 Data)을 App Group에 공유한다.
/// DeviceActivityMonitor 익스텐션이 간주(점프) 종료 시점에 차단을 "원래대로" 되돌릴 때
/// 이 데이터를 읽어 풀 차단을 복원한다. (익스텐션은 SwiftData에 접근 못 하므로 App Group으로 전달)
final class SessionShieldStore {
    static let shared = SessionShieldStore()
    static let appGroupId = "group.hime.app.todolock"
    private let key = "sessionSelections"

    private var defaults: UserDefaults? { UserDefaults(suiteName: Self.appGroupId) }

    private func map() -> [String: Data] {
        (defaults?.dictionary(forKey: key) as? [String: Data]) ?? [:]
    }

    func setSelectionData(_ data: Data, for sessionId: UUID) {
        var m = map()
        m[sessionId.uuidString] = data
        defaults?.set(m, forKey: key)
    }

    func remove(_ sessionId: UUID) {
        var m = map()
        m[sessionId.uuidString] = nil
        defaults?.set(m, forKey: key)
    }
}
