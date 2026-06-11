import Foundation
import SwiftData
import FamilyControls

/// 리모컨 홈 화면의 모드 버튼(공부모드·출근길·잘때 등).
/// 각자 제목·시간·잠글 앱·잠금해제 과업을 저장해두고, 누르면 리모컨에 한 번에 로드된다.
@Model
final class SessionPreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var durationSeconds: Int

    var appTokensData: Data

    var passDurationMinutes: Int

    var orderIndex: Int

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

    init(
        id: UUID = UUID(),
        name: String,
        durationSeconds: Int,
        selection: FamilyActivitySelection = FamilyActivitySelection(),
        passDurationMinutes: Int = 15,
        orderIndex: Int
    ) {
        self.id = id
        self.name = name
        self.durationSeconds = durationSeconds
        self.appTokensData = (try? JSONEncoder().encode(selection)) ?? Data()
        self.passDurationMinutes = passDurationMinutes
        self.orderIndex = orderIndex
    }

    /// 기본 시드 모드 2개. 앱/과업/시간은 모드 설정 팝업(선택된 모드 다시 탭)에서 채운다.
    /// 모드1이 기본 선택값. (3번째 자리는 모드가 아니라 "감시" 기능 버튼이 차지한다)
    static func seeds() -> [SessionPreset] {
        [
            SessionPreset(name: "모드1", durationSeconds: 60 * 60, orderIndex: 0),
            SessionPreset(name: "모드2", durationSeconds: 60 * 60, orderIndex: 1)
        ]
    }
}
