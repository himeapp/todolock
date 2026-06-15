import SwiftUI
import FamilyControls

/// 리모컨이 잠금/감시 어느 용도로 동작 중인지. 같은 LED·숫자패드·시작 버튼을
/// 모드에 따라 재사용한다. (감시는 별도 시트가 아니라 리모컨의 한 "모드")
enum RemoteMode { case lock, watchdog }

/// 리모컨 화면의 작업 상태. SwiftData 접근은 뷰가 담당하고, 여기선 입력/표시 상태만 다룬다.
@MainActor
final class RemoteViewModel: ObservableObject {
    /// 오른쪽부터 채우는 DDHHMM 입력 버퍼 (최대 6자리). 예: "010230" → 1일 2시간 30분.
    @Published private(set) var digits: String = ""

    @Published var selection = FamilyActivitySelection()

    /// 현재 모드. 감시 키로 토글한다. 잠금 입력(digits/selection)과 감시 입력
    /// (watchdogDigits/watchdogSelection)은 서로 독립이라 모드를 오가도 값이 보존된다.
    @Published var mode: RemoteMode = .lock

    /// 감시 대상 앱(잠글 앱과 별개의 독립 규칙).
    @Published var watchdogSelection = FamilyActivitySelection()

    /// 감시 하루 한도를 담는 HHMM 4자리 롤링 버퍼. 기본 02:00(2시간).
    @Published private(set) var watchdogDigits: String = "0200"

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

    // MARK: - 감시 모드 표시/검증 (HHMM, 하루 한도)

    /// 감시 한도 최소(분)·최대(시간). 너무 짧으면 의미가 없고, 하루 한도라 12시간을 상한으로.
    static let minWatchdogMinutes = 30
    static let maxWatchdogHours = 12

    /// 4자리로 0채운 HHMM. 비어 있으면 0000.
    private var paddedWatchdogDigits: String {
        String(repeating: "0", count: max(0, 4 - watchdogDigits.count)) + watchdogDigits
    }

    /// 감시 LED용 '시' 2자리.
    var watchdogHoursString: String { String(paddedWatchdogDigits.prefix(2)) }
    /// 감시 LED용 '분' 2자리.
    var watchdogMinutesString: String { String(paddedWatchdogDigits.suffix(2)) }

    private var watchdogHoursField: Int { Int(watchdogHoursString) ?? 0 }
    private var watchdogMinutesField: Int { Int(watchdogMinutesString) ?? 0 }

    /// 감시 한도(초).
    var watchdogTotalSeconds: Int { watchdogHoursField * 3600 + watchdogMinutesField * 60 }

    /// 분 0~59, 시 0~12 범위여야 유효.
    var watchdogValidTime: Bool {
        watchdogMinutesField < 60 && watchdogHoursField <= Self.maxWatchdogHours
    }
    /// 최소 한도(30분)를 채웠는지.
    var watchdogMeetsMinimum: Bool { watchdogTotalSeconds >= Self.minWatchdogMinutes * 60 }

    /// 감시 대상이 하나라도 골라졌는지.
    var watchdogHasSelection: Bool {
        !watchdogSelection.applicationTokens.isEmpty ||
        !watchdogSelection.categoryTokens.isEmpty ||
        !watchdogSelection.webDomainTokens.isEmpty
    }

    /// 감시를 걸 수 있는지. (시뮬레이터는 앱 선택이 동작하지 않아 시간 조건만 본다)
    var canSaveWatchdog: Bool {
        #if targetEnvironment(simulator)
        return watchdogValidTime && watchdogMeetsMinimum
        #else
        return watchdogValidTime && watchdogMeetsMinimum && watchdogHasSelection
        #endif
    }

    /// 감시를 걸 수 없는 이유. 가능하면 nil. (막힌 버튼을 눌렀을 때 안내용)
    var watchdogBlockReason: String? {
        guard !canSaveWatchdog else { return nil }
        if !watchdogValidTime { return "시간을 올바르게 입력해주세요" }
        if !watchdogMeetsMinimum { return "한도는 최소 \(Self.minWatchdogMinutes)분부터 정할 수 있어요" }
        #if !targetEnvironment(simulator)
        if !watchdogHasSelection { return "감시할 앱을 먼저 선택해주세요" }
        #endif
        return nil
    }

    // MARK: - 숫자 입력 (모드에 따라 잠금/감시 버퍼로 라우팅)

    func pushDigit(_ d: Int) {
        guard (0...9).contains(d) else { return }
        // 롤링 레지스터: 항상 오른쪽 끝에 붙이고, 자릿수를 넘치면 맨 앞을 버린다.
        // (모드는 항상 하나 선택 상태 유지 — 숫자로 시간만 바꿔도 선택은 풀지 않는다.)
        switch mode {
        case .lock:
            digits = String((digits + String(d)).suffix(maxDigits))
        case .watchdog:
            watchdogDigits = String((watchdogDigits + String(d)).suffix(4))
        }
    }

    func back() {
        switch mode {
        case .lock:
            guard !digits.isEmpty else { return }
            digits.removeLast()
        case .watchdog:
            guard !watchdogDigits.isEmpty else { return }
            watchdogDigits.removeLast()
        }
    }

    func clear() {
        switch mode {
        case .lock: digits = ""
        case .watchdog: watchdogDigits = ""
        }
    }

    /// LED를 지정한 초로 맞춘다(마지막 사용 시간 복원 등). 0~최대 범위로 클램프.
    func setDuration(_ seconds: Int) {
        setSeconds(seconds)
    }

    // MARK: - 시간 ▲▼ (1분 단위)

    private var maxTotalSeconds: Int { maxDays * 86400 + 23 * 3600 + 59 * 60 }

    func bumpMinutes(_ delta: Int) {
        switch mode {
        case .lock:
            setSeconds(min(maxTotalSeconds, max(0, totalSeconds + delta * 60)))
        case .watchdog:
            let maxWatchdog = Self.maxWatchdogHours * 3600
            setWatchdogSeconds(min(maxWatchdog, max(0, watchdogTotalSeconds + delta * 60)))
        }
    }

    private func setSeconds(_ seconds: Int) {
        let s = max(0, min(maxTotalSeconds, seconds))
        let dd = min(maxDays, s / 86400)
        let hh = (s % 86400) / 3600
        let mm = (s % 3600) / 60
        digits = String(format: "%02d%02d%02d", dd, hh, mm)
    }

    private func setWatchdogSeconds(_ seconds: Int) {
        let s = max(0, min(Self.maxWatchdogHours * 3600, seconds))
        watchdogDigits = String(format: "%02d%02d", s / 3600, (s % 3600) / 60)
    }

    // MARK: - 프리셋

    func load(_ preset: SessionPreset) {
        // 모드를 고르는 건 잠금 의도 — 감시 모드 중이었다면 잠금으로 되돌린다.
        mode = .lock
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
