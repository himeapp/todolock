import Foundation
import SwiftData
import FamilyControls
import ManagedSettings

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var endsAt: Date
    var passDurationMinutes: Int

    var appTokensData: Data

    var passCount: Int
    var attemptCount: Int

    @Transient
    var selection: FamilyActivitySelection {
        get {
            guard let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: appTokensData) else {
                return FamilyActivitySelection()
            }
            return decoded
        }
        set {
            appTokensData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var isActive: Bool { Date() < endsAt }
    var remaining: TimeInterval { max(0, endsAt.timeIntervalSinceNow) }

    init(
        id: UUID = UUID(),
        endsAt: Date,
        selection: FamilyActivitySelection,
        passDurationMinutes: Int
    ) {
        self.id = id
        self.createdAt = Date()
        self.endsAt = endsAt
        self.passDurationMinutes = passDurationMinutes
        self.appTokensData = (try? JSONEncoder().encode(selection)) ?? Data()
        self.passCount = 0
        self.attemptCount = 0
    }
}
