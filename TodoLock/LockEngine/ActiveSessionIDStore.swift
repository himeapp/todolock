import Foundation

/// 메인 앱과 ShieldAction/DeviceActivityMonitor extension이 공유하는 App Group 저장소.
/// 익스텐션에 동일한 정의가 중복으로 존재 (extension 타깃은 별도 모듈).
final class ActiveSessionIDStore {
    static let shared = ActiveSessionIDStore()
    static let appGroupId = "group.hime.app.todolock"
    private let key = "activeSessionIds"

    var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupId)
    }

    func allIds() -> [UUID] {
        guard let strings = defaults?.array(forKey: key) as? [String] else { return [] }
        return strings.compactMap(UUID.init)
    }

    func add(_ id: UUID) {
        var ids = allIds()
        guard !ids.contains(id) else { return }
        ids.append(id)
        save(ids)
    }

    func remove(_ id: UUID) {
        var ids = allIds()
        ids.removeAll { $0 == id }
        save(ids)
    }

    func save(_ ids: [UUID]) {
        defaults?.set(ids.map(\.uuidString), forKey: key)
    }
}
