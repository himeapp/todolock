import SwiftUI

/// 페이월에서 안심 팝업을 닫은 "딱 한 번" 전체화면으로 흐르는 앱 소개 투어.
/// 실제 동영상 대신, 주요 화면을 노래방 룩 포스터로 만들어 3초마다 페이드로 자동 전환한다.
/// (탭하면 다음으로 건너뛰고, 마지막 장면을 지나면 자동으로 닫힌다.)
struct ScreenTourView: View {
    var onFinish: () -> Void

    @State private var index = 0
    @State private var generation = 0   // 자동 전환 타이머 식별 — 탭으로 건너뛰면 이전 타이머 무효화.

    /// 장면당 머무는 시간(초). 천천히 음미할 수 있게 넉넉히.
    private let perSlide: Double = 600

    private var slides: [TourSlide] { TourSlide.all }

    var body: some View {
        ZStack {
            // 배경은 점프 과업 화면(앱 아이콘)과 같은 파란 네온 룩.
            NeonBlurBackground()
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.15), .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // 떠다니는 음표 장식.
            noteDecorations

            // 포스터 + 설명을 위쪽으로 끌어올리고, 페이지 핸들은 바닥에 둔다.
            // (좌우 탭 안내 대신 스와이프로 넘긴다.)
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                // 포스터 + 설명을 한 덩어리로 세로 중앙에 둔다.
                // 4장 모두 같은 "노래방 모니터" 틀에 넣어 크기·위치를 고정한다.
                VStack(spacing: 24) {
                    TourStage {
                        slides[index].view
                            .id(index)
                            .transition(.opacity)
                    }
                    caption
                }
                Spacer(minLength: 20)
                pageHandle
                    .padding(.bottom, 30)
            }

            // 건너뛰기 버튼은 탭 가능해야 하므로 맨 위 레이어에 따로 둔다.
            VStack {
                topBar
                Spacer()
            }
        }
        // 좌우 스와이프로 앞·뒤 이동 (왼쪽으로 밀면 다음, 오른쪽으로 밀면 이전).
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -40 {
                        advance()
                    } else if value.translation.width > 40 {
                        goBack()
                    }
                }
        )
        .task(id: generation) { await autoAdvance() }
    }

    /// 하단 페이지 핸들 — 진행 점 + 그랩 핸들. 스와이프로 넘긴다.
    private var pageHandle: some View {
        VStack(spacing: 12) {
            progressDots
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 50, height: 5)
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
    }

    // MARK: 상단 (건너뛰기)

    private var topBar: some View {
        HStack {
            Spacer()
            Button { onFinish() } label: {
                Text("건너뛰기  ✕")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: 하단 (설명 + 진행 점)

    private var caption: some View {
        VStack(spacing: 14) {
            Text(slides[index].title)
                .font(.myungjo(23))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.7), radius: 3)
            Text(slides[index].subtitle)
                .font(.myungjoLight(16))
                .lineSpacing(7)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
        .id(index)
        .transition(.opacity)
        .padding(.horizontal, 30)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? KColor.highlight : .white.opacity(0.3))
                    .frame(width: i == index ? 20 : 7, height: 7)
                    .shadow(color: i == index ? KColor.highlight.opacity(0.7) : .clear, radius: 5)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
    }

    private var noteDecorations: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                note("music.note", KColor.cyan, x: 0.12, baseY: 0.30, t: t, speed: 0.6, amp: 10)
                note("music.note", KColor.pink, x: 0.86, baseY: 0.26, t: t, speed: 0.8, amp: 14)
                note("music.quarternote.3", KColor.yellow, x: 0.80, baseY: 0.62, t: t, speed: 0.5, amp: 12)
            }
        }
        .allowsHitTesting(false)
    }

    private func note(_ name: String, _ color: Color, x: CGFloat, baseY: CGFloat,
                      t: TimeInterval, speed: Double, amp: CGFloat) -> some View {
        GeometryReader { geo in
            Image(systemName: name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.7), radius: 8)
                .position(
                    x: geo.size.width * x,
                    y: geo.size.height * baseY + CGFloat(sin(t * speed)) * amp
                )
                .opacity(0.85)
        }
    }

    // MARK: 동작

    /// 다음 장면으로. 마지막을 지나면 투어를 닫는다.
    private func advance() {
        if index >= slides.count - 1 {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { index += 1 }
            generation += 1   // 자동 타이머 재시작.
        }
    }

    /// 이전 장면으로. 첫 장면이면 그대로 둔다(자동 진행만 다시 시작).
    private func goBack() {
        if index > 0 {
            withAnimation(.easeInOut(duration: 0.45)) { index -= 1 }
        }
        generation += 1   // 손으로 넘긴 직후엔 자동 타이머를 리셋해 갑자기 안 넘어가게.
    }

    private func autoAdvance() async {
        try? await Task.sleep(nanoseconds: UInt64(perSlide * 1_000_000_000))
        guard !Task.isCancelled else { return }
        advance()
    }
}

