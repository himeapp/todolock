import Foundation
import ActivityKit

// 앱 ↔ 위젯/Live Activity 공유 모델.
// 이 파일은 메인 앱 타깃과 위젯 익스텐션 타깃 양쪽에서 함께 컴파일된다.

// MARK: - 홈 위젯이 App Group으로 읽어가는 진행중 세션 스냅샷

struct LockWidgetState: Codable {
    var startedAt: Date     // 세션 시작(가사 시계 기준점)
    var endsAt: Date        // 잠금 종료 시각
    var appCount: Int       // 잠근 앱 수
    var songTitle: String   // 배정된 이별노래 제목
    var lyrics: [String]    // 완창 가사(한 줄씩)
    var isPaused: Bool = false  // 간주(임시 해제) 중 여부

    var isActive: Bool { Date() < endsAt }
}

// MARK: - 감시(watchdog) 중 스냅샷

/// 감시 모드가 걸려 있을 때 홈 위젯이 읽어가는 스냅샷.
/// (감시 = 잠금과 별개로 하루 사용 한도를 지켜보는 규칙)
struct WatchdogWidgetState: Codable {
    var appCount: Int            // 감시 대상 앱 수
    var dailyLimitMinutes: Int   // 하루 한도(분)
    var startedAt: Date          // 감시를 건 시각
}

// MARK: - App Group 다리

enum LockWidgetBridge {
    static let appGroup = "group.hime.app.todolock"
    static let key = "activeLockState"
    static let watchdogKey = "activeWatchdogState"
    /// 감시를 켜뒀던 누적 "날 수"(달력일 기준). 감시를 끌 때 그동안의 일수를 여기에 더한다.
    static let watchdogDaysKey = "watchdogCumulativeDays"

    /// 가사 한 줄이 머무는 시간(초). 노래방 자막 호흡.
    static let lineCadence: TimeInterval = 14

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func write(_ state: LockWidgetState) {
        guard let d = defaults, let data = try? JSONEncoder().encode(state) else { return }
        d.set(data, forKey: key)
    }

    static func clear() { defaults?.removeObject(forKey: key) }

    static func read() -> LockWidgetState? {
        guard let data = defaults?.data(forKey: key),
              let s = try? JSONDecoder().decode(LockWidgetState.self, from: data) else { return nil }
        return s
    }

    static func writeWatchdog(_ state: WatchdogWidgetState) {
        guard let d = defaults, let data = try? JSONEncoder().encode(state) else { return }
        d.set(data, forKey: watchdogKey)
    }

    static func clearWatchdog() { defaults?.removeObject(forKey: watchdogKey) }

    static func readWatchdog() -> WatchdogWidgetState? {
        guard let data = defaults?.data(forKey: watchdogKey),
              let s = try? JSONDecoder().decode(WatchdogWidgetState.self, from: data) else { return nil }
        return s
    }

    /// `from`~`to`가 걸친 달력일 수(시작일 포함). 예: 같은 날이면 1.
    private static func calendarDaysInclusive(from: Date, to: Date) -> Int {
        let cal = Calendar.current
        let span = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: from),
                                      to: cal.startOfDay(for: to)).day ?? 0
        return max(1, span + 1)
    }

    /// 감시를 끌 때 호출 — 지금 켜져 있던 기간의 날 수를 누적 합계에 더한다.
    /// (clearWatchdog 보다 먼저 불러야 한다. 활성 감시가 없으면 아무 것도 안 함)
    static func foldWatchdogDays() {
        guard let d = defaults, let s = readWatchdog() else { return }
        let span = calendarDaysInclusive(from: s.startedAt, to: Date())
        d.set(d.integer(forKey: watchdogDaysKey) + span, forKey: watchdogDaysKey)
    }

    /// 지금까지 감시한 누적 날 수 = 끝난 기간들의 합 + 현재 켜져 있는 기간.
    static func watchdogTotalDays() -> Int {
        let stored = defaults?.integer(forKey: watchdogDaysKey) ?? 0
        guard let s = readWatchdog() else { return stored }
        return stored + calendarDaysInclusive(from: s.startedAt, to: Date())
    }

    /// 노래가 끊기지 않게 가사를 도는 현재 줄 인덱스.
    static func lineIndex(at date: Date, startedAt: Date, lineCount: Int) -> Int {
        guard lineCount > 0 else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return Int(elapsed / lineCadence) % lineCount
    }
}

// MARK: - Live Activity 속성

struct LockActivityAttributes: ActivityAttributes {
    /// 세션 내내 고정되는 값(가사·제목·앱 수)은 정적 속성에 둔다.
    var songTitle: String
    /// 짧은 별칭 — 컴팩트 다이내믹 아일랜드처럼 좁은 곳에 곡 제목 대신 짧게 보여준다.
    var nickname: String = ""
    var lyrics: [String]
    var appCount: Int
    /// "점수 제거"가 켜져 있는지(세션 시작 시점 기준). 켜져 있으면 완료 시 점수 대신
    /// 차분한 완주 표시를 보여준다.
    var hideScore: Bool = false

    /// 시간에 따라 바뀌는 값.
    public struct ContentState: Codable, Hashable {
        var endsAt: Date
        var startedAt: Date
        var lineIndex: Int    // 앱이 포그라운드일 때 갱신해 가사를 넘긴다.
        var isPaused: Bool     // 간주(임시 해제) 중 여부
    }
}

extension Array {
    /// 인덱스 안전 접근.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
