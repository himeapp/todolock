import SwiftUI
import SwiftData
import FamilyControls

/// 노래방 리모컨 컨셉의 홈 화면. 앱 실행 시 첫 화면.
/// 숫자패드로 시간(HHMM) 입력 → 모드/앱/과업 설정 → 시작으로 잠금 세션 시작.
struct RemoteControlView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = RemoteViewModel()
    @StateObject private var deepLink = DeepLinkHandler.shared

    @Query(sort: \SessionPreset.orderIndex) private var presets: [SessionPreset]
    @Query(sort: \Session.createdAt, order: .reverse) private var sessions: [Session]

    @State private var showingPicker = false
    /// 감시 대상 앱 고르기용 별도 피커(잠글 앱 피커와 독립).
    @State private var showingWatchdogPicker = false
    @State private var showingJump = false
    @State private var showingJumpBlockedAlert = false
    @State private var showingSettings = false
    /// 리모컨 모달 안에서 보여줄 페이지. 시작 확인·감시 설정은 모달 위에 새 모달을
    /// 띄우지 않고(=이중 모달 금지) 이 값만 바꿔 모달 안에서 좌우로 밀어 전환한다.
    @State private var page: RemotePage = .keypad
    /// 키패드 페이지의 실측 높이. 시작/감시 페이지를 같은 높이로 맞춰 전환이
    /// 위아래로 튀지 않고 순수 좌우 슬라이드로만 보이게 한다.
    @State private var keypadHeight: CGFloat = 0
    @State private var errorMessage: String?
    @State private var taskExecutionSessionId: UUID?
    @State private var editingPreset: SessionPreset?

    /// 막힌 시작 버튼을 눌렀을 때 잠깐 보여주는 안내. 일정 시간 뒤 사라진다.
    @State private var blockHint: String?
    /// 안내가 오류(빨강)인지 알림(틸)인지. 감시를 걸었을 때의 확인 메시지는 틸로 보여준다.
    @State private var blockHintIsNotice = false
    /// 안내 자동 숨김 타이머 식별용. 연타 시 이전 타이머가 새 안내를 지우지 않게 한다.
    @State private var blockHintGeneration = 0

    /// 유저가 마지막으로 사용한 잠금 시간(초). 기본값 1시간.
    @AppStorage("lastDurationSeconds") private var lastDurationSeconds: Int = 60 * 60

    private var activeSessions: [Session] { sessions.filter { $0.isActive } }

    var body: some View {
        NavigationStack {
            ZStack {
                // 뒤: 실제 잠금화면과 같은 노래방 CRT TV 배경.
                KaraokeBackground().ignoresSafeArea()

                // 위쪽엔 빈 노래방 TV가 살짝 보이고("빨리 잠그고 싶게"),
                // 컨트롤은 전부 하단 크림 리모컨 "모달"에 모은다.
                VStack(spacing: 0) {
                    tvIdle
                        .padding(.top, 30)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 8)
                    remoteModal
                }
                // 모드 이름 변경 팝업의 키보드가 올라와도 뒤 화면(숫자패드 등)은 밀리지 않게.
                .ignoresSafeArea(.keyboard, edges: .bottom)

                if let preset = editingPreset {
                    ModeNameEditor(
                        preset: preset,
                        onSave: { if vm.activePresetID == preset.id { vm.load(preset) } },
                        onClose: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                editingPreset = nil
                            }
                        }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { id in
                SessionDetailView(sessionId: id)
            }
            .familyActivityPicker(isPresented: $showingPicker, selection: $vm.selection)
            .familyActivityPicker(isPresented: $showingWatchdogPicker, selection: $vm.watchdogSelection)
            .sheet(isPresented: $showingJump) {
                TaskPoolSheet()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet()
            }
            .fullScreenCover(isPresented: Binding(
                get: { !activeSessions.isEmpty },
                set: { _ in }
            )) {
                if let session = activeSessions.first {
                    LockScreenView(session: session)
                }
            }
            .sheet(item: Binding(
                get: { taskExecutionSessionId.map { IdentifiableUUID(id: $0) } },
                set: { taskExecutionSessionId = $0?.id }
            )) { wrapper in
                TaskExecutionView(sessionId: wrapper.id)
            }
            .alert("시작 실패", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("아직 점프할 수 없어요", isPresented: $showingJumpBlockedAlert) {
                Button("확인", role: .cancel) { }
            } message: {
                Text("앱을 잠그고 노래 중일 때에만 간주 점프에 도전할 수 있어요.")
            }
            .onAppear(perform: setupPresets)
            .onReceive(deepLink.$pendingSessionId) { id in
                guard let id else { return }
                // 잠금이 활성이면 잠금 화면(LockScreenView)이 점프(곡목록)를 직접 연다.
                // 풀스크린 커버에 가려 시트가 안 보이므로 여기선 건드리지 않는다.
                // 잠금이 없는 상태(만료된 알림을 뒤늦게 탭 등)에서만 과업 화면을 띄운다.
                guard activeSessions.isEmpty else { return }
                taskExecutionSessionId = id
                deepLink.clear()
            }
        }
    }

    // MARK: - 빈 TV 대기 영역 (모달 위로 살짝 보이는 부분)

    /// 잠금 전, 위쪽에 보이는 노래방 "선곡 대기" 화면. 옛날 노래방 기기가 곡 입력을
    /// 기다릴 때처럼 자막·이퀄라이저로 살아 움직여 빨리 시작하고 싶게 만든다.
    private var tvIdle: some View { KaraokeStandbyTV() }

    // MARK: - 리모컨 모달 (하단 시트)

    /// 크림 보디 + 하늘색 테두리 + 비닐막. 안에 LED·기능·숫자패드·시작을 모은다.
    private var remoteModal: some View {
        VStack(spacing: 13) {
            Capsule()
                .fill(.black.opacity(0.16))
                .frame(width: 48, height: 5)
                .padding(.top, 4)

            header

            // 모달 위 모달 대신, 한 모달 안에서 화면만 좌우로 밀어 전환한다.
            // 키패드는 왼쪽 가장자리, 시작/감시 카드는 오른쪽 가장자리로 드나든다.
            ZStack {
                switch page {
                case .keypad:
                    keypadPage
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                case .start:
                    startCard
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            // 슬라이드 중 옆 페이지가 모달 밖으로 삐져나오지 않게 가둔다.
            .clipped()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 30)
                .fill(RemoteTheme.background)
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0, topTrailingRadius: 30)
                        .stroke(Color(hex: 0xa8cee8).opacity(0.75), lineWidth: 2.5)
                }
                .overlay { remoteFilm }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - 리모컨 모달 안의 페이지들

    /// 기본 페이지 — LED·기능키·숫자패드·시작. 높이를 실측해 시작/감시 카드와 맞춘다.
    private var keypadPage: some View {
        VStack(spacing: 13) {
            if let session = activeSessions.first {
                activeBanner(session)
            }

            // 감시 모드에선 같은 LED가 하루 한도(HOUR:MIN)를 남보라로 보여준다.
            // DAY 자리는 빼고, 색만 바꿔 위치/크기는 그대로 둔다(레이아웃 불변).
            if vm.mode == .watchdog {
                LEDDisplay(days: "", hours: vm.watchdogHoursString, minutes: vm.watchdogMinutesString,
                           showDays: false,
                           lit: Color(hex: 0x8f9bff), barLit: Color(hex: 0x8f9bff))
            } else {
                LEDDisplay(days: vm.daysString, hours: vm.hoursString, minutes: vm.minutesString)
            }

            controlSplit

            if let hint = blockHint {
                Text(hint)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(blockHintIsNotice ? Color(hex: 0x15897b) : Color(hex: 0xe8533a))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            startButton
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(PanelHeightKey.self) { keypadHeight = $0 }
    }

    /// 시작 확인 카드 — 모달 위 시트가 아니라 키패드와 같은 높이의 카드로 끼워 넣는다.
    private var startCard: some View {
        StartConfirmSheet(
            selection: vm.selection,
            durationText: durationText(vm.totalSeconds),
            onStart: {
                go(to: .keypad)
                start()
            },
            onCancel: { go(to: .keypad) }
        )
        .frame(height: keypadHeight > 0 ? keypadHeight : nil)
    }

    /// 비닐막 — 리모컨 모달 표면의 라미네이트 느낌(사선 빛줄기 + 가장자리 광). 터치는 통과.
    private var remoteFilm: some View {
        ZStack {
            // 상단 광
            RadialGradient(colors: [.white.opacity(0.14), .clear],
                           center: UnitPoint(x: 0.38, y: 0.05), startRadius: 5, endRadius: 220)
            // 사선 빛줄기 2개
            Capsule().fill(.white.opacity(0.30)).frame(height: 12).blur(radius: 2)
                .rotationEffect(.degrees(-9)).offset(x: -40, y: -70)
            Capsule().fill(.white.opacity(0.22)).frame(height: 14).blur(radius: 2)
                .rotationEffect(.degrees(7)).offset(x: 50, y: 30)
            // 가장자리 안쪽 광
            UnevenRoundedRectangle(topLeadingRadius: 27, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 27)
                .stroke(Color(hex: 0xcee6f6).opacity(0.55), lineWidth: 2)
                .padding(4)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: 30))
        .allowsHitTesting(false)
    }

    // MARK: - 상단

    private var header: some View {
        HStack(spacing: 8) {
            Text("TL")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(
                        RadialGradient(colors: [Color(hex: 0xff8a5c), Color(hex: 0xe8533a)],
                                       center: .topLeading, startRadius: 1, endRadius: 22)
                    )
                )
            Text("TODOLOCK")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Color(hex: 0x333333))
            Spacer()
            Button {
                showingSettings = true
            } label: { settingsKeycap }
            .buttonStyle(.plain)
        }
    }

    /// 헤더 우측 설정 버튼 — 숫자패드의 아이보리 키캡과 같은 룩으로 "설정"을 새긴 키.
    /// 더 둥근 모서리(13) + 비닐 라미네이트막 + 균일 고딕 라벨로 실물 노래방 리모컨 키 느낌.
    private var settingsKeycap: some View {
        Text("설정")
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(Color(hex: 0x1a1a1a))
            .frame(width: 58, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 13).fill(
                    LinearGradient(colors: [Color(hex: 0xeceee0), Color(hex: 0xd6d9c4)],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: 0xc1c4b0), lineWidth: 1))
            .overlay(alignment: .top) { keycapGloss(radius: 13) }
            .overlay { settingsKeycapFilm }
    }

    /// 설정 키 표면의 비닐 라미네이트 — 사선 광 시트 + 윗쪽 빛줄기 + 들뜬 가장자리 광. 터치는 통과.
    private var settingsKeycapFilm: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.04), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Capsule().fill(.white.opacity(0.42)).frame(height: 6).blur(radius: 1.5)
                .rotationEffect(.degrees(-12)).offset(y: -9)
            RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.3), lineWidth: 1).padding(1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .allowsHitTesting(false)
    }

    private func activeBanner(_ session: Session) -> some View {
        NavigationLink(value: session.id) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text("\(session.selection.applicationTokens.count)개 앱 잠금 중" +
                     (activeSessions.count > 1 ? " 외 \(activeSessions.count - 1)" : ""))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x23306a)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 좌측 기능 컬럼 (작은 키 6개 + 잠글앱관리)

    /// 실물 리모컨처럼 좌측엔 컬러 기능키 매트릭스(2열×3) + 잠글앱관리,
    /// 우측엔 숫자패드를 둔다. 좌측 키들은 우측 숫자패드보다 작게.
    private var leftColumn: some View {
        // 모드는 앞 2개만 노출한다. (감시가 3번째 모드 자리를 대체했다)
        let modes = Array(presets.prefix(2))
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                FuncButton(title: "시간", arrow: "▲", style: .gray) { vm.bumpMinutes(60) }
                FuncButton(title: "시간", arrow: "▼", style: .gray) { vm.bumpMinutes(-60) }
            }
            // 좌열은 모드(모드1·모드2), 우열은 점프/감시로 묶는다.
            HStack(spacing: 8) {
                if let m = modes.first { presetButton(m) }
                jumpButton
            }
            HStack(spacing: 8) {
                if modes.count > 1 { presetButton(modes[1]) }
                WatchdogButton(isActive: vm.mode == .watchdog) { toggleWatchdog() }
            }
            Button {
                if vm.mode == .watchdog { showingWatchdogPicker = true } else { showingPicker = true }
            } label: { manageBar }
                .buttonStyle(.plain)
        }
    }

    private func presetButton(_ preset: SessionPreset) -> some View {
        PresetButton(name: preset.name, selected: vm.activePresetID == preset.id) {
            if vm.activePresetID == preset.id {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    editingPreset = preset
                }
            } else {
                vm.load(preset)
            }
        }
    }

    private var jumpButton: some View {
        FuncButton(title: "점프", arrow: nil, style: .green) {
            // 점프(간주)는 앱을 잠그고 노래 중일 때만 도전할 수 있다.
            if activeSessions.isEmpty {
                showingJumpBlockedAlert = true
            } else {
                showingJump = true
            }
        }
    }

    /// 좌(기능) + 우(숫자패드) 분할. 숫자패드 4줄 높이(키 56 × 4 + 간격 6 × 3 = 242)에
    /// 맞춰 분할 전체 높이를 고정하고, 좌측 manage가 그 안에서 남는 높이를 채운다.
    /// (고정하지 않으면 manage의 maxHeight:.infinity가 모달 전체로 전파돼 끝까지 늘어난다.)
    private var controlSplit: some View {
        HStack(alignment: .top, spacing: 10) {
            leftColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            numberPad
                // 숫자버튼 쪽에 비닐 질감을 더 살린다 — 키 위로 비치는 라미네이트 광막.
                .overlay { numberPadFilm }
                .frame(maxWidth: .infinity)
        }
        .frame(height: 242)
        // 좌측 기능키에도 같은 비닐이 옅게 비친다 — 숫자패드만 따로 싼 게 아니라
        // 리모컨 전체가 한 겹 비닐로 감싸이고, 숫자패드 위에서만 더 두드러지는 느낌.
        .overlay { controlFilm }
    }

    /// 컨트롤 전체(기능키 + 숫자패드)를 한 장으로 덮는 옅은 비닐막. 터치는 통과.
    /// 숫자패드는 이 위에 numberPadFilm으로 한 번 더 비쳐 더 도드라진다.
    private var controlFilm: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.10), .clear, .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Capsule().fill(.white.opacity(0.16)).frame(height: 10).blur(radius: 3)
                .rotationEffect(.degrees(-8)).offset(y: -66)
            Capsule().fill(.white.opacity(0.12)).frame(height: 9).blur(radius: 3)
                .rotationEffect(.degrees(5)).offset(y: 54)
        }
        .allowsHitTesting(false)
    }

    /// 숫자패드 표면에 덮인 비닐 라미네이트 — 키 위로 비치는 부드러운 광막 + 사선 빛줄기.
    /// 모달 전체 비닐막(remoteFilm)은 배경 뒤라 키에 가려지므로, 숫자버튼엔 이걸 따로 덮는다. 터치는 통과.
    private var numberPadFilm: some View {
        ZStack {
            // 패드 전체를 비스듬히 덮는 라미네이트 시트 광 — 위 절반이 더 밝게 비친다.
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // 우상단에서 번지는 부드러운 광막
            RadialGradient(colors: [.white.opacity(0.30), .clear],
                           center: UnitPoint(x: 0.72, y: 0.16), startRadius: 4, endRadius: 160)
            // 사선 빛줄기 3개 (위·중간·아래)
            Capsule().fill(.white.opacity(0.48)).frame(height: 12).blur(radius: 2.5)
                .rotationEffect(.degrees(-13)).offset(x: 16, y: -58)
            Capsule().fill(.white.opacity(0.32)).frame(height: 9).blur(radius: 2)
                .rotationEffect(.degrees(6)).offset(x: 22, y: -4)
            Capsule().fill(.white.opacity(0.36)).frame(height: 13).blur(radius: 2.5)
                .rotationEffect(.degrees(-5)).offset(x: 8, y: 50)
        }
        .allowsHitTesting(false)
    }

    /// 좌측 컬럼 하단의 2줄 앱 관리 블록. 남은 높이를 채워 숫자패드와 바닥을 맞춘다.
    /// 잠금=빨강 "잠글 앱 관리", 감시=틸 "감시할 앱 고르기"로 모드에 따라 바뀐다.
    private var manageBar: some View {
        let watchdog = vm.mode == .watchdog
        let count = watchdog ? watchdogSelectionCount : vm.selection.applicationTokens.count
        let title: String = watchdog
            ? (count == 0 ? "감시할 앱\n고르기" : "감시할 앱\n· \(count)")
            : (count == 0 ? "잠글 앱\n관리" : "잠글 앱\n관리 · \(count)")
        let colors = watchdog
            ? [Color(hex: 0x2bb5a4), Color(hex: 0x15897b)]
            : [Color(hex: 0xec5743), Color(hex: 0xd23522)]
        return Text(title)
            .multilineTextAlignment(.center)
            .lineSpacing(1)
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(
                    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(alignment: .top) { keycapGloss(radius: 10) }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.18), lineWidth: 1))
    }

    /// 감시 대상 개수(앱+카테고리+웹도메인).
    private var watchdogSelectionCount: Int {
        vm.watchdogSelection.applicationTokens.count
        + vm.watchdogSelection.categoryTokens.count
        + vm.watchdogSelection.webDomainTokens.count
    }

    // MARK: - 숫자패드

    private var numberPad: some View {
        VStack(spacing: 6) {
            ForEach(0..<3) { row in
                HStack(spacing: 6) {
                    ForEach(1..<4) { col in
                        let n = row * 3 + col
                        NumKey(.digit(n)) { vm.pushDigit(n) }
                    }
                }
            }
            HStack(spacing: 6) {
                NumKey(.cancel) { vm.clear() }
                NumKey(.digit(0)) { vm.pushDigit(0) }
                NumKey(.back) { vm.back() }
            }
        }
    }

    private var startButton: some View {
        // 잠금=노랑 "시 작 ▶", 감시=검정 "오늘부터 감시 걸기 ▶".
        let watchdog = vm.mode == .watchdog
        // 막혔을 때도 탭은 받아서 안내를 띄운다(.disabled 이면 탭이 안 들어옴).
        return Button(action: watchdog ? tapWatchdogStart : tapStart) {
            Text(watchdog ? "오늘부터 감시 걸기 ▶" : "시 작 ▶")
                .font(.system(size: watchdog ? 22 : 30, weight: .black))
                .tracking(watchdog ? 1 : 6)
                .foregroundStyle(watchdog ? .white : Color(hex: 0x2a2e06))
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .background(
                    RoundedRectangle(cornerRadius: 30).fill(
                        LinearGradient(
                            colors: watchdog
                                ? [Color(hex: 0x34322c), Color(hex: 0x111111)]
                                : [Color(hex: 0xf7ff5e), Color(hex: 0xe9f600)],
                            startPoint: .top, endPoint: .bottom)
                    )
                )
                .overlay(alignment: .top) { keycapGloss(radius: 30) }
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(.black.opacity(0.18), lineWidth: 1))
                // 뿌연 네온 글로우 제거 — 실물처럼 또렷한 아날로그 버튼으로.
                .opacity((watchdog ? vm.canSaveWatchdog : vm.canStart) ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    /// 시작 버튼 탭. 시작 가능하면 확인 시트, 아니면 막힌 이유를 잠깐 안내한다.
    private func tapStart() {
        if vm.canStart {
            blockHint = nil
            go(to: .start)
        } else if let reason = vm.startBlockReason {
            showBlockHint(reason)
        }
    }

    /// 감시 걸기 탭. 가능하면 곧장 감시를 걸고(확인 시트 없음), 아니면 막힌 이유를 안내한다.
    private func tapWatchdogStart() {
        if vm.canSaveWatchdog {
            startWatchdog()
        } else if let reason = vm.watchdogBlockReason {
            showBlockHint(reason)
        }
    }

    /// 리모컨 모달 안에서 페이지를 바꾼다. 키패드는 왼쪽 가장자리로, 시작/감시
    /// 페이지는 오른쪽 가장자리로 드나들어 "앞으로/뒤로" 내비게이션처럼 보인다.
    private func go(to newPage: RemotePage) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            page = newPage
        }
    }

    /// 안내를 띄우고 2.5초 뒤 자동으로 숨긴다. 연타 시 마지막 안내 기준으로만 숨김.
    /// isNotice면 오류(빨강)가 아니라 알림(틸)으로 보여준다.
    private func showBlockHint(_ message: String, isNotice: Bool = false) {
        blockHintGeneration += 1
        let generation = blockHintGeneration
        withAnimation(.easeOut(duration: 0.2)) {
            blockHint = message
            blockHintIsNotice = isNotice
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard blockHintGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.3)) { blockHint = nil }
        }
    }

    /// 감시 모드 ↔ 잠금 모드 토글. 감시 키로 호출한다.
    private func toggleWatchdog() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            vm.mode = vm.mode == .watchdog ? .lock : .watchdog
            blockHint = nil
        }
    }

    /// 감시를 건다. 지금은 UI 흐름만 — 실제 등록은 TODO. 끝나면 잠금 모드로 돌아오며 확인을 띄운다.
    private func startWatchdog() {
        // TODO(피드백 후 배선): 감시 설정(watchdogSelection + 한도)을 App Group에 저장 →
        //   DeviceActivityCenter에 daily 스케줄 + threshold(watchdogTotalSeconds) 이벤트 등록.
        //   알림 권한이 거절 상태면 "설정에서 알림 켜기" 안내를 띄운다.
        //   넘는 순간 익스텐션 eventDidReachThreshold → 로컬 알림 → 탭 시 시작 확인 시트(딥링크).
        let limit = durationText(vm.watchdogTotalSeconds)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { vm.mode = .lock }
        showBlockHint("감시를 걸었어요 · 하루 \(limit)", isNotice: true)
    }

    // MARK: - 동작

    /// 최초 실행 시 기본 모드 3개를 시드하고, 항상 하나의 모드가 선택돼 있도록 보장한다.
    /// (모드는 항상 하나 선택 상태 — 비어 있으면 모드1, 이미 있으면 첫 모드를 로드)
    private func setupPresets() {
        if presets.isEmpty {
            let seeds = SessionPreset.seeds()
            for p in seeds { modelContext.insert(p) }
            try? modelContext.save()
            if let first = seeds.min(by: { $0.orderIndex < $1.orderIndex }) {
                vm.load(first)
                vm.setDuration(lastDurationSeconds)
            }
        } else if vm.activePresetID == nil, let first = presets.first {
            vm.load(first)
            // 모드의 저장 시간 대신, 유저가 마지막으로 쓴 시간을 LED에 보여준다.
            vm.setDuration(lastDurationSeconds)
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)일") }
        if h > 0 { parts.append("\(h)시간") }
        if m > 0 { parts.append("\(m)분") }
        return parts.isEmpty ? "0분" : parts.joined(separator: " ")
    }

    private func start() {
        let store = SessionStore(modelContext: modelContext)
        do {
            // 시작한 시간을 다음 실행 때 다시 보여주도록 저장.
            lastDurationSeconds = vm.totalSeconds
            _ = try store.start(
                endsAt: vm.endsAt,
                selection: vm.selection,
                passDurationMinutes: vm.passDurationMinutes
            )
            // 0분으로 비우지 않고, 방금 쓴 시간을 그대로 유지한다.
            vm.setDuration(lastDurationSeconds)
        } catch SessionStartError.appAlreadyLocked {
            errorMessage = "이미 다른 세션에서 잠긴 앱이 있어요. 다른 앱을 선택해주세요."
        } catch SessionStartError.schedulingFailed(let underlying) {
            errorMessage = "세션 예약에 실패했어요: \(underlying.localizedDescription)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct IdentifiableUUID: Identifiable { let id: UUID }

/// 리모컨 모달 안에서 보여줄 페이지. (모달 위 모달 대신 한 모달 안에서 전환)
/// 감시는 별도 페이지가 아니라 키패드 페이지의 한 "모드"로 동작한다(vm.mode).
private enum RemotePage { case keypad, start }

/// 키패드 페이지 높이를 부모로 올려 보내, 시작/감시 카드를 같은 높이로 맞추는 키.
private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - 노래방 선곡 대기 화면 (리모컨 위로 보이는 빈 TV)

/// 노래방 "인기차트" 패널을 아주 옅게 본뜬 대기화면.
/// CRT TV(KaraokeBackground)를 비워두고, 거의 투명한 차트 네모와 안내 한 줄만 남겨
/// 빨리 잠그고(=선곡하고) 싶게 만든다.
private struct KaraokeStandbyTV: View {
    /// 인기차트 헤더 우측의 날짜(노래방 차트 룩).
    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            chartHeader

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)

            Text("선곡을 기다리고 있어요")
                .font(.myungjoLight(15))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// 인기차트 헤더 — 좌측 "인기차트" · 가운데 "◀ 가요 ▶" 탭 · 우측 날짜. 전부 옅게.
    private var chartHeader: some View {
        HStack(spacing: 8) {
            Text("인기차트")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white.opacity(0.55))

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 8, weight: .bold))
                Text("잠글 앱").font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.38))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )

            Spacer(minLength: 8)

            Text(dateText)
                .font(.led(11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - 시작 전 확인 시트

/// 어떤 앱을 얼마 동안 떠나보내는지 정확히 보여주고 시작을 확인받는 시트.
/// 앱 이름은 FamilyControls 프라이버시상 문자열로 못 빼므로 `Label(token)`으로만 렌더링한다.
/// 모드 이름 변경 팝업(노래찾기 룩)과 같은 노래방 디자인 — 파란 타이틀바·CRT 다크 본문·
/// 곡목록처럼 보이는 앱 목록·하단 액션바로 구성한다.
private struct StartConfirmSheet: View {
    let selection: FamilyActivitySelection
    let durationText: String
    let onStart: () -> Void
    let onCancel: () -> Void

    private var appCount: Int { selection.applicationTokens.count }
    private var categoryCount: Int { selection.categoryTokens.count }
    private var webCount: Int { selection.webDomainTokens.count }
    private var totalCount: Int { appCount + categoryCount + webCount }

    var body: some View {
        // 모달 위 시트가 아니라, 리모컨 모달 안에 끼워지는 카드. 키패드와 같은
        // 높이를 부모가 잡아주므로 여기선 그 높이를 가득 채우고 둥글게 클립만 한다.
        VStack(spacing: 0) {
            titleBar
            bodyArea
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [Color(hex: 0x12203a), Color(hex: 0x0a1326)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x2d4f86), lineWidth: 1.5)
        )
    }

    // MARK: 파란 타이틀바

    private var titleBar: some View {
        HStack(spacing: 10) {
            waveCircle
            OutlinedText(text: "잠시만 안녕할까요?", size: 19,
                         fill: Color(hex: 0xeaff6a), stroke: KColor.outline, strokeWidth: 3.5)
            Spacer(minLength: 6)
            durationChip
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x3c7bd6), Color(hex: 0x1e4f9e)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.25)).frame(height: 1.5)
        }
    }

    private var waveCircle: some View {
        ZStack {
            Circle().fill(
                RadialGradient(colors: [Color(hex: 0xffe08a), Color(hex: 0xe69a28)],
                               center: .topLeading, startRadius: 1, endRadius: 26)
            )
            Circle().stroke(Color(hex: 0x8a571a), lineWidth: 1.5)
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Color(hex: 0x5a3a08))
        }
        .frame(width: 30, height: 30)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private var durationChip: some View {
        Text(durationText)
            .font(.led(13))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(KColor.pink))
    }

    // MARK: 본문 (곡목록처럼 보이는 앱 목록)
    // 기간/안내는 타이틀바(잠시만 안녕할까요? + 기간칩)가 이미 말하므로 본문은 목록만.

    private var bodyArea: some View {
        KaraokeSongList(selection: selection)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxHeight: .infinity)
    }

    // MARK: 하단 액션바

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text("\(totalCount)개")
                .font(.led(13))
                .foregroundStyle(KColor.cyan)
            Spacer()
            actionButton("취소", color: Color(hex: 0x4a5568)) { onCancel() }
            actionButton("시작", color: KColor.green) { onStart() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.myungjo(16))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(color))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - VFD LED 디스플레이

