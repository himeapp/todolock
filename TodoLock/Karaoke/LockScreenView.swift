import SwiftUI
import SwiftData
import FamilyControls

/// 잠금이 활성인 동안 보이는 풀스크린 노래방 TV.
/// 하단에 기본 리모컨 일부를 따온 "잠금 전용 슬림 리모컨"이 늘 놓여 있다(드로어 없음).
/// 잠금 중엔 잠글 앱 "추가"만 가능(남은 시간·기존 잠금은 그대로). 점프는 작은 유혹 버튼일 뿐.
struct LockScreenView: View {
    let session: Session
    @State private var showIntro: Bool
    @State private var showingJump = false
    @State private var showingJumpBlocked = false
    /// 슬림 리모컨의 "잠근 앱" 키 → 잠근 앱 목록(추가 전용) 카드.
    @State private var showingLockedApps = false

    @ObservedObject private var ticker = Ticker.shared
    /// Shield "과제 수행하기" → 푸시 → 탭으로 들어온 딥링크. 잠금 화면이 직접 점프를 연다.
    @ObservedObject private var deepLink = DeepLinkHandler.shared
    /// 이 세션에 걸린 임시 해제들. (만료되면 컨트롤러가 삭제 → 자동 갱신)
    @Query private var unlocks: [TempUnlock]

    init(session: Session) {
        self.session = session
        // 노래방처럼 곡(세션)이 처음 시작될 때 한 번만 인트로를 띄운다.
        _showIntro = State(initialValue: !KaraokeIntroTracker.hasShown(session.id))
    }

    /// 지금 살아있는 점프(간주)의 가장 늦은 만료 시각. 없으면 nil(=점프 가능).
    private var jumpExpiry: Date? {
        _ = ticker.now
        let now = ticker.now
        let sessionId = session.id
        return unlocks
            .filter { $0.sessionId == sessionId && $0.expiresAt > now }
            .map(\.expiresAt)
            .max()
    }

    var body: some View {
        ActiveLockView(session: session)
            .overlay(alignment: .bottom) {
                if !showIntro {
                    LockRemoteBar(
                        session: session,
                        onManage: { showingLockedApps = true },
                        onJump: handleJumpTap
                    )
                }
            }
            .overlay {
                if showIntro {
                    KaraokeIntroView(
                        song: karaokeSong(for: session),
                        number: karaokeNumber(session.id),
                        displayTitle: session.title,
                        onFinish: finishIntro
                    )
                    .transition(.opacity)
                }
            }
            // 점프는 TV 채널 맞추듯 "지지직" 등장하되, 풀스크린이 아니라 위로 잠금 화면이
            // 비치는 큰 카드로 띄운다.
            .glitchReveal(isPresented: $showingJump, dimmed: false) { close in
                TaskPoolSheet(onClose: close, asCard: true)
            }
            // 잠근 앱 목록 — 점프(곡목록)와 같은 카드 톤으로 띄우되, 잠금 중엔 "추가"만 된다.
            .glitchReveal(isPresented: $showingLockedApps, dimmed: false) { close in
                LockedAppsSheet(session: session, onClose: close, asCard: true)
            }
            // 이미 간주 중이면 새 점프를 막고 "지금은 안 돼요"를 같은 톤으로 띄운다.
            .glitchReveal(isPresented: $showingJumpBlocked) { close in
                JumpBlockedNotice(session: session, expiry: jumpExpiry, onClose: close)
            }
            // 푸시(Shield 과제 수행하기)를 탭하면 잠금 화면 위로 곧장 점프(곡목록)를 연다.
            // 잠금 중엔 RemoteControlView의 시트가 이 풀스크린 커버에 가려 안 보이므로
            // 보이는 레이어인 여기서 직접 처리한다.
            .onReceive(deepLink.$pendingSessionId) { id in
                guard id != nil else { return }
                handleJumpTap()
                deepLink.clear()
            }
    }

    /// 점프 키캡 탭 — 이미 간주 중이면 재점프를 막고 안내, 아니면 곡목록을 연다.
    private func handleJumpTap() {
        if jumpExpiry != nil {
            showingJumpBlocked = true
        } else {
            showingJump = true
        }
    }

    private func finishIntro() {
        guard showIntro else { return }
        KaraokeIntroTracker.markShown(session.id)
        withAnimation(.easeInOut(duration: 0.5)) { showIntro = false }
    }
}

// MARK: - 재점프 차단 안내 (이미 간주 중일 때)

