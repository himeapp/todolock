import SwiftUI
import SwiftData

/// 잠금이 시작된 뒤 보이는 노래방 TV 화면.
/// 개념: "참고 잠겨있는 것 = 노래를 부르는 중". 가사는 앱과 이별한 슬픔(?)을 노래한다.
/// 점프(과업)로 임시 해제가 걸려 있는 동안엔 노래가 "간주 중"으로 잠깐 멈추고,
/// 간주가 끝나면 3·2·1을 센 뒤 멈춘 지점부터 이어 부른다.
struct ActiveLockView: View {
    @ObservedObject private var ticker = Ticker.shared
    let session: Session

    /// 이 세션에 걸린 임시 해제들. (만료되면 컨트롤러가 삭제 → 자동 갱신)
    @Query private var unlocks: [TempUnlock]

    /// 간주(임시 해제) 진행 중인지.
    @State private var inInterlude = false
    /// 간주가 끝난 직후 떠오르는 복귀 카운트(3·2·1). nil이면 카운트 없음.
    @State private var resumeCount: Int? = nil
    @State private var resumeTask: Task<Void, Never>? = nil

    /// 간주로 노래가 멈춰 있던 총 시간 — 가사 시계에서 빼서 멈춘 지점부터 이어지게 한다.
    @State private var pausedTotal: TimeInterval = 0
    /// 지금 멈춰 있는 간주의 시작 시각(멈춘 동안 흐른 시간은 실시간으로 빼준다).
    @State private var pauseStart: Date? = nil

    /// 간주(임시 해제) 동안 멈춰 있던 누적 시간 — 지금 멈춰 있으면 실시간으로 더한다.
    /// 가사 시계와 잠금 게이지를 똑같이 멈춰 두는 데 함께 쓴다.
    private var pauseElapsed: TimeInterval {
        _ = ticker.now
        var e = pausedTotal
        if let start = pauseStart { e += max(0, ticker.now.timeIntervalSince(start)) }
        return e
    }

    /// 지금 간주가 끝날 때까지 남은 시간(간주 아니면 0).
    private var interludeRemaining: TimeInterval {
        guard inInterlude, let end = interludeEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(ticker.now))
    }

    /// 화면에 보여줄 남은 잠금시간. 간주 중엔 그 길이만큼 빼서 시계가 멈춰 보이게 한다.
    /// (잠금 종료 시각은 간주를 부여할 때 그만큼 미뤄 둬서 실제 잠금도 같이 멈춘다.)
    private var displayedRemaining: TimeInterval {
        _ = ticker.now
        return max(0, session.remaining - interludeRemaining)
    }

    private var progress: Double {
        _ = ticker.now
        let elapsed = max(0, ticker.now.timeIntervalSince(session.createdAt) - pauseElapsed)
        let total = elapsed + displayedRemaining
        guard total > 0 else { return 1 }
        return elapsed / total
    }

    /// 잠금 총 시간 (가사에 박을 "이별 기간")
    private var totalDurationText: String {
        let totalMinutes = Int((session.endsAt.timeIntervalSince(session.createdAt) / 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)시간 \(m)분" }
        if h > 0 { return "\(h)시간" }
        return "\(max(1, m))분"
    }

    private var appCount: Int { session.selection.applicationTokens.count }

    /// 지금 살아있는 임시 해제 중 가장 늦게 끝나는 시각. 없으면 nil(=간주 아님).
    private var interludeEndsAt: Date? {
        _ = ticker.now
        let now = ticker.now
        let sessionId = session.id
        return unlocks
            .filter { $0.sessionId == sessionId && $0.expiresAt > now }
            .map(\.expiresAt)
            .max()
    }

    /// 한 줄을 부르고 다음 줄로 올라가는 데 걸리는 시간(초).
    private let secondsPerLine: Double = 3.4

    /// 전 곡 가사를 한 줄씩 이어 붙인 메들리. 곡 순서만 세션마다 같게 섞는다(줄 순서는 보존).
    private var medleyLines: [String] {
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(session.id.hashValue)))
        return karaokeSongs(for: session).shuffled(using: &rng).flatMap { $0.lines }
    }

    /// 곡이 시작된 뒤 흐른 시간을 "흘러간 줄 수"로 환산(정수부=현재 줄, 소수부=진행도).
    /// 간주로 멈춰 있던 시간(pausedTotal + 지금 멈춘 시간)은 빼서 멈춘 지점부터 이어진다.
    private var lyricPosition: Double {
        _ = ticker.now
        let count = medleyLines.count
        guard count > 0 else { return 0 }
        let elapsed = max(0, ticker.now.timeIntervalSince(session.createdAt) - pauseElapsed)
        return (elapsed / secondsPerLine).truncatingRemainder(dividingBy: Double(count))
    }

    var body: some View {
        ZStack {
            KaraokeBackground()

            VStack(alignment: .leading, spacing: 0) {
                NowPlayingBox(
                    tag: inInterlude ? "간주" : "부르는 중",
                    tagColor: inInterlude ? KColor.pink : KColor.green,
                    title: karaokeNumber(session.id),
                    subtitle: inInterlude
                        ? "잠근 앱 잠깐 사용 가능"
                        : "\(appCount)개 앱과 이별 \(totalDurationText)"
                )
                // 상단 노치/세이프에어리어와 안 붙도록 넉넉히(감시 시트 상단 여백과 통일).
                .padding(.top, 20)

                KaraokeGauge(progress: progress, label: remainingString)
                    .padding(.top, 18)

                Spacer(minLength: 24)

                if inInterlude {
                    InterludeView(endsAt: interludeEndsAt ?? ticker.now)
                        .transition(.opacity)
                } else {
                    // 자막(가사) = 이별노래
                    KaraokeLyricScroll(lines: medleyLines, position: lyricPosition, size: 32)
                        .transition(.opacity)
                }
            }
            .padding(22)
            .padding(.bottom, LockDrawerMetrics.collapsedHandleReserve)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay {
            if let n = resumeCount {
                ResumeCountdownOverlay(number: n)
            }
        }
        .onAppear(perform: syncInterludeOnAppear)
        .onChange(of: interludeEndsAt) { old, new in
            handleInterludeChange(old: old, new: new)
        }
        .animation(.easeInOut(duration: 0.35), value: inInterlude)
    }

    private var remainingString: String {
        _ = ticker.now
        let seconds = Int(displayedRemaining)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        // 간주(점프) 중엔 잠금 시간이 멈춰 있으므로 "남음" 대신 "멈춤"으로 표시.
        let suffix = inInterlude ? "멈춤" : "남음"
        if h > 0 { return String(format: "%d:%02d:%02d \(suffix)", h, m, s) }
        return String(format: "%d:%02d \(suffix)", m, s)
    }

    // MARK: - 간주 상태 전이

    /// 화면에 들어올 때 이미 간주 중이면 멈춘 상태로 동기화.
    private func syncInterludeOnAppear() {
        if interludeEndsAt != nil {
            inInterlude = true
            if pauseStart == nil { pauseStart = Date() }
        }
    }

    private func handleInterludeChange(old: Date?, new: Date?) {
        if new != nil {
            // 간주 시작/연장 — 복귀 카운트가 떠 있었다면 거둔다.
            resumeTask?.cancel()
            resumeCount = nil
            if !inInterlude {
                inInterlude = true
                if pauseStart == nil { pauseStart = Date() }
            }
        } else if old != nil {
            // 간주 끝 — 3·2·1 센 뒤 멈춘 지점부터 이어 부른다.
            inInterlude = false
            startResumeCountdown()
        }
    }

    private func startResumeCountdown() {
        resumeTask?.cancel()
        resumeTask = Task { @MainActor in
            for n in [3, 2, 1] {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) { resumeCount = n }
                try? await Task.sleep(nanoseconds: 820_000_000)
                if Task.isCancelled { return }
            }
            withAnimation(.easeOut(duration: 0.25)) { resumeCount = nil }
            // 멈춰 있던 시간을 누적 → 가사가 멈춘 지점부터 이어진다.
            if let start = pauseStart {
                pausedTotal += Date().timeIntervalSince(start)
                pauseStart = nil
            }
        }
    }
}

