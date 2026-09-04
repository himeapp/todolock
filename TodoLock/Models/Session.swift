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

    /// 이 세션의 곡 제목(=시작한 곡의 displayTitle). 위젯·Live Activity·다이내믹 아일랜드에
    /// 곡명으로 노출한다. 비어 있으면 표시 측에서 자동 발라드 제목으로 대체한다.
    var title: String = ""

    /// 이 세션의 짧은 별칭(=시작한 곡의 preset.name). 다이내믹 아일랜드 컴팩트처럼
    /// 좁은 곳에 곡 제목 대신 짧게 보여줄 때 쓴다. 비면 표시 측에서 곡 제목으로 대체.
    var nickname: String = ""

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
        passDurationMinutes: Int,
        title: String = "",
        nickname: String = ""
    ) {
        self.id = id
        self.createdAt = Date()
        self.endsAt = endsAt
        self.passDurationMinutes = passDurationMinutes
        self.title = title
        self.nickname = nickname
        self.appTokensData = (try? JSONEncoder().encode(selection)) ?? Data()
        self.passCount = 0
        self.attemptCount = 0
    }
}
