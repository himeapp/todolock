import Foundation
import SwiftData
import ManagedSettings

@Model
final class TempUnlock {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var appTokenData: Data
    var unlockedAt: Date
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }

    var appToken: ApplicationToken? {
        try? JSONDecoder().decode(ApplicationToken.self, from: appTokenData)
    }

    init(sessionId: UUID, appToken: ApplicationToken, expiresAt: Date) {
        self.id = UUID()
        self.sessionId = sessionId
        self.appTokenData = (try? JSONEncoder().encode(appToken)) ?? Data()
        self.unlockedAt = Date()
        self.expiresAt = expiresAt
    }
}
