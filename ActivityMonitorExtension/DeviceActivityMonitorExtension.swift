import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

/// OS가 예약된 시점에 호출하는 모니터.
/// - activity 이름이 순수 UUID → 세션 종료: 해당 세션 shield 해제.
/// - activity 이름이 "<UUID>|relock" → 간주(점프) 종료: 풀 차단 복원.
///   앱이 정지·종료돼 메모리 타이머가 죽어도 OS가 깨어나 재잠금을 보장한다.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    /// 메인 앱 ActivityScheduler.relockSuffix와 동일해야 한다.
    private static let relockSuffix = "|relock"

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let raw = activity.rawValue

        // 간주 종료 → 재잠금
        if raw.hasSuffix(Self.relockSuffix) {
            let idString = String(raw.dropLast(Self.relockSuffix.count))
            guard let sessionId = UUID(uuidString: idString) else { return }
            reapplyFullShield(sessionId: sessionId)
            DeviceActivityCenter().stopMonitoring([activity])
            return
        }

        // 세션 종료 → 해제
        guard let sessionId = UUID(uuidString: raw) else { return }
        let store = ManagedSettingsStore(named: .init(rawValue: sessionId.uuidString))
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil

        // 세션이 끝나면 간주 재잠금 예약·공유 데이터도 함께 정리.
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(raw + Self.relockSuffix)])
        SessionShieldStore.shared.remove(sessionId)

        var ids = ActiveSessionIDStore.shared.allIds()
        ids.removeAll { $0 == sessionId }
        ActiveSessionIDStore.shared.setActiveSessionIds(ids)
    }

    /// App Group에 공유된 세션 선택을 읽어 풀 차단을 복원한다(제외 토큰 없음).
    /// 메인 앱 ManagedSettingsController.applyShield와 동일한 구성.
    private func reapplyFullShield(sessionId: UUID) {
        guard let data = SessionShieldStore.shared.selectionData(for: sessionId),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        let store = ManagedSettingsStore(named: .init(rawValue: sessionId.uuidString))
        let apps = selection.applicationTokens
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: [])
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: [])
    }
}

/// Shield Extension의 것과 동일한 저장소를 사용 (App Group 공유).
/// 별도 타깃이라 코드 공유가 안 돼서 중복 정의.
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

    func setActiveSessionIds(_ ids: [UUID]) {
        defaults?.set(ids.map(\.uuidString), forKey: key)
    }
}

/// 메인 앱 SessionShieldStore와 동일한 App Group 저장소(읽기 전용 + 정리).
/// 별도 타깃이라 코드 공유가 안 돼서 중복 정의.
final class SessionShieldStore {
    static let shared = SessionShieldStore()
    static let appGroupId = "group.hime.app.todolock"
    private let key = "sessionSelections"

    private var defaults: UserDefaults? { UserDefaults(suiteName: Self.appGroupId) }

    func selectionData(for sessionId: UUID) -> Data? {
        (defaults?.dictionary(forKey: key) as? [String: Data])?[sessionId.uuidString]
    }

    func remove(_ sessionId: UUID) {
        var m = (defaults?.dictionary(forKey: key) as? [String: Data]) ?? [:]
        m[sessionId.uuidString] = nil
        defaults?.set(m, forKey: key)
    }
}
