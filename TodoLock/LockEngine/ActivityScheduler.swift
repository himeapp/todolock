import Foundation
import DeviceActivity
import FamilyControls

/// 세션의 시작/종료 시점을 OS에 예약. DeviceActivityMonitor extension이 콜백 받음.
final class ActivityScheduler {
    static let shared = ActivityScheduler()

    private let center = DeviceActivityCenter()

    func schedule(sessionId: UUID, endsAt: Date) throws {
        let now = Date()
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: endsAt)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        let activityName = DeviceActivityName(sessionId.uuidString)
        try center.startMonitoring(activityName, during: schedule)
    }

    func cancel(sessionId: UUID) {
        center.stopMonitoring([DeviceActivityName(sessionId.uuidString)])
    }

    // MARK: - 간주(점프) 재잠금 예약

    /// 메인 세션과 구분되는 재잠금 전용 activity 이름 접미사.
    /// intervalDidEnd에서 이 접미사로 "세션 종료(해제)"와 "간주 종료(재잠금)"를 구분한다.
    static let relockSuffix = "|relock"

    private func relockName(_ sessionId: UUID) -> DeviceActivityName {
        DeviceActivityName(sessionId.uuidString + Self.relockSuffix)
    }

    /// 간주 종료 시각(relockAt)에 OS가 깨어나 차단을 복원하도록 예약한다.
    /// 앱이 정지·종료돼 메모리 타이머가 죽어도 재잠금이 보장된다.
    /// (DeviceActivity 최소 간격 15분 — 점프 시간이 그보다 짧으면 예약이 거부될 수 있다.)
    func scheduleRelock(sessionId: UUID, relockAt: Date) throws {
        let now = Date()
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: relockAt)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        try center.startMonitoring(relockName(sessionId), during: schedule)
    }

    func cancelRelock(sessionId: UUID) {
        center.stopMonitoring([relockName(sessionId)])
    }

    // MARK: - 감시(watchdog) 하루 한도

    /// 감시 전용 activity 이름. 익스텐션이 이 이름으로 한도 도달/일일 리셋을 구분한다.
    static let watchdogActivityName = DeviceActivityName("watchdog")
    /// 한도 도달 이벤트 이름.
    static let watchdogEventName = DeviceActivityEvent.Name("watchdog.dailyLimit")

    /// 고른 앱에 "하루 사용 한도"를 건다.
    /// 매일 0:00~23:59 반복 스케줄에 사용량 임계(threshold) 이벤트를 등록 →
    /// 한도를 넘기는 순간 익스텐션 eventDidReachThreshold가 호출돼 그 앱들을 차단한다.
    /// (자정에 intervalDidStart가 다시 와서 차단이 풀리며 한도가 리셋된다.)
    func scheduleWatchdog(selection: FamilyActivitySelection, limitMinutes: Int) throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: limitMinutes)
        )
        // 한도 도달 시 익스텐션이 shield를 걸 수 있도록 감시 선택을 App Group에 공유.
        WatchdogShareStore.shared.setSelection(selection, limitMinutes: limitMinutes)
        // 기존 감시가 있다면 새 설정으로 덮어쓴다.
        center.stopMonitoring([Self.watchdogActivityName])
        try center.startMonitoring(
            Self.watchdogActivityName,
            during: schedule,
            events: [Self.watchdogEventName: event]
        )
    }

    /// 감시 해제 — 모니터링 중단 + 공유 데이터 정리.
    func cancelWatchdog() {
        center.stopMonitoring([Self.watchdogActivityName])
        WatchdogShareStore.shared.clear()
    }
}
