import Foundation
import SwiftData
import FamilyControls
import ManagedSettings

enum SessionStartError: Error {
    case appAlreadyLocked
    case schedulingFailed(Error)
}

/// 활성 세션 라이프사이클 관리.
@MainActor
final class SessionStore {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func activeSessions() -> [Session] {
        let now = Date()
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.endsAt > now },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func session(id: UUID) -> Session? {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    /// 이미 활성 세션 중에 잠겨있는 ApplicationToken 집합.
    func lockedAppTokens() -> Set<ApplicationToken> {
        var result: Set<ApplicationToken> = []
        for s in activeSessions() {
            result.formUnion(s.selection.applicationTokens)
        }
        return result
    }

    func start(
        endsAt: Date,
        selection: FamilyActivitySelection,
        passDurationMinutes: Int
    ) throws -> Session {
        // 과업은 잠긴 앱을 열 때 전역 풀에서 골라 수행한다. 세션 자체엔 과업이 묶이지 않는다.
        let conflict = lockedAppTokens().intersection(selection.applicationTokens)
        guard conflict.isEmpty else { throw SessionStartError.appAlreadyLocked }

        let session = Session(
            endsAt: endsAt,
            selection: selection,
            passDurationMinutes: passDurationMinutes
        )
        modelContext.insert(session)
        try modelContext.save()

        ManagedSettingsController.shared.applyShield(for: session.id, selection: selection)
        // 간주 종료 시 익스텐션이 풀 차단을 복원할 수 있도록 선택을 App Group에 공유.
        SessionShieldStore.shared.setSelectionData(session.appTokensData, for: session.id)

        do {
            try ActivityScheduler.shared.schedule(sessionId: session.id, endsAt: endsAt)
        } catch {
            ManagedSettingsController.shared.clearShield(for: session.id)
            SessionShieldStore.shared.remove(session.id)
            modelContext.delete(session)
            try? modelContext.save()
            throw SessionStartError.schedulingFailed(error)
        }

        ActiveSessionIDStore.shared.add(session.id)
        return session
    }

    /// 세션이 자연 만료됐을 때 정리. DeviceActivityMonitor의 intervalDidEnd에서 호출.
    func finalize(sessionId: UUID) {
        ManagedSettingsController.shared.clearShield(for: sessionId)
        ActivityScheduler.shared.cancel(sessionId: sessionId)
        ActivityScheduler.shared.cancelRelock(sessionId: sessionId)
        ActiveSessionIDStore.shared.remove(sessionId)
        SessionShieldStore.shared.remove(sessionId)

        let descriptor = FetchDescriptor<TempUnlock>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        if let unlocks = try? modelContext.fetch(descriptor) {
            for u in unlocks { modelContext.delete(u) }
        }
        try? modelContext.save()
    }

    func recordAttempt(_ session: Session) {
        session.attemptCount += 1
        try? modelContext.save()
    }

    func recordPass(_ session: Session) {
        session.passCount += 1
        try? modelContext.save()
    }
}
