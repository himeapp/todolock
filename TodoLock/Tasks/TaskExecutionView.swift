import SwiftUI
import SwiftData
import FamilyControls

/// Shield → 딥링크로 잠긴 앱을 열었을 때 표시되는 과제 수행 화면. (노래방 "점프")
/// 개념: 전역 과제 풀에서 하나를 골라 즉시 수행하면 곡을 "점프"하고 보너스 시간을 받는다.
/// 타이머형은 끝까지 버티기, 사진형은 촬영→온디바이스 검수. 중간에 나가면(이탈) 잠금 유지.
struct TaskExecutionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let sessionId: UUID

    @Query(sort: \TaskItem.useCount, order: .reverse) private var tasks: [TaskItem]

    @AppStorage("hideKaraokeScore") private var hideKaraokeScore = false

    @State private var selectedTaskId: UUID?
    @State private var taskDone = false
    @State private var hasRecordedAttempt = false
    @State private var unlockedMinutes: Int?
    @State private var unlockedSelection: FamilyActivitySelection?

    private var session: Session? {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
        return try? modelContext.fetch(descriptor).first
    }

    private var selectedTask: TaskItem? {
        guard let id = selectedTaskId else { return nil }
        return tasks.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            NeonBlurBackground()
            if let session {
                content(session: session)
                    .onAppear { recordAttempt(session) }
            } else {
                OutlinedText(text: "세션을 찾을 수 없어요", size: 26, alignment: .center)
            }

            if let minutes = unlockedMinutes, let selection = unlockedSelection {
                Group {
                    if !hideKaraokeScore {
                        KaraokeScoreScreen(unlockMinutes: minutes, unlockSelection: selection) { dismiss() }
                    } else {
                        JumpSuccessScreen(minutes: minutes, selection: selection) { dismiss() }
                    }
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: unlockedMinutes)
    }

    @ViewBuilder
    private func content(session: Session) -> some View {
        VStack(spacing: 0) {
            header(session: session)

            if let expiry = TempUnlockController.shared.activeExpiry(for: session, modelContext: modelContext) {
                alreadyJumping(until: expiry)
            } else if let task = selectedTask {
                perform(session: session, task: task)
            } else {
                picker
            }
        }
    }

    /// 이미 점프(임시 해제) 중일 때: 재점프를 막고 남은 시간만 안내.
    private func alreadyJumping(until expiry: Date) -> some View {
        let remaining = max(1, Int(ceil(expiry.timeIntervalSinceNow / 60)))
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.open.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(KColor.green)
                .shadow(color: KColor.green.opacity(0.7), radius: 16)
            OutlinedText(text: "이미 점프 중이에요", size: 24, fill: .white, alignment: .center)
            Text("\(remaining)분 남았어요. 끝나면 다시 점프할 수 있어요.")
                .font(.myungjoLight(14))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Spacer()
            Button { dismiss() } label: { Text("앱 열러 가기 ▶") }
                .buttonStyle(KaraokeButtonStyle(color: KColor.green, enabled: true))
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 22)
    }

    private func header(session: Session) -> some View {
        HStack {
            NowPlayingBox(
                tag: "점프",
                tagColor: KColor.pink,
                title: karaokeNumber(session.id),
                subtitle: "완료하면 \(session.passDurationMinutes)분 점프"
            )
            Spacer()
            Button {
                if selectedTaskId != nil {
                    selectedTaskId = nil   // 과제 선택 화면으로 뒤로
                    taskDone = false
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: selectedTaskId != nil ? "chevron.left" : "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    // MARK: - 과제 선택 (전역 풀)

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("♪  곡을 점프하려면 과제 하나를 해요  ♪")
                    .font(.led(11))
                    .foregroundStyle(KColor.yellow)
                    .shadow(color: KColor.yellow.opacity(0.5), radius: 5)

                if tasks.isEmpty {
                    OutlinedText(text: "등록된 과제이 없어요.\n리모컨에서 과제을 추가해주세요.",
                                 size: 18, alignment: .leading)
                } else {
                    ForEach(tasks) { task in
                        Button {
                            selectedTaskId = task.id
                            taskDone = false
                        } label: {
                            taskCard(task)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
    }

    private func taskCard(_ task: TaskItem) -> some View {
        HStack(spacing: 13) {
            Image(systemName: task.kind.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(task.kind == .timer ? KColor.cyan : KColor.pink)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill((task.kind == .timer ? KColor.cyan : KColor.pink).opacity(0.18))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(task.name).font(.myungjo(19)).foregroundStyle(.white)
                Text(task.subtitle).font(.myungjoLight(13)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1))
        )
    }

    // MARK: - 과제 수행

    @ViewBuilder
    private func perform(session: Session, task: TaskItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    Text("♪  이 곡을 점프하려면  ♪")
                        .font(.led(11))
                        .foregroundStyle(KColor.yellow)
                        .shadow(color: KColor.yellow.opacity(0.5), radius: 5)

                    OutlinedText(text: task.name, size: 26, fill: .white, alignment: .center)

                    if task.kind == .timer {
                        TimerTaskView(seconds: task.timerSeconds, rewardMinutes: session.passDurationMinutes) { markDone() }
                    } else {
                        PhotoTaskView(category: task.verifyCategory) { markDone() }
                    }

                    Text(task.kind == .timer
                         ? "끝까지 있어야 통과돼요. 지금 나가면 이탈 · 잠금 유지."
                         : "사진이 통과하면 점프돼요. 안 찍고 나가면 잠금 유지.")
                        .font(.myungjoLight(13))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: taskDone)
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 12)
            }

            Button {
                complete(session: session, task: task)
            } label: {
                Text(taskDone ? "\(session.passDurationMinutes)분 점프 ▶" : "과제을 마치면 점프돼요")
            }
            .buttonStyle(KaraokeButtonStyle(color: KColor.green, enabled: taskDone))
            .disabled(!taskDone)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 동작

    private func markDone() {
        guard !taskDone else { return }
        taskDone = true
    }

    private func recordAttempt(_ session: Session) {
        guard !hasRecordedAttempt else { return }
        hasRecordedAttempt = true
        SessionStore(modelContext: modelContext).recordAttempt(session)
    }

    private func complete(session: Session, task: TaskItem) {
        // 이미 점프 중이면 새로 풀지 않는다. (재점프 방지 안전망)
        guard TempUnlockController.shared.activeExpiry(for: session, modelContext: modelContext) == nil else { return }

        let store = SessionStore(modelContext: modelContext)
        store.recordPass(session)

        task.useCount += 1
        modelContext.insert(CompletionRecord(sessionId: session.id, summary: task.name))
        try? modelContext.save()

        for token in session.selection.applicationTokens {
            TempUnlockController.shared.grantTempAccess(
                session: session,
                unlockToken: token,
                modelContext: modelContext
            )
        }
        // 간주 동안 잠금 시계는 멈춰야 한다 — 종료 시각을 간주 길이만큼 미룬다.
        TempUnlockController.shared.extendLockForInterlude(session: session, modelContext: modelContext)
        unlockedSelection = session.selection
        withAnimation(.easeInOut(duration: 0.3)) {
            unlockedMinutes = session.passDurationMinutes
        }
    }
}

/// 점수 화면을 끈 경우의 점프 성공 화면.
/// 풀린 앱 목록(시작 화면과 같은 곡목록 컴포넌트)과 함께 "풀렸어요"를 보여준다.
private struct JumpSuccessScreen: View {
    let minutes: Int
    let selection: FamilyActivitySelection
    var onClose: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            NeonBlurBackground()

            VStack(spacing: 18) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(KColor.green)
                    .shadow(color: KColor.green.opacity(0.7), radius: 18)
                    .scaleEffect(appear ? 1 : 0.4)
                    .opacity(appear ? 1 : 0)
                    .padding(.top, 28)

                Text("♪  점프 성공!  ♪")
                    .font(.led(13))
                    .foregroundStyle(KColor.yellow)
                    .shadow(color: KColor.yellow.opacity(0.6), radius: 6)

                OutlinedText(text: "\(minutes)분 동안 풀렸어요", size: 26, fill: .white, alignment: .center)

                KaraokeSongList(selection: selection)
                    .padding(.horizontal, 22)

                Text("시간이 끝나면 다시 잠겨요.")
                    .font(.myungjoLight(13))
                    .foregroundStyle(.white.opacity(0.55))

                Button { onClose() } label: {
                    Text("앱 열러 가기 ▶")
                }
                .buttonStyle(KaraokeButtonStyle(color: KColor.green, enabled: true))
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true }
        }
    }
}
