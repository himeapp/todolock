import Foundation
import ActivityKit
import WidgetKit

// Live Activity + 홈 위젯 상태를 관리한다.
//
// 로컬(서버 푸시 없음) Live Activity의 한계상 백그라운드에서 가사를 자동으로 넘기거나
// 종료를 감지할 수 없다. 그래서:
//  - 시작: 세션 start()에서 request
//  - 가사 넘김: 앱이 포그라운드일 때 ticker가 refreshLine() 호출
//  - 종료/정리: 앱이 활성화될 때마다 reconcile()로 만료 세션 정리 + 활성 세션 보장
@available(iOS 16.1, *)
@MainActor
enum LiveActivityController {

    /// 세션 시작 — Live Activity를 띄우고 홈 위젯 상태를 공유한다.
    static func start(session: Session) {
        let song = karaokeSong(for: session)
        let lyrics = song.lines
        let appCount = session.selection.applicationTokens.count
        // 곡 제목 = 사용자가 정한 곡명(session.title). 비어 있으면 자동 발라드 제목으로 대체.
        // (가사는 곡명과 무관하게 늘 이별 발라드 메들리를 쓴다.)
        let displayTitle = session.title.trimmingCharacters(in: .whitespaces).isEmpty
            ? song.title : session.title
        // 별칭 = 사용자가 정한 짧은 곡 별칭. 비어 있으면 곡 제목으로 대체(컴팩트에서 쓴다).
        let nickname = session.nickname.trimmingCharacters(in: .whitespaces).isEmpty
            ? displayTitle : session.nickname
        // "점수 제거" 토글(@AppStorage = 표준 UserDefaults). 완료 축하 점수 노출 여부.
        let hideScore = UserDefaults.standard.bool(forKey: "hideKaraokeScore")

        // 홈 위젯이 읽어갈 스냅샷 공유 + 타임라인 갱신.
        LockWidgetBridge.write(LockWidgetState(
            startedAt: session.createdAt,
            endsAt: session.endsAt,
            appCount: appCount,
            songTitle: displayTitle,
            lyrics: lyrics
        ))
        WidgetCenter.shared.reloadAllTimelines()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // 이미 떠 있는 활동이 있으면 중복 생성하지 않는다.
        guard currentActivity(for: session.id) == nil else { return }

        let attributes = LockActivityAttributes(
            songTitle: displayTitle, nickname: nickname, lyrics: lyrics,
            appCount: appCount, hideScore: hideScore
        )
        let state = LockActivityAttributes.ContentState(
            endsAt: session.endsAt, startedAt: session.createdAt, lineIndex: 0, isPaused: false
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: session.endsAt),
                pushType: nil
            )
        } catch {
            // 권한·예산 문제로 실패해도 홈 위젯은 동작하므로 조용히 넘어간다.
        }
    }

    /// 앱 포그라운드에서 호출 — 시각에 맞는 가사 줄로 넘기고, 간주 상태를 반영한다.
    static func refreshLine(isPaused: Bool = false) {
        var pauseChanged = false
        for activity in Activity<LockActivityAttributes>.activities {
            let st = activity.content.state
            let idx = LockWidgetBridge.lineIndex(
                at: Date(), startedAt: st.startedAt, lineCount: activity.attributes.lyrics.count
            )
            guard idx != st.lineIndex || isPaused != st.isPaused else { continue }
            if isPaused != st.isPaused { pauseChanged = true }
            var ns = st
            ns.lineIndex = idx
            ns.isPaused = isPaused
            Task { await activity.update(.init(state: ns, staleDate: st.endsAt)) }
        }
        // 간주 상태가 바뀌면 홈 위젯 타임라인도 갱신해 "간주 점프 중" 표시를 즉시 반영한다.
        if pauseChanged, var state = LockWidgetBridge.read() {
            state.isPaused = isPaused
            LockWidgetBridge.write(state)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 활성 세션 목록과 Live Activity를 맞춘다 — 만료된 건 종료, 새 세션은 시작.
    static func reconcile(activeSessions: [Session]) {
        let activeIDs = Set(activeSessions.map(\.id))

        // 만료/사라진 세션의 활동 종료.
        for activity in Activity<LockActivityAttributes>.activities {
            let stillActive = activeSessions.contains { $0.endsAt > Date() && matches(activity, $0) }
            if !stillActive {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }

        // 가장 늦게 끝나는 활성 세션 하나만 위젯/활동에 반영(여러 개여도 대표 1개).
        if let primary = activeSessions.filter({ $0.endsAt > Date() }).max(by: { $0.endsAt < $1.endsAt }) {
            start(session: primary)   // 내부에서 중복 방지
        } else {
            LockWidgetBridge.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }
        _ = activeIDs
    }

    /// 모든 활동 종료(전체 정리용).
    static func endAll() {
        for activity in Activity<LockActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        LockWidgetBridge.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 내부

    private static func currentActivity(for sessionId: UUID) -> Activity<LockActivityAttributes>? {
        Activity<LockActivityAttributes>.activities.first
    }

    /// 세션과 활동이 같은 것인지(시작 시각으로 식별).
    private static func matches(_ activity: Activity<LockActivityAttributes>, _ session: Session) -> Bool {
        abs(activity.content.state.startedAt.timeIntervalSince(session.createdAt)) < 1
    }
}