/// 이미 간주(점프) 중인데 점프 키캡을 또 누르면 뜨는 안내.
/// 곡목록(TaskPoolSheet)과 똑같이 "지지직" 등장하되, 점프 대신 "지금은 안 돼요"와
/// 간주가 끝날 때까지 남은 시간을 보여주고 다시 부르기 시작하면 점프할 수 있음을 알린다.
private struct JumpBlockedNotice: View {
    let session: Session
    let expiry: Date?
    var onClose: () -> Void

    @ObservedObject private var ticker = Ticker.shared

    private var remainingText: String {
        _ = ticker.now
        guard let expiry else { return "0:00" }
        let s = max(0, Int(expiry.timeIntervalSince(ticker.now).rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        ZStack {
            NeonBlurBackground()

            VStack(spacing: 0) {
                HStack {
                    NowPlayingBox(
                        tag: "간주",
                        tagColor: KColor.pink,
                        title: karaokeNumber(session.id),
                        subtitle: "지금은 점프할 수 없어요"
                    )
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(KColor.pink)
                        .shadow(color: KColor.pink.opacity(0.7), radius: 16)

                    OutlinedText(text: "이미 간주 점프 중이에요", size: 24, fill: .white, alignment: .center)

                    Text("간주가 끝나면 다시 점프할 수 있어요.")
                        .font(.myungjoLight(14))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)

                    VStack(spacing: 4) {
                        Text("남은 점프")
                            .font(.led(12))
                            .foregroundStyle(KColor.cyan)
                            .shadow(color: KColor.cyan.opacity(0.6), radius: 6)
                        Text(remainingText)
                            .font(.led(44))
                            .foregroundStyle(.white)
                            .shadow(color: KColor.cyan.opacity(0.5), radius: 10)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 28)

                Spacer()

                Button { onClose() } label: { Text("알겠어요 ▶") }
                    .buttonStyle(KaraokeButtonStyle(color: KColor.green))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
            }
        }
    }
}

/// 항상 떠있는 슬림 리모컨 바가 화면 하단에서 차지하는 높이.
/// ActiveLockView 본문(가사·안내문)이 이만큼 위로 떠서 바에 가려지지 않게 한다.
enum LockDrawerMetrics {
    static let collapsedHandleReserve: CGFloat = 92
}

// MARK: - 잠금 전용 슬림 리모컨 (항상 떠있는 컴팩트 바)

/// 화면 하단에 늘 놓여 있는 리모컨 바. 드로어/펼침 없이, 기본 리모컨의 크림 보디 위에
/// 빨간 "잠글 앱 관리" 키캡과 작은 초록 "점프" 키캡만 얹었다. 남은 시간은 상단 게이지가 담당.
/// 잠금 중엔 잠글 앱 "추가"만 가능, 점프는 작은 유혹 버튼.
private struct LockRemoteBar: View {
    let session: Session
    /// 빨간 "잠근 앱" 키 → 잠근 앱 목록(추가 전용) 카드를 연다.
    let onManage: () -> Void
    let onJump: () -> Void

    private var appCount: Int { session.selection.applicationTokens.count }

    var body: some View {
        HStack(spacing: 10) {
            // 기본 리모컨의 빨간 "잠근 앱" 키캡 — 누르면 잠근 앱 목록을 열고, 거기서 추가만 된다.
            Button { onManage() } label: {
                manageKey
            }
            .buttonStyle(.plain)

            // 점프는 메인이 아니라 작은 유혹 키캡.
            Button { onJump() } label: {
                jumpKey
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .background {
            // 크림 보디는 홈 인디케이터 영역까지 끊김 없이 내려가야 한다.
            // (클립 후 ignoresSafeArea를 걸면 하단이 툭 잘려 파란 TV 배경이 비친다.)
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(LockRemoteTheme.cream)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                        .stroke(.black.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// 기본 리모컨의 빨간 "잠글 앱 관리" 키캡 — 잠금 앱 수도 함께 보여준다.
    private var manageKey: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.app.dashed")
            Text(appCount == 0 ? "잠글 앱 관리" : "잠근 앱 \(appCount)개")
                .font(.system(size: 18, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 11).fill(
                LinearGradient(colors: [Color(hex: 0xec5743), Color(hex: 0xd23522)],
                               startPoint: .top, endPoint: .bottom)
            )
        )
        .overlay(alignment: .top) { keycapGloss(radius: 11) }
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.black.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }

    /// 초록 "점프" 키캡 — 과제하고 잠깐 풀기. 관리 버튼과 약 2:1 비율로 넉넉히 키운다.
    private var jumpKey: some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .black))
            Text("점프")
                .font(.system(size: 18, weight: .black, design: .rounded))
        }
        .foregroundStyle(Color(hex: 0x0b2606))
        .frame(width: 120)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 11).fill(
                LinearGradient(colors: [Color(hex: 0x74c94f), Color(hex: 0x54a836)],
                               startPoint: .top, endPoint: .bottom)
            )
        )
        .overlay(alignment: .top) { keycapGloss(radius: 11) }
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.black.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }
}