// MARK: - 간주 중 (임시 해제 동안 노래가 멈춘 화면)

/// 가사 자리를 대신 채우는 "간주 중" 표시. 음표와 함께 크게 띄우고,
/// 그 안에서 간주(임시 해제)가 끝날 때까지 남은 점프 시간을 카운트한다.
private struct InterludeView: View {
    let endsAt: Date
    @ObservedObject private var ticker = Ticker.shared

    private var remainingText: String {
        _ = ticker.now
        let s = max(0, Int(endsAt.timeIntervalSince(ticker.now).rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OutlinedText(text: "♪  간주 중  ♪", size: 28, fill: KColor.cyan, strokeWidth: 4)
                .shadow(color: KColor.cyan.opacity(0.45), radius: 7)

            VStack(alignment: .leading, spacing: 6) {
                Text("이 시간동안 앱 사용을 허락할게요")
                    .font(.led(12))
                    .foregroundStyle(KColor.cyan)
                    .shadow(color: KColor.cyan.opacity(0.5), radius: 5)

                Text(remainingText)
                    .font(.led(40))
                    .foregroundStyle(.white)
                    .shadow(color: KColor.cyan.opacity(0.45), radius: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 복귀 카운트다운 (간주 끝 → 3·2·1 → 이어 부르기)

/// 간주가 끝난 직후 화면을 살짝 덮으며 "이어서 부를게요"와 함께 3·2·1을 띄운다.
private struct ResumeCountdownOverlay: View {
    let number: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("♪  이어서 부를게요  ♪")
                    .font(.led(14))
                    .foregroundStyle(KColor.cyan)
                    .shadow(color: KColor.cyan.opacity(0.7), radius: 8)

                OutlinedText(text: "\(number)", size: 104, fill: KColor.yellow, strokeWidth: 7)
                    .id(number)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.7).combined(with: .opacity),
                        removal: .scale(scale: 0.6).combined(with: .opacity)
                    ))
                    .shadow(color: KColor.yellow.opacity(0.5), radius: 18)
            }
        }
        .transition(.opacity)
    }
}
