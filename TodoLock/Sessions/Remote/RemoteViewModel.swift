import SwiftUI
import FamilyControls

/// 리모컨 화면의 작업 상태. SwiftData 접근은 뷰가 담당하고, 여기선 입력/표시 상태만 다룬다.
@MainActor
final class RemoteViewModel: ObservableObject {
    /// 오른쪽부터 채우는 DDHHMM 입력 버퍼 (최대 6자리). 예: "010230" → 1일 2시간 30분.
    @Published private(set) var digits: String = ""

    @Published var selection = FamilyActivitySelection()

    /// 통과(점프) 시 풀리는 보너스 시간(분). 모드별로 저장/로드.
    @Published var passDurationMinutes: Int = 15

    /// 현재 로드된 프리셋(공부모드 등). 선택 표시용.
    @Published var activePresetID: UUID?

    private let maxDigits = 6
    private let maxDays = 99

    /// iOS 스크린타임(DeviceActivity) 스케줄이 허용하는 최소 길이(분).
    /// 이보다 짧으면 startMonitoring이 "schedule is too short"로 예약을 거부하므로,
    /// 시작 버튼 자체를 막아 실패 알림이 뜨지 않게 한다.
    static let minLockMinutes = 15

    // MARK: - 표시

    /// 6자리로 0채운 DDHHMM. 비어 있으면 000000.
    private var paddedDigits: String {
        String(repeating: "0", count: max(0, maxDigits - digits.count)) + digits
    }

    /// 디스플레이용 '일' 2자리(00~99).
    var daysString: String { String(paddedDigits.prefix(2)) }

    /// 디스플레이용 '시' 2자리(00~23).
    var hoursString: String {
        let s = paddedDigits
        return String(s[s.index(s.startIndex, offsetBy: 2)..<s.index(s.startIndex, offsetBy: 4)])
    }

    /// 디스플레이용 '분' 2자리(00~59).
    var minutesString: String { String(paddedDigits.suffix(2)) }

    /// 입력값을 초로 환산. DD*86400 + HH*3600 + MM*60.
    var totalSeconds: Int {
        let dd = Int(daysString) ?? 0
        let hh = Int(hoursString) ?? 0
        let mm = Int(minutesString) ?? 0
        return dd * 86400 + hh * 3600 + mm * 60
    }

    /// 입력된 '분' 자리(뒤 2자리). 60 이상이면 잘못된 시간.
    var minutesField: Int { Int(minutesString) ?? 0 }

    /// 입력된 '시' 자리(가운데 2자리).
    var hoursField: Int { Int(hoursString) ?? 0 }

    /// 분 0~59, 시 0~23 범위여야 잠글 수 있는(유효한) 시간.
    var isValidTime: Bool { minutesField < 60 && hoursField < 24 }

    /// 스크린타임 최소 길이(15분)를 채웠는지. 못 채우면 예약이 거부된다.
    var meetsMinimumDuration: Bool { totalSeconds >= Self.minLockMinutes * 60 }

    /// 시작할 수 없는 이유. 시작 가능하면 nil. (막힌 버튼을 눌렀을 때 안내용)
    /// canStart 와 같은 조건을 같은 순서로 점검한다.
    var startBlockReason: String? {
        guard !canStart else { return nil }
        if !isValidTime { return "시간을 올바르게 입력해주세요" }
        if !meetsMinimumDuration { return "최소 \(Self.minLockMinutes)분부터 시작할 수 있어요" }
        #if !targetEnvironment(simulator)
        if !hasAppSelection { return "잠글 앱을 먼저 선택해주세요" }
        #endif
        return nil
    }

    /// 앱·카테고리·웹도메인 중 무엇이든 하나라도 골랐는지.
    /// (개별 앱이 아니라 카테고리만 골라도 잠금 대상으로 인정)
    var hasAppSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }

    /// 과업은 선택사항. 시간이 유효하고(분 0~59) 최소 15분 이상이며, 잠글 대상이 있으면 시작 가능.
    var canStart: Bool {
        #if targetEnvironment(simulator)
        // 시뮬레이터는 앱 선택(FamilyActivityPicker)이 동작하지 않으므로
        // 화면 흐름만 미리 볼 수 있도록 시간 조건만 본다. 실기기 빌드엔 미포함.
        return meetsMinimumDuration && isValidTime
        #else
        return meetsMinimumDuration && isValidTime && hasAppSelection
        #endif
    }

    var endsAt: Date { Date().addingTimeInterval(TimeInterval(totalSeconds)) }

    // MARK: - 숫자 입력

    func pushDigit(_ d: Int) {
        guard (0...9).contains(d) else { return }
        // 6자리 롤링 레지스터(DDHHMM): 기존 값이 있어도 항상 오른쪽 끝에 새 숫자를 붙이고,
        // 6자리를 넘치면 맨 앞을 버린다. 즉 뒤에서부터 밀려 들어온다.
        // (모드는 항상 하나 선택 상태 유지 — 숫자로 시간만 바꿔도 선택은 풀지 않는다.)
        digits = String((digits + String(d)).suffix(maxDigits))
    }

    func back() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    func clear() {
        digits = ""
    }

    /// LED를 지정한 초로 맞춘다(마지막 사용 시간 복원 등). 0~최대 범위로 클램프.
    func setDuration(_ seconds: Int) {
        setSeconds(seconds)
    }

    // MARK: - 시간 ▲▼ (1분 단위)

    private var maxTotalSeconds: Int { maxDays * 86400 + 23 * 3600 + 59 * 60 }

    func bumpMinutes(_ delta: Int) {
        let clamped = min(maxTotalSeconds, max(0, totalSeconds + delta * 60))
        setSeconds(clamped)
    }

    private func setSeconds(_ seconds: Int) {
        let s = max(0, min(maxTotalSeconds, seconds))
        let dd = min(maxDays, s / 86400)
        let hh = (s % 86400) / 3600
        let mm = (s % 3600) / 60
        digits = String(format: "%02d%02d%02d", dd, hh, mm)
    }

    // MARK: - 프리셋

    func load(_ preset: SessionPreset) {
        setSeconds(preset.durationSeconds)
        selection = preset.selection
        passDurationMinutes = preset.passDurationMinutes
        activePresetID = preset.id
    }

    /// 현재 입력 상태를 프리셋에 다시 저장(앱·시간 수정 후 유지용). 저장은 호출부에서.
    func applyToPreset(_ preset: SessionPreset) {
        preset.durationSeconds = totalSeconds
        preset.selection = selection
        preset.passDurationMinutes = passDurationMinutes
    }
}
