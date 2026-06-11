import Foundation
import ManagedSettings
import FamilyControls
import SwiftData

/// 과업 완료 시 특정 앱을 임시 해제하고, N분 뒤 다시 잠금.
final class TempUnlockController {
    static let shared = TempUnlockController()

    private var timers: [UUID: Timer] = [:]

    /// 세션에 아직 만료되지 않은 임시 해제가 있으면 그중 가장 늦은 만료 시각을 반환.
    /// (점프 중 재점프를 막기 위한 판단용)
    func activeExpiry(for session: Session, modelContext: ModelContext) -> Date? {
        let sessionId = session.id
        let descriptor = FetchDescriptor<TempUnlock>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        let unlocks = (try? modelContext.fetch(descriptor)) ?? []
        return unlocks.filter { !$0.isExpired }.map(\.expiresAt).max()
    }

    /// 세션의 ManagedSettingsStore에서 unlockToken을 제외시켜 일시 해제.
    /// passDurationMinutes 후 다시 차단.
    func grantTempAccess(
        session: Session,
        unlockToken: ApplicationToken,
        modelContext: ModelContext
    ) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(session.passDurationMinutes) * 60)

        let record = TempUnlock(sessionId: session.id, appToken: unlockToken, expiresAt: expiresAt)
        modelContext.insert(record)
        try? modelContext.save()

        reapplyShield(session: session, modelContext: modelContext)

        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(session.passDurationMinutes) * 60, repeats: false) { [weak self] _ in
            self?.expire(record: record, session: session, modelContext: modelContext)
        }
        timers[record.id] = timer
    }

    /// 간주(임시 해제) 동안엔 잠금 시계가 멈춰야 한다. 종료 시각을 간주 길이만큼 미루고
    /// OS 예약(DeviceActivity)도 다시 잡아, 화면뿐 아니라 실제 잠금도 그만큼 늦게 풀리게 한다.
    /// 한 간주당 한 번만(세션 단위) 호출한다 — 토큰마다 부르면 중복으로 밀린다.
    func extendLockForInterlude(session: Session, modelContext: ModelContext) {
        let passSeconds = TimeInterval(session.passDurationMinutes) * 60
        session.endsAt = session.endsAt.addingTimeInterval(passSeconds)
        try? modelContext.save()
        ActivityScheduler.shared.cancel(sessionId: session.id)
        try? ActivityScheduler.shared.schedule(sessionId: session.id, endsAt: session.endsAt)

        // 핵심: 간주 종료 시 재잠금을 OS에 예약한다. 앱이 정지·종료돼 메모리 타이머가
        // 죽어도, OS가 깨어나 차단을 복원한다. (메모리 타이머는 foreground 즉시 복원용 보조 수단)
        let relockAt = Date().addingTimeInterval(passSeconds)
        try? ActivityScheduler.shared.scheduleRelock(sessionId: session.id, relockAt: relockAt)
    }

    private func expire(record: TempUnlock, session: Session, modelContext: ModelContext) {
        modelContext.delete(record)
        try? modelContext.save()
        timers[record.id] = nil
        reapplyShield(session: session, modelContext: modelContext)
        // foreground에서 타이머가 먼저 재잠갔으면, 중복으로 늦게 울릴 OS 예약은 거둔다.
        if activeExpiry(for: session, modelContext: modelContext) == nil {
            ActivityScheduler.shared.cancelRelock(sessionId: session.id)
        }
    }

    /// 현재 활성인 TempUnlock들을 모아서 제외시키고 shield 재적용.
    func reapplyShield(session: Session, modelContext: ModelContext) {
        let sessionId = session.id
        let descriptor = FetchDescriptor<TempUnlock>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        let unlocks = (try? modelContext.fetch(descriptor)) ?? []

        // 앱이 죽어 있던 사이 만료된 임시 해제 레코드는 정리한다(OS가 이미 재잠금).
        let expired = unlocks.filter { $0.isExpired }
        if !expired.isEmpty {
            for u in expired { modelContext.delete(u) }
            try? modelContext.save()
        }

        let activeTokens = unlocks
            .filter { !$0.isExpired }
            .compactMap { $0.appToken }

        ManagedSettingsController.shared.applyShield(
            for: session.id,
            selection: session.selection,
            except: Set(activeTokens)
        )

        // 익스텐션이 간주 종료 시 풀 차단을 복원할 수 있도록 현재 선택을 공유한다.
        SessionShieldStore.shared.setSelectionData(session.appTokensData, for: session.id)
    }
}
