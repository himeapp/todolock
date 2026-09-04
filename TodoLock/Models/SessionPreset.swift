import Foundation
import SwiftData
import FamilyControls

/// 리모컨 홈 화면의 "곡"(=모드) 버튼. 각 곡은 짧은 별칭(버튼에 노래방 곡번호처럼 표시)과
/// 풀네임(곡 제목), 시간·잠글 앱·잠금해제 과제을 저장해두고, 누르면 리모컨에 한 번에 로드된다.
@Model
final class SessionPreset {
    @Attribute(.unique) var id: UUID
    /// 짧은 별칭 — 버튼에 노래방 곡번호처럼 작게 표시한다. (글자수 제한, 항상 존재)
    var name: String
    /// 곡 풀네임(제목). 비어 있으면 별칭(name)을 대신 쓴다. 확인화면·위젯·Live Activity에 노출.
    var songTitle: String = ""
    var durationSeconds: Int

    var appTokensData: Data

    var passDurationMinutes: Int

    var orderIndex: Int

    /// 곡명으로 보여줄 값 — 풀네임이 있으면 그걸, 없으면 별칭, 둘 다 없으면 "곡 미정".
    var displayTitle: String {
        let t = songTitle.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        let a = name.trimmingCharacters(in: .whitespaces)
        return a.isEmpty ? "곡 미정" : a
    }

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
        songTitle: String = "",
        durationSeconds: Int,
        selection: FamilyActivitySelection = FamilyActivitySelection(),
        passDurationMinutes: Int = 15,
        orderIndex: Int
    ) {
        self.id = id
        self.name = name
        self.songTitle = songTitle
        self.durationSeconds = durationSeconds
        self.appTokensData = (try? JSONEncoder().encode(selection)) ?? Data()
        self.passDurationMinutes = passDurationMinutes
        self.orderIndex = orderIndex
    }

    /// 기본 시드 곡 2개. 앱/과제/시간은 곡 설정 팝업(선택된 곡 다시 탭)에서 채운다.
    /// 1번 곡이 기본 선택값. (3번째 자리는 곡이 아니라 "감시" 기능 버튼이 차지한다)
    static func seeds() -> [SessionPreset] {
        [
            SessionPreset(name: "애창곡", songTitle: "그대 없는 1시간", durationSeconds: 60 * 60, orderIndex: 0),
            SessionPreset(name: "18번", songTitle: "잠시만 안녕", durationSeconds: 60 * 60, orderIndex: 1)
        ]
    }
}