struct LEDDisplay: View {
    let days: String
    let hours: String
    let minutes: String
    var digitSize: CGFloat = 46
    /// 양옆 그래픽 이퀄라이저 바. 슬림 리모컨처럼 좁은 곳에선 끈다.
    var showBars: Bool = true
    /// 감시 모드에선 DAY 자리를 숨기고 HOUR:MIN만 보여준다.
    var showDays: Bool = true
    /// 7세그먼트 발광색. 잠금=주황, 감시=남보라.
    var lit: Color = Color(hex: 0xff5a32)
    /// 이퀄라이저 바 발광색. 잠금=초록, 감시=남보라.
    var barLit: Color = Color(hex: 0x4ee87f)

    var body: some View {
        Group {
            if showBars {
                HStack(spacing: 8) {
                    barColumn(greens: [false, true, true, false, true, false])
                    digitRow.frame(maxWidth: .infinity)
                    barColumn(greens: [false, true, false, true, true, false])
                }
            } else {
                digitRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 7).fill(
                RadialGradient(colors: [Color(hex: 0x14120b), Color(hex: 0x050503)],
                               center: .center, startRadius: 1, endRadius: 180)
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(hex: 0x2c281c), lineWidth: 2))
    }

    private var digitRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if showDays {
                digitGroup(days, label: "DAY")
                colon
            }
            digitGroup(hours, label: "HOUR")
            colon
            digitGroup(minutes, label: "MIN")
        }
    }

    /// 두 자리 7세그먼트 숫자 + 그 아래 작은 단위 라벨(DAY/HOUR/MIN).
    /// 뒤에 "88"을 흐리게 깔아 꺼진 세그먼트가 비치는 LED 느낌을 낸다.
    private func digitGroup(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Text("88").font(.seg7(digitSize)).foregroundStyle(lit.opacity(0.10))
                Text(value)
                    .font(.seg7(digitSize))
                    .foregroundStyle(lit)
                    .shadow(color: lit.opacity(0.8), radius: 9)
            }
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(lit.opacity(0.55))
        }
    }

    private var colon: some View {
        Text(":")
            .font(.seg7(digitSize))
            .foregroundStyle(lit)
            .shadow(color: lit.opacity(0.8), radius: 9)
    }

    private func barColumn(greens: [Bool]) -> some View {
        VStack(spacing: 3) {
            ForEach(greens.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(greens[i] ? barLit : barLit.opacity(0.16))
                    .frame(width: 12, height: 5)
                    .shadow(color: greens[i] ? barLit.opacity(0.85) : .clear, radius: 4)
            }
        }
    }
}

