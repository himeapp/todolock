import SwiftUI
import SwiftData
import FamilyControls
import WidgetKit

/// 노래방 리모컨 컨셉의 홈 화면. 앱 실행 시 첫 화면.
/// 숫자패드로 시간(HHMM) 입력 → 모드/앱/과제 설정 → 시작으로 잠금 세션 시작.
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
    @State private var errorMessage: String?
    @State private var taskExecutionSessionId: UUID?
    @State private var editingPreset: SessionPreset?

    /// 막힌 시작 버튼을 눌렀을 때 잠깐 보여주는 안내. 일정 시간 뒤 사라진다.
    @State private var blockHint: String?
    /// 안내가 오류(빨강)인지 알림(틸)인지. 감시를 걸었을 때의 확인 메시지는 틸로 보여준다.
    @State private var blockHintIsNotice = false
    /// 안내 자동 숨김 타이머 식별용. 연타 시 이전 타이머가 새 안내를 지우지 않게 한다.
    @State private var blockHintGeneration = 0
    /// 지금 감시가 걸려 있는지. 켜져 있으면 감시 버튼이 "오늘 감시 끄기"로 바뀐다.
    @State private var watchdogActive = LockWidgetBridge.readWatchdog() != nil

    /// 유저가 마지막으로 사용한 잠금 시간(초). 기본값 1시간.
    @AppStorage("lastDurationSeconds") private var lastDurationSeconds: Int = 60 * 60
    /// "점수 제거" — 켜져 있으면 완주 축하(콘페티+100점)도 함께 끈다.
    @AppStorage("hideKaraokeScore") private var hideKaraokeScore = false

    @Environment(\.scenePhase) private var scenePhase
    /// 잠금이 끝나는 순간(포그라운드)에도 잠금 화면이 닫히고 축하가 뜨도록 1초 틱을 관찰.
    @ObservedObject private var ticker = Ticker.shared
    /// 지금 축하 화면을 띄울 완주 세션. nil이면 축하 없음.
    @State private var celebrationSessionID: UUID?

    private var activeSessions: [Session] { sessions.filter { $0.isActive } }

    /// 지금 선택된 모드(=곡). 시작 확인 화면이 이 이름을 곡 제목으로 보여준다.
    private var activePreset: SessionPreset? { presets.first { $0.id == vm.activePresetID } }

    var body: some View {
        NavigationStack {
            ZStack {
                // 뒤: 실제 잠금화면과 같은 노래방 CRT TV 배경.
                KaraokeBackground().ignoresSafeArea()

                // 위: 노래방 TV. 평소엔 "선곡 대기", 시작을 누르면 그 자리에서
                // "이 곡을 부르시겠습니까?" 확인 화면으로 바뀐다(빈 네모가 morph).
                // 아래: 리모컨. 평소엔 풀 리모컨(키패드), 시작을 누르면 아래로 빠지며
                // 슬림 리모컨("잠그는 중")으로 전환된다.
                VStack(spacing: 0) {
                    tvArea
                        .padding(.top, 30)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    bottomRemote
                }
                // 곡 정보 편집은 위 TV 안 디지털 패널(.songInfo 페이지)로 들어오고
                // 리모컨은 아래로 빠지므로, 그 키보드가 올라와도 뒤 화면은 밀리지 않게.
                .ignoresSafeArea(.keyboard, edges: .bottom)

                // 잠금을 끝까지 버틴 직후 앱에 들어오면 콘페티+100점을 한 번 터뜨린다.
                if celebrationSessionID != nil {
                    KaraokeScoreScreen(onContinue: { celebrationSessionID = nil })
                        .transition(.opacity)
                        .zIndex(2)
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
            .onAppear {
                setupPresets()
                checkCelebration()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { checkCelebration() }
            }
            // 시간·앱 변경 즉시 active preset에 자동저장 — 피커/StateObject 재생성 후에도 복원.
            .onChange(of: vm.digits) { _, _ in saveToPreset() }
            .onChange(of: vm.selection) { _, _ in saveToPreset() }
            // 포그라운드에서 잠금이 막 끝났을 때(활성 세션이 비는 순간)도 축하를 띄운다.
            .onChange(of: activeSessions.isEmpty) { _, empty in
                if empty { checkCelebration() }
            }
            .animation(.easeInOut(duration: 0.3), value: celebrationSessionID)
            .onReceive(deepLink.$pendingSessionId) { id in
                guard let id else { return }
                // 잠금이 활성이면 잠금 화면(LockScreenView)이 점프(곡목록)를 직접 연다.
                // 풀스크린 커버에 가려 시트가 안 보이므로 여기선 건드리지 않는다.
                // 잠금이 없는 상태(만료된 알림을 뒤늦게 탭 등)에서만 과제 화면을 띄운다.
                guard activeSessions.isEmpty else { return }
                taskExecutionSessionId = id
                deepLink.clear()
            }
        }
    }

    // MARK: - 위쪽 TV 영역 (선곡 대기 ↔ 시작 확인)

    /// 위쪽 노래방 TV. 평소엔 "선곡 대기"(KaraokeStandbyTV), 시작을 누르면 같은 자리에서
    /// "이 곡을 부르시겠습니까?" 확인 화면으로 바뀐다. 리모컨이 슬림으로 빠지며 생긴
    /// 공간을 확인 화면이 채운다.
    @ViewBuilder private var tvArea: some View {
        switch page {
        case .keypad:
            KaraokeStandbyTV()
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .start:
            StartConfirmSheet(
                songTitle: activePreset?.displayTitle ?? "곡 미정",
                songNumber: (activePreset?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "—",
                selection: vm.selection,
                durationClock: durationClock(vm.totalSeconds),
                onStart: { go(to: .keypad); start() },
                onCancel: { go(to: .keypad) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .songInfo:
            // 곡 정보(별칭·곡 제목)도 카드 팝업이 아니라 TV 화면 속 디지털 패널로 들어온다.
            // 리모컨이 아래로 빠지며 생긴 공간에 노래찾기 패널이 떠오른다.
            if let preset = editingPreset {
                ModeNameEditor(
                    preset: preset,
                    onSave: { },
                    onClose: { closeSongInfo() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    // MARK: - 하단 리모컨 (풀 ↔ 슬림)

    /// 아래 리모컨. 평소엔 풀 리모컨(키패드), 시작을 누르면 아래로 빠지며 슬림 리모컨으로
    /// 전환된다. 둘 다 아래 가장자리로 드나들어 "삭 빠지고 새로 올라오는" 느낌을 준다.
    @ViewBuilder private var bottomRemote: some View {
        switch page {
        case .keypad:
            fullRemote
                .transition(.move(edge: .bottom))
        case .start, .songInfo:
            // 시작 확인·곡 정보 화면에선 하단 리모컨을 아래로 빼고 띄우지 않는다.
            // TV 안 디지털 화면이 전체를 쓰며, 취소/시작·완료는 그 안의 액션바가 담당한다.
            EmptyView()
        }
    }

    /// 크림 보디 + 하늘색 테두리 + 비닐막. 안에 LED·기능·숫자패드·시작을 모은다. (핸들 없음)
    private var fullRemote: some View {
        VStack(spacing: 13) {
            header
            keypadPage
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(alignment: .top) { remoteBody }
    }

    /// 크림 보디 + 하늘색 테두리 + 비닐막 — 풀 리모컨의 바탕.
    private var remoteBody: some View {
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

    // MARK: - 리모컨 안의 페이지들

    /// 기본 페이지 — LED·기능키·숫자패드·시작.
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
            // 작아진 키들이 위로 모이도록 남는 높이는 아래 여백으로. (숫자패드 상단과 정렬 유지)
            Spacer(minLength: 0)
        }
    }

    private func presetButton(_ preset: SessionPreset) -> some View {
        // 감시 모드일 땐 곡 하이라이트를 끈다 — 리모컨에선 곡/감시 중 하나만 켜진 것처럼 보이게.
        // (activePresetID 자체는 보존하므로 잠금 모드로 돌아오면 곡 선택이 되살아난다.)
        PresetButton(alias: preset.name, selected: vm.mode != .watchdog && vm.activePresetID == preset.id) {
            if vm.activePresetID == preset.id {
                // 이미 선택된 곡을 다시 누르면: 리모컨이 내려가고 곡 정보가 TV 안으로 들어온다.
                editingPreset = preset
                go(to: .songInfo)
            } else {
                vm.load(preset)
            }
        }
        // 감시 모드일 땐 곡 키들이 한 발 물러나 보이도록 살짝 흐린다. (여전히 누를 순 있음)
        .opacity(vm.mode == .watchdog ? 0.45 : 1)
        .disabled(vm.mode == .watchdog)
        .animation(.easeInOut(duration: 0.2), value: vm.mode)
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
        // 곡 키와 같이, 감시 모드일 땐 점프도 한 발 물러나 보이게 살짝 흐린다.
        .opacity(vm.mode == .watchdog ? 0.45 : 1)
        .disabled(vm.mode == .watchdog)
        .animation(.easeInOut(duration: 0.2), value: vm.mode)
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
            ? (count == 0 ? "하루 사용량\n제한할 앱" : "하루 사용량\n제한할 앱 · \(count)")
            : (count == 0 ? "잠글 앱\n관리" : "잠글 앱\n관리 · \(count)")
        let colors = watchdog
            ? [Color(hex: 0x2bb5a4), Color(hex: 0x15897b)]
            : [Color(hex: 0xec5743), Color(hex: 0xd23522)]
        return Text(title)
            .multilineTextAlignment(.center)
            .lineSpacing(1)
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 18).fill(
                    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.16), radius: 2.5, y: 1.5)
            )
            .overlay(alignment: .top) { keycapGloss(radius: 18) }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.12), lineWidth: 1))
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
        // 잠금=노랑 "시 작 ▶", 감시=검정 "오늘부터 감시 걸기 ▶"(이미 걸렸으면 "오늘 감시 끄기").
        let watchdog = vm.mode == .watchdog
        let label = watchdog
            ? (watchdogActive ? "오늘 감시 끄기" : "오늘부터 감시 걸기 ▶")
            : "시 작 ▶"
        // 감시가 켜져 있으면 끄기는 항상 가능. 아니면 설정 유효성으로 활성화.
        let enabled = watchdog ? (watchdogActive || vm.canSaveWatchdog) : vm.canStart
        // 막혔을 때도 탭은 받아서 안내를 띄운다(.disabled 이면 탭이 안 들어옴).
        return Button(action: watchdog ? tapWatchdogStart : tapStart) {
            Text(label)
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
                .opacity(enabled ? 1 : 0.45)
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

    /// 감시 걸기/끄기 탭. 이미 걸려 있으면 끄고, 아니면 곧장 건다(확인 시트 없음).
    private func tapWatchdogStart() {
        if watchdogActive {
            stopWatchdog()
        } else if vm.canSaveWatchdog {
            startWatchdog()
        } else if let reason = vm.watchdogBlockReason {
            showBlockHint(reason)
        }
    }

    /// 키패드 ↔ 시작 확인 전환. 리모컨은 아래로 빠지고(슬림화) 위 TV는 확인 화면으로
    /// 바뀐다. 한 번의 스프링으로 위·아래가 함께 움직이게 묶는다.
    private func go(to newPage: RemotePage) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            page = newPage
        }
    }

    /// 곡 정보 화면 닫기 — 키패드로 되돌리고(리모컨 복귀), 전환이 끝난 뒤 편집 대상 비움.
    /// 사라지는 패널이 빈 화면으로 깜빡이지 않도록 스프링이 끝날 즈음에 nil 처리한다.
    private func closeSongInfo() {
        go(to: .keypad)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if page == .keypad { editingPreset = nil }
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

    /// 감시를 건다. 하루 한도를 DeviceActivity에 등록하고, 끝나면 잠금 모드로 돌아오며 확인을 띄운다.
    private func startWatchdog() {
        let limitMinutes = vm.watchdogTotalSeconds / 60
        do {
            // 매일 반복 한도 모니터링 등록 — 한도 초과 시 익스텐션이 그 앱들을 차단한다.
            try ActivityScheduler.shared.scheduleWatchdog(
                selection: vm.watchdogSelection,
                limitMinutes: limitMinutes
            )
        } catch {
            showBlockHint("감시 예약에 실패했어요: \(error.localizedDescription)")
            return
        }
        // 위젯 "감시 중" 상태 공유.
        LockWidgetBridge.writeWatchdog(WatchdogWidgetState(
            appCount: watchdogSelectionCount,
            dailyLimitMinutes: limitMinutes,
            startedAt: Date()
        ))
        WidgetCenter.shared.reloadAllTimelines()
        watchdogActive = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { vm.mode = .lock }
        showBlockHint("감시를 걸었어요 · 하루 \(durationText(vm.watchdogTotalSeconds))", isNotice: true)
    }

    /// 감시 해제 — 모니터링 중단 + 차단 즉시 해제 + 위젯 상태 정리.
    private func stopWatchdog() {
        ActivityScheduler.shared.cancelWatchdog()
        ManagedSettingsController.shared.clearWatchdogShield()
        LockWidgetBridge.foldWatchdogDays()   // 켜뒀던 기간을 누적 감시 일수에 더한 뒤
        LockWidgetBridge.clearWatchdog()
        WidgetCenter.shared.reloadAllTimelines()
        watchdogActive = false
        showBlockHint("감시를 껐어요", isNotice: true)
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
            // preset에 저장된 시간·앱을 복원한다 (자동저장으로 항상 최신 상태).
            vm.load(first)
        }
    }

    /// 현재 입력(시간·앱)을 active preset에 저장한다. 앱 선택 또는 시간이 바뀔 때마다 호출.
    private func saveToPreset() {
        guard let preset = activePreset else { return }
        vm.applyToPreset(preset)
        lastDurationSeconds = vm.totalSeconds
        try? modelContext.save()
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

    /// LED 디스플레이와 같은 일:시:분 표기(DD:HH:MM)로 잠금 시간을 보여준다.
    /// 리모컨 LED의 DAY·HOUR·MIN 배치와 동일 — 초 단위는 의미 없으므로 생략.
    private func durationClock(_ seconds: Int) -> String {
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        return String(format: "%02d:%02d:%02d", d, h, m)
    }

    /// 완주한 세션이 있으면 축하 화면을 띄운다(점수 제거가 켜져 있으면 조용히 넘긴다).
    /// 활성 세션이 떠 있는 동안엔(잠금 화면이 덮고 있으니) 잠시 미룬다.
    private func checkCelebration() {
        guard celebrationSessionID == nil, activeSessions.isEmpty else { return }
        // sessions는 최신순 정렬 — 가장 최근에 완주한 대기 세션을 고른다.
        guard let session = sessions.first(where: {
            !$0.isActive && KaraokeCelebrationTracker.isPending($0.id)
        }) else { return }

        // 한 번만 — 점수 제거든 축하든 대기 목록에서 비운다.
        KaraokeCelebrationTracker.consume(session.id)
        guard !hideKaraokeScore else { return }
        celebrationSessionID = session.id
    }

    private func start() {
        let store = SessionStore(modelContext: modelContext)
        do {
            // 시작한 시간을 다음 실행 때 다시 보여주도록 저장.
            lastDurationSeconds = vm.totalSeconds
            _ = try store.start(
                endsAt: vm.endsAt,
                selection: vm.selection,
                passDurationMinutes: vm.passDurationMinutes,
                title: activePreset?.displayTitle ?? "",
                nickname: activePreset?.name ?? ""
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

/// 화면 상태. keypad=풀 리모컨+선곡 대기 TV, start=슬림 리모컨+시작 확인 TV.
/// 감시는 별도 페이지가 아니라 키패드 페이지의 한 "모드"로 동작한다(vm.mode).
private enum RemotePage { case keypad, start, songInfo }

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

// MARK: - 시작 전 확인 화면 ("이 곡을 부르시겠습니까?")

/// 시작을 누르면 위 노래방 TV 자리(선곡 대기)가 이 확인 화면으로 바뀐다.
/// 카드 팝업이 아니라 **노래방 TV 화면 속 디지털 UI** — 뒤 CRT 배경 위에 곡 헤더·
/// 큰 곡 제목(=모드명)·"이 곡을 부르시겠습니까?"·곡목록(잠글 앱)·취소/시작을 직접 얹어,
/// 노래방 인트로(KaraokeIntroView)와 같은 화면 언어로 보이게 한다.
/// 앱 이름은 FamilyControls 프라이버시상 문자열로 못 빼므로 `Label(token)`으로만 렌더링한다.
private struct StartConfirmSheet: View {
    /// 선곡된 곡 제목 = 활성 모드 이름.
    let songTitle: String
    /// 곡목록 위에 보일 곡 번호(노래방 차트 룩).
    let songNumber: String
    let selection: FamilyActivitySelection
    /// 위젯 카운트다운과 같은 시계 표기(HH:MM:SS).
    let durationClock: String
    let onStart: () -> Void
    let onCancel: () -> Void

    private var appCount: Int { selection.applicationTokens.count }
    private var categoryCount: Int { selection.categoryTokens.count }
    private var webCount: Int { selection.webDomainTokens.count }
    private var totalCount: Int { appCount + categoryCount + webCount }

    /// 곡목록은 곡 수에 맞춰 크기를 잡고, 많아지면 그 안에서 스크롤한다.
    /// (maxHeight:.infinity로 화면 전체를 먹어 빈 목록이 거대해지던 문제를 막는다.)
    private var songListHeight: CGFloat {
        let rowHeight: CGFloat = 44
        let visibleRows = min(max(totalCount, 1), 5)
        return CGFloat(visibleRows) * rowHeight
    }

    var body: some View {
        // 헤더는 위, 액션은 아래에 고정하고 곡 제목·곡목록 블록은 남는 공간 한가운데에
        // 띄워 화면 전체(특히 그동안 비어 있던 아래쪽)를 고르게 쓴다.
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                KaraokeSongList(selection: selection)
                    .frame(height: songListHeight)
            }

            Spacer(minLength: 16)

            noteDivider
                .padding(.bottom, 18)
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 노래방 인트로처럼 음표 장식 한 줄 — 비어 보이던 아래 공간을 곡 분위기로 채운다.
    private var noteDivider: some View {
        HStack(spacing: 16) {
            ForEach([KColor.cyan, KColor.pink, KColor.yellow, KColor.green], id: \.self) { c in
                Image(systemName: "music.note")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(c)
                    .shadow(color: c.opacity(0.7), radius: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: 곡 헤더 (선곡 박스 + 기간 칩)

    private var header: some View {
        HStack(spacing: 10) {
            NowPlayingBox(
                tag: "선곡",
                tagColor: KColor.green,
                title: songNumber,
                subtitle: "\(totalCount)곡 선곡"
            )
            Spacer(minLength: 8)
            durationChip
        }
    }

    /// 위젯 "남은 시간"과 같은 표현 — 어두운 패널 위 7세그(DSEG7) 호박색 시계.
    private var durationChip: some View {
        HStack(spacing: 8) {
            Text("부를 시간")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
            Text(durationClock)
                .font(.seg7(15))
                .foregroundStyle(KColor.yellow)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.05, green: 0.06, blue: 0.20).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.6)
        )
    }

    // MARK: 곡 제목 (모드명) + 확인 문구 — 노래방 인트로 룩

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "music.mic")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(KColor.cyan)
                Text("이 곡을 부르시겠습니까?")
                    .font(.led(13))
                    .foregroundStyle(KColor.cyan)
                    .shadow(color: KColor.cyan.opacity(0.6), radius: 6)
            }
            OutlinedText(text: songTitle, size: 34, fill: KColor.yellow, strokeWidth: 6)
        }
    }

    // MARK: 액션 (취소 / 이 곡 부르기 ▶)

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button { onCancel() } label: { Text("취소") }
                .buttonStyle(KaraokeButtonStyle(color: Color(hex: 0x44506a)))
                .frame(width: 104)

            Button { onStart() } label: { Text("이 곡 부르기 ▶") }
                .buttonStyle(KaraokeButtonStyle(color: KColor.green))
        }
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
                Text(title).font(.system(size: 16, weight: .black))
                if let arrow { Text(arrow).font(.system(size: 14, weight: .bold)).opacity(0.9) }
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(gradient)
                    .shadow(color: .black.opacity(0.16), radius: 2.5, y: 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.12), lineWidth: 1))
            .overlay(alignment: .top) { keycapGloss(radius: 16) }
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
    /// 짧은 별칭 — 작은 곳(리모컨 버튼)엔 이것만 노래방 곡번호처럼 보여준다.
    /// 곡 풀네임은 버튼에 안 쓰고, 눌러서 여는 확인화면·편집 팝업에서만 크게 보인다.
    let alias: String
    let selected: Bool
    let action: () -> Void

    private var hasAlias: Bool { !alias.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected {
                    Circle().fill(Color(hex: 0xe8853a)).frame(width: 5, height: 5)
                }
                // 별칭 = 곡번호 룩(모노스페이스 파랑). 없으면 옅은 "곡 미정".
                Text(hasAlias ? alias : "곡 미정")
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundStyle(hasAlias ? Color(hex: 0x3f73bd) : Color(hex: 0x1a1a1a).opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(
                    LinearGradient(colors: [Color(hex: 0xf4eedd), Color(hex: 0xe6dcc3)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.16), radius: 2.5, y: 1.5)
            )
            .overlay(alignment: .top) { keycapGloss(radius: 16) }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Color(hex: 0x3f73bd) : .black.opacity(0.12),
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

/// 선택된 곡을 다시 탭하면 뜨는 작은 창. 곡 제목(풀네임)과 별칭(번호 룩)을 함께 정한다.
/// 옛날 노래방 노래찾기 화면을 본떠 파란 타이틀바·돋보기 원형 아이콘·CRT 다크 입력창·
/// 추천 곡목록·하단 액션바로 구성한다.
private struct ModeNameEditor: View {
    @Environment(\.modelContext) private var modelContext
    let preset: SessionPreset
    let onSave: () -> Void
    let onClose: () -> Void

    private enum Field { case title, alias }

    /// 곡 제목(풀네임) + 별칭(번호 룩).
    @State private var songTitle: String = ""
    @State private var alias: String = ""
    @FocusState private var focusedField: Field?

    /// 곡 제목 최대 글자수. 확인화면·위젯에 들어가는 한도 안에서 가능한 길게.
    private let maxTitleLength = 24
    /// 별칭 최대 글자수 — 버튼에 곡번호처럼 작게 들어가야 하므로 짧게.
    private let maxAliasLength = 5

    /// 노래찾기 곡목록처럼 보이는 추천 곡 제목 + 가짜 곡번호.
    /// TV 안 패널은 키보드 위 공간이 좁아 3줄만 둔다(분위기용 장식).
    private let suggestions: [(code: String, title: String)] = [
        ("24433", "그대 없는 1시간"),
        ("91405", "공부의 신"),
        ("53997", "마감 직전")
    ]

    private var trimmedTitle: String { songTitle.trimmingCharacters(in: .whitespaces) }
    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespaces) }
    /// 별칭·곡 제목 중 하나만 있어도 저장 가능(둘 다 비면 막는다).
    private var isValid: Bool { !trimmedAlias.isEmpty || !trimmedTitle.isEmpty }
    /// 곡 제목이 한도까지 찼는지 — 입력이 막혔음을 알리는 데 쓴다.
    private var titleAtLimit: Bool { songTitle.count >= maxTitleLength }

    /// 입력 글자로 추천 곡을 고른다.
    /// 앞글자 일부("마"→마감 직전)나 초성("ㅁㄱ")이 들어맞으면 선택된 것으로 본다.
    private func matches(_ candidate: String) -> Bool {
        let q = trimmedTitle
        guard !q.isEmpty else { return false }
        if candidate.hasPrefix(q) { return true }
        return Self.chosung(of: candidate).hasPrefix(Self.chosung(of: q))
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
        // 어두운 스크림·플로팅 카드 없이, TV 화면 위에 떠오른 노래찾기 디지털 패널.
        // 리모컨이 내려가며 생긴 공간 위쪽에 자리잡고, 아래는 CRT 배경을 그대로 둔다.
        VStack(spacing: 0) {
            titleBar
            bodyArea
            bottomBar
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(
                LinearGradient(colors: [Color(hex: 0x12203a), Color(hex: 0x0a1326)],
                               startPoint: .top, endPoint: .bottom)
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x2d4f86), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // 떠 있는 카드가 아니라 화면 속에서 빛나는 패널처럼 보이도록 청록 글로우만 옅게.
        .shadow(color: KColor.cyan.opacity(0.18), radius: 14)
        .onAppear {
            songTitle = preset.songTitle
            alias = preset.name
            // 팝업 등장과 키보드를 한 모션으로 묶기 위해 지연 없이 다음 런루프에서 바로 포커스.
            // 별칭이 위라 별칭부터 잡는다.
            DispatchQueue.main.async { focusedField = .alias }
        }
    }

    // MARK: 파란 타이틀바

    private var titleBar: some View {
        HStack(spacing: 10) {
            searchCircle
            OutlinedText(text: "곡 정보", size: 19,
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

    // MARK: 본문 (곡 제목 입력 + 별칭 입력 + 추천 곡목록)

    private var bodyArea: some View {
        VStack(spacing: 8) {
            // 별칭(작은 곳에 뜨는 번호)을 위로, 곡 제목을 아래로.
            aliasField
            titleField

            // 곡 제목이 한도까지 찼을 때만 막혔음을 알린다.
            if titleAtLimit {
                Text("곡 제목은 최대 \(maxTitleLength)자까지 쓸 수 있어요")
                    .font(.myungjoLight(12))
                    .foregroundStyle(KColor.pink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, item in
                    suggestionRow(item)
                }
            }
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .animation(.easeOut(duration: 0.2), value: titleAtLimit)
    }

    /// 곡 제목(풀네임) — 노래찾기 화면처럼 큰 명조 + 밑줄 커서.
    private var titleField: some View {
        HStack(spacing: 8) {
            Text("가")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(KColor.pink))

            ZStack(alignment: .leading) {
                Group {
                    if songTitle.isEmpty && focusedField != .title {
                        Text("곡 제목 입력")
                            .font(.myungjoLight(20))
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        HStack(spacing: 1) {
                            Text(songTitle)
                                .font(.myungjo(24))
                                .foregroundStyle(.white)
                            if focusedField == .title { blinkingCaret(size: 24) }
                        }
                    }
                }
                .allowsHitTesting(false)

                TextField("", text: $songTitle)
                    .font(.myungjo(24))
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { if isValid { save() } }
                    .onChange(of: songTitle) { _, newValue in
                        if newValue.count > maxTitleLength {
                            songTitle = String(newValue.prefix(maxTitleLength))
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !songTitle.isEmpty {
                Button { songTitle = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.45))
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
            }
            counter(songTitle.count, max: maxTitleLength)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(fieldBackground)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke((titleAtLimit ? KColor.pink : KColor.cyan).opacity(focusedField == .title ? 0.85 : 0.4), lineWidth: 1.5))
    }

    /// 별칭(번호 룩) — 버튼에 곡번호처럼 들어가는 짧은 식별자. 모노스페이스 청록.
    private var aliasField: some View {
        HStack(spacing: 8) {
            Text("별칭")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(KColor.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.35)))

            ZStack(alignment: .leading) {
                Group {
                    if alias.isEmpty && focusedField != .alias {
                        Text("곡 미정")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    } else {
                        HStack(spacing: 1) {
                            Text(alias)
                                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                                .foregroundStyle(KColor.cyan)
                            if focusedField == .alias { blinkingCaret(size: 17) }
                        }
                    }
                }
                .allowsHitTesting(false)

                TextField("", text: $alias)
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .focused($focusedField, equals: .alias)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .title }
                    .onChange(of: alias) { _, newValue in
                        if newValue.count > maxAliasLength {
                            alias = String(newValue.prefix(maxAliasLength))
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            counter(alias.count, max: maxAliasLength)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(fieldBackground)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(KColor.cyan.opacity(focusedField == .alias ? 0.8 : 0.4), lineWidth: 1.5))
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8).fill(
            RadialGradient(colors: [Color(hex: 0x0d1322), Color(hex: 0x05080f)],
                           center: .center, startRadius: 1, endRadius: 220)
        )
    }

    /// 0.5초 주기로 깜빡이는 밑줄 커서.
    private func blinkingCaret(size: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
            Text("_")
                .font(.myungjo(size))
                .foregroundStyle(KColor.cyan)
                .opacity(on ? 1 : 0)
        }
    }

    /// 입력칸 우측 글자수 카운터 — 한도에 닿으면 분홍으로 바꿔 "막혔다"를 알린다.
    private func counter(_ count: Int, max: Int) -> some View {
        Text("\(count)/\(max)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(count >= max ? KColor.pink : .white.opacity(0.4))
    }

    /// 추천 곡 한 줄 — 탭하면 곡 제목을 채운다. (별칭은 그대로 둠)
    private func suggestionRow(_ item: (code: String, title: String)) -> some View {
        let selected = matches(item.title)
        return Button {
            songTitle = String(item.title.prefix(maxTitleLength))
        } label: {
            HStack(spacing: 10) {
                Text(item.code)
                    .font(.led(13))
                    .foregroundStyle(selected ? Color(hex: 0x0c3a6b) : KColor.cyan)
                    .frame(width: 54, alignment: .leading)
                Text(item.title)
                    .font(.myungjo(16))
                    .foregroundStyle(selected ? Color(hex: 0x06223f) : .white)
                    .lineLimit(1)
                Spacer()
                Text("곡")
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
            // 글자수는 각 입력칸 우측 카운터가 보여주므로, 여기선 비었을 때만 안내한다.
            if !isValid {
                Text("별칭이나 곡 제목 중 하나는 채워주세요")
                    .font(.myungjoLight(12))
                    .foregroundStyle(KColor.pink)
            }
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
        preset.name = String(trimmedAlias.prefix(maxAliasLength))
        preset.songTitle = String(trimmedTitle.prefix(maxTitleLength))
        try? modelContext.save()
        onSave()
        onClose()
    }
}