// MARK: - 투어 장면

/// 한 장면 = 일러스트 뷰 + 제목/설명.
private struct TourSlide {
    let title: String
    let subtitle: String
    let view: AnyView

    static let all: [TourSlide] = [
        TourSlide(
            title: "잠글 시간을 정해요",
            subtitle: "노래방 리모컨처럼 시간을 맞추고\n시작 버튼만 누르면 끝.",
            view: AnyView(RemotePoster())
        ),
        TourSlide(
            title: "앱이 잠겼어요",
            subtitle: "노래방 자막이 흐르는 건\n인내의 시간을 위로하는 거예요.",
            view: AnyView(LockPoster())
        ),
        TourSlide(
            title: "가끔 꼭 필요할 때",
            subtitle: "간주 점프를 눌러보세요.\n미리 정해놓은 과업 리스트가 떠요.",
            view: AnyView(JumpPoster())
        ),
        TourSlide(
            title: "간주 점프 성공!",
            subtitle: "점프를 성공하면\n딱 15분만 잠금을 해제할 수 있어요.",
            view: AnyView(ScorePoster())
        )
    ]
}

// MARK: - 공통 모니터 틀

/// 노래방 TV 한 대 느낌의 고정 크기 프레임. 장면이 바뀌어도 크기·위치가 그대로라
/// 아래 제목/설명이 출렁이지 않고, 4장이 "한 모니터 안의 화면들"로 묶여 보인다.
/// 배경(네온)과 또렷이 구분되도록 화면 안엔 지직이는 가로줄을, 테두리엔 진한 시안을 둔다.
private struct TourStage<Content: View>: View {
    @ViewBuilder var content: Content

    /// 배경 네온과 구분되는, TV임을 알리는 진한 시안 테두리.
    private let deepCyan = Color(red: 0.0, green: 0.66, blue: 0.74)
    private let corner: CGFloat = 22

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            // 어두운 화면 + 지직이는 가로줄 노이즈를 콘텐츠 뒤·앞에 깔아 CRT TV 느낌.
            .background(
                ZStack {
                    // 순흑이 아니라 살짝 시안기 도는 어두운 화면 — 검은 주사선이 보이도록.
                    Color(red: 0.02, green: 0.05, blue: 0.07)
                    TVStatic()
                }
            )
            .overlay(TVStatic().opacity(0.25))   // 콘텐츠 위로도 옅게 흘려 화면 전체가 지직이게.
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(deepCyan, lineWidth: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner - 3)
                    .stroke(KColor.cyan.opacity(0.55), lineWidth: 1)
                    .padding(3)                  // 안쪽 밝은 시안 림 — 모니터 베젤 광택.
            )
            .shadow(color: deepCyan.opacity(0.6), radius: 22)
            .padding(.horizontal, 44)
    }
}

