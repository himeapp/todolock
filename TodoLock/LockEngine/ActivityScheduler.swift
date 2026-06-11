import Foundation
import DeviceActivity

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
}
