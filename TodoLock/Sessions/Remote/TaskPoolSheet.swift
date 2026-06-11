import SwiftUI
import SwiftData
import FamilyControls

/// 리모컨 초록 "과업/점프" 버튼이 여는 자주 쓰는 과업 풀 화면. (노래방 네온 룩)
/// 단일 과업 목록(타이머/사진). 잠긴 앱을 열면 이 중 하나를 즉시 수행한다.
struct TaskPoolSheet: View {
    /// 글리치 프레젠테이션에서 닫기를 가로채기 위한 콜백. 없으면 기본 dismiss 사용.
    var onClose: (() -> Void)? = nil
    /// 잠금 화면 위에 띄울 때 true. 풀스크린 대신 위로 잠금 화면이 비치는 둥근 카드로 그린다.
    var asCard: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.useCount, order: .reverse) private var tasks: [TaskItem]

    @State private var editingTask: TaskItem?
    @State private var runningTask: TaskItem?
    @State private var creatingNew = false

    var body: some View {
        presentationBody
            .onAppear(perform: seedIfNeeded)
            .sheet(isPresented: $creatingNew) { TaskEditorView() }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            // 과업을 끝내면 실행 화면뿐 아니라 이 과업 목록까지 함께 닫아 가사 화면으로 돌아간다.
            .sheet(item: $runningTask) { TaskRunView(task: $0, onFinished: closeSheet) }
    }

    /// asCard면 위쪽 여백으로 잠금 화면이 비치는 둥근 카드, 아니면 화면을 꽉 채운다.
    @ViewBuilder private var presentationBody: some View {
        if asCard {
            VStack(spacing: 0) {
                Spacer(minLength: 70)   // 위 여백 — 그 아래로 잠금 화면이 비친다
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if tasks.isEmpty {
                            OutlinedText(text: "등록된 과업이 없어요.\n아래에서 만들어보세요.",
                                         size: 18, alignment: .leading)
                        } else {
                            ForEach(tasks) { task in
                                TaskPoolCard(
                                    task: task,
                                    onRun: { runningTask = task },
                                    onEdit: { editingTask = task }
                                )
                            }

                            // 진짜 주 동작은 "하나 골라 ▶". 리스트 끝에 가볍게 짚어준다.
                            Label("하나를 골라 ▶ 를 누르면 바로 시작해요", systemImage: "hand.point.up.left.fill")
                                .font(.myungjoLight(13))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 40)
                    .padding(.bottom, 16)
                }

                // 보조 동작: 과업이 없을 때만 초록 강조(첫 사용자 안내), 평소엔 옅은 고스트
                // 버튼으로 둬서 재생(▶)이 주 동작임을 흐리지 않는다.
                Group {
                    if tasks.isEmpty {
                        Button { creatingNew = true } label: {
                            Label("새 과업 만들기", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(KaraokeButtonStyle(color: KColor.green))
                    } else {
                        Button { creatingNew = true } label: {
                            Label("새 과업 만들기", systemImage: "plus.circle")
                                .font(.myungjo(15))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 13)
                                        .stroke(.white.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
    }

    private var header: some View {
        HStack {
            NowPlayingBox(
                tag: "과업",
                tagColor: KColor.green,
                title: "점프 과업 목록",
                subtitle: "하나를 끝내면 15분 점프!"
            )
            Spacer()
            Button { closeSheet() } label: {
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

    private func closeSheet() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func seedIfNeeded() {
        if tasks.isEmpty {
            for t in TaskItem.seeds() { modelContext.insert(t) }
        }
        #if targetEnvironment(simulator)
        // 시뮬레이터에서 100점 흐름을 빨리 확인할 수 있도록 3초짜리 테스트 과업을 보장.
        if !tasks.contains(where: { $0.name == "⏱ 테스트 3초" }) {
            modelContext.insert(TaskItem(name: "⏱ 테스트 3초", kind: .timer, timerSeconds: 3))
        }
        #endif
        try? modelContext.save()
    }
}

/// 과업 풀 카드 한 줄. 탭하면 바로 실행, 우측 연필로 수정.
private struct TaskPoolCard: View {
    let task: TaskItem
    let onRun: () -> Void
    let onEdit: () -> Void

    private var accent: Color { task.kind == .timer ? KColor.cyan : KColor.pink }

    var body: some View {
        HStack(spacing: 11) {
            // 주 동작: 카드 전체를 탭하면 바로 실행. 우측의 큰 재생 버튼으로 강조.
            Button(action: onRun) {
                HStack(spacing: 13) {
                    Image(systemName: task.kind.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 11).fill(accent.opacity(0.18))
                        )
                    Text(task.name).font(.myungjo(20)).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(accent))
                        .shadow(color: accent.opacity(0.55), radius: 11)
                }
            }
            .buttonStyle(.plain)

            // 보조 동작: 수정. 작고 옅게 두어 재생을 방해하지 않도록.
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1))
        )
    }
}

/// 풀에서 과업을 탭하면 뜨는 실행 화면. 수행 → 100점 점수판(15분 사용 안내) → 가사 화면 복귀.
private struct TaskRunView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem
    /// 과업을 끝내고 빠져나갈 때 호출. 이 실행 화면뿐 아니라 그 아래 곡목록(풀)까지 함께 닫는다.
    var onFinished: () -> Void

    @Query(sort: \Session.createdAt, order: .reverse) private var sessions: [Session]
    @AppStorage("hideKaraokeScore") private var hideKaraokeScore = false
    @State private var taskDone = false
    @State private var granted = false
    /// 타이머 도전 중 X를 누르면 뜨는 "이대로 포기할래요?" 확인 알럿.
    @State private var showGiveUpAlert = false
    /// 점프 성공으로 임시 해제된 시간(분)·앱 목록. 설정되면 점수판이 한꺼번에 보여준다.
    @State private var unlockedMinutes: Int?
    @State private var unlockedSelection: FamilyActivitySelection?

    private var activeSessions: [Session] { sessions.filter { $0.isActive } }
    private var passMinutes: Int { activeSessions.first?.passDurationMinutes ?? 15 }

    var body: some View {
        ZStack {
            NeonBlurBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 22) {
                        Text("♪  이 과업을 해요  ♪")
                            .font(.led(11))
                            .foregroundStyle(KColor.yellow)
                            .shadow(color: KColor.yellow.opacity(0.5), radius: 5)

                        OutlinedText(text: task.name, size: 26, fill: .white, alignment: .center)

                        if task.kind == .timer {
                            TimerTaskView(seconds: task.timerSeconds, rewardMinutes: passMinutes) { markDone() }
                        } else {
                            PhotoTaskView(category: task.verifyCategory) { markDone() }
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: taskDone)
                    .padding(.horizontal, 22)
                    .padding(.top, 48)
                    .padding(.bottom, 12)
                }
            }

            // 과업 성공 → 100점 + "딱 15분만 사용할 수 있어요"를 카드로. 바깥을 탭하면 닫혀 가사 화면으로.
            if let minutes = unlockedMinutes, let selection = unlockedSelection {
                KaraokeScoreScreen(unlockMinutes: minutes, unlockSelection: selection) {
                    onFinished()
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: unlockedMinutes)
        .alert("이대로 도전을 포기할까요?", isPresented: $showGiveUpAlert) {
            Button("계속하기", role: .cancel) {}
            Button("포기하기", role: .destructive) { dismiss() }
        } message: {
            Text("진행 중인 과업이 사라져요. 간주 점프 15분을 받을 수 없어요.")
        }
    }

    /// 타이머 도전이 아직 끝나지 않았으면 X로 닫을 때 확인 알럿을 먼저 띄운다.
    private func closeRequested() {
        if task.kind == .timer && !taskDone {
            showGiveUpAlert = true
        } else {
            dismiss()
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button { closeRequested() } label: {
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

    private func markDone() {
        guard !taskDone else { return }
        taskDone = true
        // 성공하면 곧장 사용권을 준다. "점수 제거"가 꺼져 있으면 100점 점수판(N분 안내)을, 켜져 있으면 곧장 닫는다.
        grantPass(celebrate: !hideKaraokeScore)
    }

    /// 활성 세션에 임시 해제를 부여한다. celebrate면 점수판을 띄우고, 아니면 곧장 닫는다.
    private func grantPass(celebrate: Bool) {
        // 이미 점프 중인 세션은 건너뛴다. (재점프 방지)
        let grantable = activeSessions.filter {
            TempUnlockController.shared.activeExpiry(for: $0, modelContext: modelContext) == nil
        }

        if !granted && !grantable.isEmpty {
            granted = true
            let store = SessionStore(modelContext: modelContext)
            task.useCount += 1
            for session in grantable {
                store.recordPass(session)
                modelContext.insert(CompletionRecord(sessionId: session.id, summary: task.name))
                for token in session.selection.applicationTokens {
                    TempUnlockController.shared.grantTempAccess(
                        session: session,
                        unlockToken: token,
                        modelContext: modelContext
                    )
                }
                // 간주 동안 잠금 시계는 멈춰야 한다 — 종료 시각을 간주 길이만큼 미룬다.
                TempUnlockController.shared.extendLockForInterlude(session: session, modelContext: modelContext)
            }
            try? modelContext.save()
        }

        if celebrate, let session = grantable.first {
            unlockedSelection = session.selection
            withAnimation(.easeInOut(duration: 0.3)) { unlockedMinutes = session.passDurationMinutes }
        } else {
            onFinished()
        }
    }
}

/// 과업 생성/편집. (노래방 네온 룩) 타입(타이머/사진)에 따라 입력이 달라진다.
struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existing: TaskItem?
    @State private var name: String
    @State private var kind: TaskKind
    /// 오른쪽부터 채우는 MMSS 입력 버퍼(최대 4자리). 예: "3000" → 30:00.
    @State private var timerDigits: String
    @State private var category: VerifyCategory

    init(task: TaskItem? = nil) {
        self.existing = task
        _name = State(initialValue: task?.name ?? "")
        _kind = State(initialValue: task?.kind ?? .timer)
        _timerDigits = State(initialValue: Self.digits(fromSeconds: task?.timerSeconds ?? 1800))
        _category = State(initialValue: task?.verifyCategory ?? .exercise)
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if kind == .timer { return isTimerValid }
        return true
    }

    // MARK: - 타이머 숫자 입력 (MM:SS, 오른쪽부터 채우는 4자리 레지스터)

    /// 0으로 채운 4자리 MMSS. 비어 있으면 0000.
    private var paddedTimerDigits: String {
        String(repeating: "0", count: max(0, 4 - timerDigits.count)) + timerDigits
    }
    private var timerMinutesField: Int { Int(paddedTimerDigits.prefix(2)) ?? 0 }
    private var timerSecondsField: Int { Int(paddedTimerDigits.suffix(2)) ?? 0 }
    private var timerTotalSeconds: Int { timerMinutesField * 60 + timerSecondsField }

    /// 설정 가능한 최대 길이(초). 60분.
    private static let maxTimerSeconds = 60 * 60

    /// LED 표시용 MM:SS. 실행 화면 시계와 같은 분:초 형식으로 통일.
    private var timerClock: String { "\(paddedTimerDigits.prefix(2)):\(paddedTimerDigits.suffix(2))" }

    /// 초가 0~59이고, 0보다 길고, 60분을 넘지 않아야 유효.
    private var isTimerValid: Bool {
        timerSecondsField < 60 && timerTotalSeconds > 0 && timerTotalSeconds <= Self.maxTimerSeconds
    }

    private var timerHint: String {
        if timerSecondsField >= 60 { return "초는 0~59 사이로 입력해주세요." }
        if timerTotalSeconds > Self.maxTimerSeconds { return "최대 60분까지 설정할 수 있어요." }
        return "타이머가 끝날 때까지 화면에 머물러야 통과해요."
    }

    private func pushTimerDigit(_ d: Int) {
        timerDigits = String((timerDigits + String(d)).suffix(4))
    }
    private func backTimerDigit() {
        guard !timerDigits.isEmpty else { return }
        timerDigits.removeLast()
    }

    /// 초 → MMSS 4자리 문자열 (편집 시작 시 기존 값 복원용). 최대 60:00으로 클램프.
    private static func digits(fromSeconds seconds: Int) -> String {
        let clamped = max(0, min(maxTimerSeconds, seconds))
        return String(format: "%02d%02d", clamped / 60, clamped % 60)
    }

    var body: some View {
        ZStack {
            NeonBlurBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        field(label: "이름") {
                            TextField("", text: $name,
                                      prompt: Text("예: 30분 독서").foregroundStyle(.white.opacity(0.35)))
                                .font(.myungjo(18))
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(darkCard)
                        }

                        field(label: "종류") {
                            HStack(spacing: 10) {
                                ForEach(TaskKind.allCases) { k in
                                    SelectChip(
                                        title: k.title,
                                        symbol: k.symbol,
                                        accent: k == .timer ? KColor.cyan : KColor.pink,
                                        selected: kind == k
                                    ) { kind = k }
                                }
                            }
                        }

                        if kind == .timer {
                            field(label: "타이머") {
                                VStack(spacing: 12) {
                                    TimerLEDDisplay(text: timerClock, valid: isTimerValid)
                                    NeonNumPad(onDigit: pushTimerDigit,
                                               onBack: backTimerDigit,
                                               onClear: { timerDigits = "" })
                                    Text(timerHint)
                                        .font(.myungjoLight(12))
                                        .foregroundStyle((timerSecondsField >= 60 || timerTotalSeconds > Self.maxTimerSeconds) ? KColor.pink : .white.opacity(0.55))
                                }
                            }
                        } else {
                            field(label: "사진 검수") {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(VerifyCategory.allCases) { c in
                                        CategoryRow(category: c, selected: category == c) {
                                            category = c
                                        }
                                    }
                                    Text("기기 안에서 Vision AI가 사진을 판정해요.")
                                        .font(.myungjoLight(12)).foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 10) {
                    Button { save() } label: {
                        Text(existing == nil ? "만들기" : "저장")
                    }
                    .buttonStyle(KaraokeButtonStyle(color: KColor.green, enabled: isValid))
                    .disabled(!isValid)

                    if existing != nil {
                        Button(role: .destructive) { deleteTask() } label: {
                            Label("이 과업 삭제", systemImage: "trash")
                                .font(.myungjo(15))
                                .foregroundStyle(KColor.pink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
        }
    }

    private var header: some View {
        HStack {
            OutlinedText(text: existing == nil ? "새 과업" : "과업 편집", size: 24, alignment: .leading)
            Spacer()
            Button { dismiss() } label: {
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

    private var darkCard: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.3))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.led(11))
                .foregroundStyle(KColor.yellow)
                .shadow(color: KColor.yellow.opacity(0.5), radius: 5)
            content()
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let timer = max(0, timerTotalSeconds)
        if let task = existing {
            task.name = trimmed
            task.kind = kind
            task.timerSeconds = timer
            task.verifyCategory = category
        } else {
            let task = TaskItem(name: trimmed, kind: kind, timerSeconds: timer, verifyCategory: category)
            modelContext.insert(task)
        }
        try? modelContext.save()
        dismiss()
    }

    private func deleteTask() {
        if let task = existing {
            modelContext.delete(task)
            try? modelContext.save()
        }
        dismiss()
    }
}

// MARK: - 편집기 구성요소

/// 종류 선택용 큰 칩 (타이머 / 사진).
private struct SelectChip: View {
    let title: String
    let symbol: String
    let accent: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                Text(title).font(.myungjo(16))
            }
            .foregroundStyle(selected ? accent : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(selected ? accent.opacity(0.18) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(selected ? accent : .white.opacity(0.15),
                                    lineWidth: selected ? 2 : 1)
                    )
            )
            .shadow(color: selected ? accent.opacity(0.4) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
    }
}

/// 사진 검수 카테고리 한 줄 (운동 기구 / 책 / 하늘·나무).
private struct CategoryRow: View {
    let category: VerifyCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? KColor.pink : .white.opacity(0.4))
                Text(category.title).font(.myungjo(17)).foregroundStyle(.white)
                Spacer()
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? KColor.pink.opacity(0.14) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? KColor.pink : .white.opacity(0.13),
                                    lineWidth: selected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// 분:초 LED 디스플레이 (네온 룩). 실행 화면 시계와 같은 MM:SS 형식.
private struct TimerLEDDisplay: View {
    let text: String
    let valid: Bool

    private var color: Color { valid ? KColor.cyan : KColor.pink }

    var body: some View {
        Text(text)
            .font(.led(46))
            .monospacedDigit()
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.6), radius: 10)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1))
            )
    }
}

/// 네온 룩 숫자패드 (리모컨 스타일). 오른쪽부터 채워 MM:SS를 입력한다.
private struct NeonNumPad: View {
    let onDigit: (Int) -> Void
    let onBack: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3) { row in
                HStack(spacing: 8) {
                    ForEach(1..<4) { col in
                        let n = row * 3 + col
                        digitKey(n)
                    }
                }
            }
            HStack(spacing: 8) {
                iconKey("xmark", accent: KColor.pink, action: onClear)
                digitKey(0)
                iconKey("delete.left", accent: .white.opacity(0.85), action: onBack)
            }
        }
    }

    private func digitKey(_ n: Int) -> some View {
        Button { onDigit(n) } label: {
            Text("\(n)")
                .font(.led(26))
                .foregroundStyle(KColor.cyan)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(keyBackground)
        }
        .buttonStyle(.plain)
    }

    private func iconKey(_ symbol: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(keyBackground)
        }
        .buttonStyle(.plain)
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