/// TV 화면 안의 "지직" 노이즈 — 천천히 흐르는 가로 주사선 + 가끔 지나가는 트래킹 밴드.
/// (KaraokeBackground의 CRT 효과를 모니터 틀 안에 가둔 축소판.)
private struct TVStatic: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                // 가로 주사선이 천천히 위로 흐른다 (검은 줄이 화면을 어둑하게 가른다).
                Canvas { c, size in
                    let spacing: CGFloat = 3
                    let scroll = (t * 14).truncatingRemainder(dividingBy: Double(spacing))
                    var y = -spacing + CGFloat(scroll)
                    while y < size.height {
                        c.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: 1.3)),
                            with: .color(.black.opacity(0.32))
                        )
                        y += spacing
                    }
                }

                // 밝은 시안 주사선 + 트래킹 밴드는 화면을 밝히는 쪽이라 screen 블렌드.
                Canvas { c, size in
                    let spacing: CGFloat = 3
                    let scroll = (t * 14).truncatingRemainder(dividingBy: Double(spacing))
                    var y = -spacing + CGFloat(scroll)
                    while y < size.height {
                        c.fill(
                            Path(CGRect(x: 0, y: y + 1.3, width: size.width, height: 0.7)),
                            with: .color(KColor.cyan.opacity(0.08))
                        )
                        y += spacing
                    }

                    // 밝은 트래킹 밴드가 아래로 한 번씩 가로지른다 (지지직).
                    let period = size.height + 120
                    let top = CGFloat((t * 70).truncatingRemainder(dividingBy: Double(period))) - 60
                    let bandHeight: CGFloat = 44
                    var by = top
                    while by < top + bandHeight {
                        let d = abs((by - (top + bandHeight / 2)) / (bandHeight / 2))
                        let alpha = max(0, 0.20 * (1 - d))
                        c.fill(
                            Path(CGRect(x: 0, y: by, width: size.width, height: 1)),
                            with: .color(.white.opacity(alpha))
                        )
                        by += 2
                    }
                }
                .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 장면 일러스트 (실제 화면 요소 재사용)

/// 1. 리모컨 — LED 디스플레이로 시간 입력 화면을 떠올리게 한다.
private struct RemotePoster: View {
    var body: some View {
        VStack(spacing: 18) {
            // 잡다한 키 없이 시간 LED를 주인공으로 — "시간을 맞추고 시작"만 보여준다.
            LEDDisplay(days: "00", hours: "01", minutes: "30", digitSize: 42, showBars: false)
                .fixedSize()
            startCap
        }
        .frame(width: 232)
    }

    private var startCap: some View {
        Text("시 작 ▶")
            .font(.system(size: 27, weight: .black, design: .rounded))
            .tracking(8)
            .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.02))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(
                    LinearGradient(colors: [Color(red: 0.97, green: 1.0, blue: 0.37),
                                            Color(red: 0.91, green: 0.96, blue: 0.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(alignment: .top) { keycapGloss(radius: 14) }
            .shadow(color: Color(red: 0.88, green: 1.0, blue: 0.08).opacity(0.6), radius: 16)
    }
}

/// 2. 잠금 화면 — 노래방 자막 두 줄.
private struct LockPoster: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(KColor.cyan)
                .shadow(color: KColor.cyan.opacity(0.7), radius: 14)
            VStack(alignment: .leading, spacing: 10) {
                KaraokeLine(text: "그대 없는 한 시간 반", size: 23, progress: 0.62)
                KaraokeLine(text: "어떻게 버텨야 하나요", size: 23, progress: 0)
                    .opacity(0.9)
            }
            .padding(.horizontal, 24)
        }
    }
}

/// 3. 간주 점프 — 큰 점프 버튼 느낌.
private struct JumpPoster: View {
    var body: some View {
        VStack(spacing: 14) {
            OutlinedText(text: "간주 점프!", size: 29, fill: KColor.yellow, strokeWidth: 4)
            Text("타이머 · 사진 인증")
                .font(.myungjoLight(14))
                .foregroundStyle(.white.opacity(0.85))
            Text("점프 ▶▶")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.04, green: 0.15, blue: 0.02))
                .padding(.horizontal, 32)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(
                        LinearGradient(colors: [Color(red: 0.45, green: 0.79, blue: 0.31),
                                                Color(red: 0.33, green: 0.66, blue: 0.21)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                )
                .overlay(alignment: .top) { keycapGloss(radius: 14) }
                .shadow(color: KColor.green.opacity(0.6), radius: 16)
        }
    }
}

/// 4. 채점 — 기존 KaraokeScore 점수판 재사용.
private struct ScorePoster: View {
    var body: some View {
        KaraokeScore(score: 100, framed: false)
    }
}
