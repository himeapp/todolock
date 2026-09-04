import Foundation
import FamilyControls

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

/// 감시(watchdog) 대상 선택과 하루 한도를 App Group에 공유한다.
/// DeviceActivityMonitor 익스텐션이 한도 도달 시 이 선택을 읽어 차단(shield)을 건다.
/// (익스텐션은 같은 키를 자체 복제 코드로 읽는다.)
final class WatchdogShareStore {
    static let shared = WatchdogShareStore()
    static let appGroupId = "group.hime.app.todolock"
    static let selectionKey = "watchdogSelectionData"
    static let limitKey = "watchdogLimitMinutes"

    private var defaults: UserDefaults? { UserDefaults(suiteName: Self.appGroupId) }

    func setSelection(_ selection: FamilyActivitySelection, limitMinutes: Int) {
        defaults?.set((try? JSONEncoder().encode(selection)) ?? Data(), forKey: Self.selectionKey)
        defaults?.set(limitMinutes, forKey: Self.limitKey)
    }

    func clear() {
        defaults?.removeObject(forKey: Self.selectionKey)
        defaults?.removeObject(forKey: Self.limitKey)
    }
}