// MARK: - 잠근 앱 목록 (추가 전용)

/// 슬림 리모컨의 "잠근 앱" 키가 여는 카드. 지금 잠근 앱을 곡목록처럼 보여주고,
/// 잠금 중엔 빼기 없이 "더하기"만 허용한다. (예전엔 시스템 피커에 현재 선택을 채워
/// 띄워 빼기가 가능해 보였지만 합집합만 반영돼 "체크 풀고 나오면 그대로"였다.
/// 이제 추가 피커는 빈 선택으로 열어, 기존 잠금은 건드릴 수 없게 한다.)
private struct LockedAppsSheet: View {
    let session: Session
    var onClose: () -> Void
    /// 잠금 화면 위에 띄울 때 true. 풀스크린 대신 위로 잠금 화면이 비치는 둥근 카드로 그린다.
    var asCard: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var showingPicker = false
    /// 추가용 피커는 항상 빈 선택으로 연다 — 기존 잠금은 보이지 않아 뺄 수 없고, 고른 것만 더해진다.
    @State private var addSelection = FamilyActivitySelection()

    private var appCount: Int { session.selection.applicationTokens.count }
    private var categoryCount: Int { session.selection.categoryTokens.count }
    private var webCount: Int { session.selection.webDomainTokens.count }
    private var totalCount: Int { appCount + categoryCount + webCount }

    var body: some View {
        presentationBody
            .familyActivityPicker(isPresented: $showingPicker, selection: $addSelection)
            .onChange(of: showingPicker) { _, isShown in
                if !isShown { commitAddedApps() }
            }
    }

    @ViewBuilder private var presentationBody: some View {
        if asCard {
            VStack(spacing: 0) {
                Spacer(minLength: 10)   // 점프 카드와 같은 작은 상단 여백 — 타이틀은 카드가 덮는다
                ZStack {
                    NeonBlurBackground()
                    content
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            }
            .ignoresSafeArea(edges: .bottom)
        } else {
            ZStack {
                NeonBlurBackground()
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            Group {
                if totalCount == 0 {
                    VStack(spacing: 10) {
                        OutlinedText(text: "아직 잠근 앱이 없어요", size: 20, alignment: .center)
                        Text("아래에서 잠글 앱을 더해보세요")
                            .font(.myungjoLight(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 22)
                } else {
                    KaraokeSongList(selection: session.selection)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                }
            }
            .frame(maxHeight: .infinity)

            // 잠금 중엔 빼기 없이 더하기만 — 키패드 화면과 톤을 맞춘 옅은 안내.
            Text("잠금 중엔 앱을 더하기만 할 수 있어요")
                .font(.myungjoLight(12))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.20))

            Button {
                addSelection = FamilyActivitySelection()   // 항상 빈 선택으로 — 추가만.
                showingPicker = true
            } label: {
                Label("잠글 앱 더하기", systemImage: "plus.circle.fill")
            }
            .buttonStyle(KaraokeButtonStyle(color: KColor.green))
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        HStack {
            NowPlayingBox(
                tag: "잠금",
                tagColor: KColor.pink,
                title: "잠근 앱 \(totalCount)개",
                subtitle: "지금 이별 중인 앱들"
            )
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    /// 잠금 중엔 "추가"만 허용한다: 고른 앱을 기존 선택에 합집합으로 더하고,
    /// 임시 해제를 보존하며 차단을 다시 적용한다. 남은 시간(endsAt)은 건드리지 않는다.
    private func commitAddedApps() {
        var merged = session.selection
        merged.applicationTokens.formUnion(addSelection.applicationTokens)
        merged.categoryTokens.formUnion(addSelection.categoryTokens)
        merged.webDomainTokens.formUnion(addSelection.webDomainTokens)

        let current = session.selection
        let changed = merged.applicationTokens != current.applicationTokens
            || merged.categoryTokens != current.categoryTokens
            || merged.webDomainTokens != current.webDomainTokens
        guard changed else { return }

        session.selection = merged
        try? modelContext.save()
        TempUnlockController.shared.reapplyShield(session: session, modelContext: modelContext)
    }
}

private enum LockRemoteTheme {
    static let cream = LinearGradient(
        colors: [Color(hex: 0xf1ead7), Color(hex: 0xe4dabe), Color(hex: 0xd2c7a6)],
        startPoint: .top, endPoint: .bottom
    )
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