// MARK: - 기능 버튼 / 프리셋 / 숫자키

private struct FuncButton: View {
    enum Style { case gray, ivory, green }
    let title: String
    let arrow: String?
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title).font(.system(size: 18, weight: .black))
                if let arrow { Text(arrow).font(.system(size: 16, weight: .bold)).opacity(0.9) }
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 8).fill(gradient))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.22), lineWidth: 1))
            .overlay(alignment: .top) { keycapGloss(radius: 8) }
        }
        .buttonStyle(.plain)
    }

    private var fg: Color {
        switch style {
        case .gray, .ivory: return Color(hex: 0x222222)
        case .green: return Color(hex: 0x0b2606)
        }
    }
    private var gradient: LinearGradient {
        let colors: [Color]
        switch style {
        case .gray: colors = [Color(hex: 0xe6e6de), Color(hex: 0xcfcfc4)]
        case .ivory: colors = [Color(hex: 0xf2ecda), Color(hex: 0xe2d9c1)]
        case .green: colors = [Color(hex: 0x74c94f), Color(hex: 0x54a836)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

private struct PresetButton: View {
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if selected {
                    Circle().fill(Color(hex: 0xe8853a)).frame(width: 5, height: 5)
                }
                // 모드 이름: 검정·또렷하게
                Text(name).font(.system(size: 18, weight: .black))
            }
            .foregroundStyle(Color(hex: 0x1a1a1a))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(
                    LinearGradient(colors: [Color(hex: 0xf4eedd), Color(hex: 0xe6dcc3)],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(alignment: .top) { keycapGloss(radius: 8) }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color(hex: 0x3f73bd) : .black.opacity(0.2),
                                  lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct NumKey: View {
    enum Kind { case digit(Int), cancel, back }
    let kind: Kind
    let action: () -> Void

    init(_ kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
    }

    private let radius: CGFloat = 9

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: radius).fill(gradient))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: 1))
                .overlay(alignment: .top) { keycapGloss(radius: radius) }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var label: some View {
        switch kind {
        case .digit(let n):
            Text("\(n)")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .italic()
                .foregroundStyle(Color(hex: 0x1a1a1a))
        case .cancel:
            Text("취소")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        case .back:
            Text("지움")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var isBlue: Bool {
        switch kind { case .digit: return false; default: return true }
    }
    private var gradient: LinearGradient {
        isBlue
        ? LinearGradient(colors: [Color(hex: 0x5a93d6), Color(hex: 0x3f73bd)], startPoint: .top, endPoint: .bottom)
        : LinearGradient(colors: [Color(hex: 0xeceee0), Color(hex: 0xd6d9c4)], startPoint: .top, endPoint: .bottom)
    }
    private var stroke: Color { isBlue ? Color(hex: 0x2f5a9a) : Color(hex: 0xc1c4b0) }
}

// MARK: - 테마 / 헬퍼

/// 리모컨 키캡 느낌의 상단 광택 띠 — 둥근 모서리를 따라 위쪽만 하얗게 비친다.
/// 실제 고무/플라스틱 버튼처럼 빛이 윗면에 모이는 느낌을 준다.
func keycapGloss(radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius)
        .fill(
            LinearGradient(
                colors: [.white.opacity(0.45), .white.opacity(0.05), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
        .padding(1.5)
        .allowsHitTesting(false)
}

private enum RemoteTheme {
    static let background = LinearGradient(
        colors: [Color(hex: 0xf1ead7), Color(hex: 0xe4dabe), Color(hex: 0xd2c7a6), Color(hex: 0xc2b692)],
        startPoint: .topLeading, endPoint: .bottomTrailing
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

// MARK: - 모드 이름 변경 팝업 (노래방 "노래찾기" 룩)

/// 선택된 모드를 다시 탭하면 뜨는 작은 창. 모드 이름만 바꿔 SessionPreset에 저장한다.
/// 옛날 노래방 노래찾기 화면을 본떠 파란 타이틀바·돋보기 원형 아이콘·CRT 다크 입력창·
/// 추천 이름 곡목록·하단 액션바로 구성한다.
private struct ModeNameEditor: View {
    @Environment(\.modelContext) private var modelContext
    let preset: SessionPreset
    let onSave: () -> Void
    let onClose: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    /// 버튼에 한 줄로 들어가도록 모드 이름 최대 글자수.
    private let maxNameLength = 6

    /// 노래찾기 곡목록처럼 보이는 추천 이름 + 가짜 곡번호.
    private let suggestions: [(code: String, name: String)] = [
        ("24433", "집중"),
        ("91405", "공부"),
        ("53997", "마감"),
        ("24434", "운동"),
        ("91880", "취침")
    ]

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { !trimmed.isEmpty }

    /// 입력 글자로 추천 이름을 고른다.
    /// 앞글자 일부("마"→마감)나 초성("ㅁㄱ"→마감)이 들어맞으면 선택된 것으로 본다.
    private func matches(_ candidate: String) -> Bool {
        let q = trimmed
        guard !q.isEmpty else { return false }
        if candidate.hasPrefix(q) { return true }
        return Self.chosung(of: candidate).hasPrefix(q)
    }

    /// 한글 음절을 초성 문자열로 바꾼다. "마감" → "ㅁㄱ". 한글이 아니면 그대로 둔다.
    private static func chosung(of text: String) -> String {
        let table = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
                     "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
        var out = ""
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v >= 0xAC00, v <= 0xD7A3 {
                out += table[Int((v - 0xAC00) / 588)]
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                titleBar
                bodyArea
                bottomBar
            }
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(
                    LinearGradient(colors: [Color(hex: 0x12203a), Color(hex: 0x0a1326)],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x2d4f86), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            .padding(.horizontal, 26)
        }
        .onAppear {
            name = preset.name
            // 팝업 등장과 키보드를 한 모션으로 묶기 위해 지연 없이 다음 런루프에서 바로 포커스.
            // (0.35초 지연을 두면 팝업이 먼저 뜬 뒤 키보드가 따로 올라와 2단계로 버벅여 보인다.)
            DispatchQueue.main.async { focused = true }
        }
    }

    // MARK: 파란 타이틀바

    private var titleBar: some View {
        HStack(spacing: 10) {
            searchCircle
            OutlinedText(text: "모드 이름 변경", size: 19,
                         fill: Color(hex: 0xeaff6a), stroke: KColor.outline, strokeWidth: 3.5)
            Spacer(minLength: 6)
            hangulChip
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x3c7bd6), Color(hex: 0x1e4f9e)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.25)).frame(height: 1.5)
        }
    }

    private var searchCircle: some View {
        ZStack {
            Circle().fill(
                RadialGradient(colors: [Color(hex: 0xffe08a), Color(hex: 0xe69a28)],
                               center: .topLeading, startRadius: 1, endRadius: 26)
            )
            Circle().stroke(Color(hex: 0x8a571a), lineWidth: 1.5)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Color(hex: 0x5a3a08))
        }
        .frame(width: 30, height: 30)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private var hangulChip: some View {
        HStack(spacing: 4) {
            Text("한글")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text("가")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(KColor.pink))
        }
    }

    // MARK: 본문 (입력창 + 추천 이름 목록)

    private var bodyArea: some View {
        VStack(spacing: 12) {
            inputField

            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, item in
                    suggestionRow(item)
                }
            }
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            Text("가")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(KColor.pink))

            ZStack(alignment: .leading) {
                // 보이는 텍스트 + 밑줄(_) 커서. 노래찾기 화면처럼 "송가인_" 느낌.
                Group {
                    if name.isEmpty && !focused {
                        Text("모드 이름 입력")
                            .font(.myungjoLight(20))
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        HStack(spacing: 1) {
                            Text(name)
                                .font(.myungjo(24))
                                .foregroundStyle(.white)
                            if focused { blinkingCaret }
                        }
                    }
                }
                .allowsHitTesting(false)

                // 입력 캡처용 투명 필드 — 글자/기본 커서는 숨기고 위 표시만 보이게 한다.
                TextField("", text: $name)
                    .font(.myungjo(24))
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if isValid { save() } }
                    .onChange(of: name) { _, newValue in
                        if newValue.count > maxNameLength {
                            name = String(newValue.prefix(maxNameLength))
                        }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(
                RadialGradient(colors: [Color(hex: 0x0d1322), Color(hex: 0x05080f)],
                               center: .center, startRadius: 1, endRadius: 220)
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(KColor.cyan.opacity(0.55), lineWidth: 1.5))
    }

    /// 0.5초 주기로 깜빡이는 밑줄 커서.
    private var blinkingCaret: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
            Text("_")
                .font(.myungjo(24))
                .foregroundStyle(KColor.cyan)
                .opacity(on ? 1 : 0)
        }
    }

    private func suggestionRow(_ item: (code: String, name: String)) -> some View {
        let selected = matches(item.name)
        return Button {
            name = item.name
        } label: {
            HStack(spacing: 10) {
                Text(item.code)
                    .font(.led(13))
                    .foregroundStyle(selected ? Color(hex: 0x0c3a6b) : KColor.cyan)
                    .frame(width: 54, alignment: .leading)
                Text(item.name)
                    .font(.myungjo(16))
                    .foregroundStyle(selected ? Color(hex: 0x06223f) : .white)
                Spacer()
                Text("모드")
                    .font(.myungjoLight(13))
                    .foregroundStyle(selected ? Color(hex: 0x06223f) : KColor.yellow.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? KColor.cyan : .clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: 하단 액션바

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text("\(name.count)/\(maxNameLength)")
                .font(.led(13))
                .foregroundStyle(KColor.cyan)
            Spacer()
            actionButton("취소", color: Color(hex: 0x4a5568)) { onClose() }
            actionButton("완료", color: KColor.green, enabled: isValid) { if isValid { save() } }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
    }

    private func actionButton(_ title: String, color: Color, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.myungjo(16))
                .foregroundStyle(enabled ? .white : .white.opacity(0.4))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(enabled ? color : Color.white.opacity(0.1))
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func save() {
        guard isValid else { return }
        preset.name = String(trimmed.prefix(maxNameLength))
        try? modelContext.save()
        onSave()
        onClose()
    }
}
