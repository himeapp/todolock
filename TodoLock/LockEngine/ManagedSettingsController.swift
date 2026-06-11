import Foundation
import ManagedSettings
import FamilyControls

/// 세션 단위로 별도의 ManagedSettingsStore를 사용해서 세션 간 격리.
/// store 이름은 세션 UUID와 동일.
final class ManagedSettingsController {
    static let shared = ManagedSettingsController()

    private func store(for sessionId: UUID) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init(rawValue: sessionId.uuidString))
    }

    func applyShield(for sessionId: UUID, selection: FamilyActivitySelection, except excluded: Set<ApplicationToken> = []) {
        let s = store(for: sessionId)
        let apps = selection.applicationTokens.subtracting(excluded)
        s.shield.applications = apps.isEmpty ? nil : apps
        s.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: excluded)
        s.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: [])
    }

    func clearShield(for sessionId: UUID) {
        let s = store(for: sessionId)
        s.shield.applications = nil
        s.shield.applicationCategories = nil
        s.shield.webDomainCategories = nil
    }
}
