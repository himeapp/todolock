import SwiftUI
import FamilyControls

// 옛날 노래방 CRT TV 룩을 위한 공용 스타일 키트.
// - 배경: 저녁 풍경 그라데이션 + 가로 스캔라인(지글지글) + 미세 롤 애니메이션
// - 가사: AppleMyungjo(한글 명조) + 테두리 스트로크

enum KColor {
    static let outline = Color(red: 0.07, green: 0.09, blue: 0.42)   // 자막 테두리(레퍼런스 남색)
    static let fill = Color.white
    static let cyan = Color(red: 0.22, green: 0.91, blue: 0.91)
    static let highlight = Color(red: 0.16, green: 0.52, blue: 1.0)   // 가사 채움(노래방 파란색)
    static let green = Color(red: 0.11, green: 0.56, blue: 0.23)
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.23)
    static let pink = Color(red: 1.0, green: 0.23, blue: 0.42)
}

extension Font {
    /// 한글 명조체 — 번들된 나눔명조 ExtraBold (노래방 자막용 굵은 명조).
    static func myungjo(_ size: CGFloat) -> Font { .custom("NanumMyeongjoExtraBold", size: size) }
    /// 작은 캡션/부제용 가는 명조.
    static func myungjoLight(_ size: CGFloat) -> Font { .custom("NanumMyeongjo", size: size) }
    static func led(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
    /// 7세그먼트 디지털 숫자 — 번들된 DSEG7 Classic Bold (리모컨 LED 디스플레이용).
    static func seg7(_ size: CGFloat) -> Font { .custom("DSEG7Classic-Bold", size: size) }
}

// MARK: - 배경 (CRT 노래방 TV)

struct KaraokeBackground: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                scenery
                scanlines(t: t)
                trackingBand(t: t)
                vignette
            }
            .ignoresSafeArea()
        }
    }

    // 옛날 VHS 노래방 풍경: 옅고 푸르스름한 하늘 + 밝은 톤
    private var scenery: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.68, blue: 0.88),
                    Color(red: 0.60, green: 0.72, blue: 0.90),
                    Color(red: 0.65, green: 0.75, blue: 0.90),
                    Color(red: 0.52, green: 0.65, blue: 0.82),
                    Color(red: 0.48, green: 0.60, blue: 0.78)
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.40), .clear],
                center: UnitPoint(x: 0.5, y: 0.3), startRadius: 20, endRadius: 350
            )
            .blendMode(.screen)
        }
    }

    // 가로 주사선이 천천히 위로 흐른다 (지글지글)
    private func scanlines(t: TimeInterval) -> some View {
        Canvas { c, size in
            let spacing: CGFloat = 3
            let scroll = (t * 16).truncatingRemainder(dividingBy: Double(spacing))
            var y = -spacing + CGFloat(scroll)
            while y < size.height {
                c.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1.4)),
                    with: .color(.black.opacity(0.30))
                )
                c.fill(
                    Path(CGRect(x: 0, y: y + 1.4, width: size.width, height: 0.6)),
                    with: .color(.white.opacity(0.06))
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }

    // 트래킹 노이즈 밴드: 밝고 촘촘한 가로선 띠가 화면을 아래로 가로질러 지나간다
    private func trackingBand(t: TimeInterval) -> some View {
        Canvas { c, size in
            let period = size.height + 200
            let top = CGFloat((t * 95).truncatingRemainder(dividingBy: Double(period))) - 100
            let bandHeight: CGFloat = 64
            var y = top
            let spacing: CGFloat = 2
            while y < top + bandHeight {
                let d = abs((y - (top + bandHeight / 2)) / (bandHeight / 2))
                let alpha = max(0, 0.22 * (1 - d))
                c.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.white.opacity(alpha))
                )
                y += spacing
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    private var vignette: some View {
        RadialGradient(
            colors: [.clear, .black.opacity(0.55)],
            center: .center, startRadius: 180, endRadius: 520
        )
        .allowsHitTesting(false)
    }
}

// MARK: - 네온 블러 배경 (투두 화면용)

struct NeonBlurBackground: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                // 남색 기본 배경
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.08, blue: 0.30),
                        Color(red: 0.15, green: 0.10, blue: 0.35),
                        Color(red: 0.18, green: 0.12, blue: 0.40),
                        Color(red: 0.14, green: 0.09, blue: 0.32)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                // 네온 블러 원형 라이트들 (애니메이션 포함)
                GeometryReader { geo in
                    ZStack {
                        let lights: [(x: CGFloat, y: CGFloat, color: Color, speed: Double)] = [
                            (0.25, 0.30, Color(red: 0.0, green: 1.0, blue: 1.0), 1.5),
                            (0.75, 0.40, Color(red: 1.0, green: 0.0, blue: 1.0), 1.8),
                            (0.50, 0.70, Color(red: 0.0, green: 0.5, blue: 1.0), 1.2),
                            (0.15, 0.70, Color(red: 0.5, green: 1.0, blue: 0.0), 2.0),
                            (0.85, 0.60, Color(red: 1.0, green: 0.5, blue: 0.0), 1.6)
                        ]
                        ForEach(Array(lights.enumerated()), id: \.offset) { _, light in
                            let pulse = sin(t * light.speed) * 0.3 + 0.7
                            RadialGradient(
                                colors: [
                                    light.color.opacity(0.4 * pulse),
                                    light.color.opacity(0.2 * pulse),
                                    .clear
                                ],
                                center: .center, startRadius: 0, endRadius: 120 * pulse
                            )
                            .frame(width: 240 * pulse, height: 240 * pulse)
                            .position(x: geo.size.width * light.x, y: geo.size.height * light.y)
                        }
                    }
                    .blur(radius: 40)
                    .allowsHitTesting(false)
                }

                // 스캔라인 (잠금 화면과 동일)
                Canvas { c, size in
                    let spacing: CGFloat = 3
                    var y: CGFloat = 0
                    while y < size.height {
                        c.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: 1.4)),
                            with: .color(.black.opacity(0.25))
                        )
                        y += spacing
                    }
                }
                .allowsHitTesting(false)

                // 비네팅
                RadialGradient(
                    colors: [.clear, .black.opacity(0.50)],
                    center: .center, startRadius: 150, endRadius: 500
                )
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - 테두리 명조 자막

struct OutlinedText: View {
    let text: String
    var size: CGFloat
    var fill: Color = KColor.fill
    var stroke: Color = KColor.outline
    var strokeWidth: CGFloat = 5.5
    var alignment: TextAlignment = .leading

    private static let offsets: [CGSize] = {
        (0..<12).map { i in
            let a = Double(i) / 12 * 2 * .pi
            return CGSize(width: cos(a), height: sin(a))
        }
    }()

    var body: some View {
        ZStack {
            ForEach(Array(Self.offsets.enumerated()), id: \.offset) { _, off in
                base
                    .foregroundStyle(stroke)
                    .offset(x: off.width * strokeWidth, y: off.height * strokeWidth)
            }
            base.foregroundStyle(fill)
        }
    }

    private var base: some View {
        Text(text)
            .font(.myungjo(size))
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 한 줄 가사를 왼쪽부터 파란색으로 채우는 노래방 자막 한 줄.
/// `progress` 0→1 만큼 파란 글자가 흰 글자 위로 드러난다.
struct KaraokeLine: View {
    let text: String
    var size: CGFloat
    var progress: Double = 0      // 0...1, 채워진 비율
    var strokeWidth: CGFloat = 5

    var body: some View {
        OutlinedText(text: text, size: size, fill: .white, strokeWidth: strokeWidth)
            .overlay(alignment: .leading) {
                OutlinedText(text: text, size: size, fill: KColor.highlight, strokeWidth: strokeWidth)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: geo.size.width * max(0, min(1, progress)))
                        }
                    }
            }
    }
}

/// 두 줄만 보이는 노래방 자막. 슬라이드 없이, 한 줄을 다 부르면 두 줄이 통째로 다음 줄로
/// 교체된다. (윗줄=지금 부르는 줄, 아랫줄=다음 줄) → 줄 내용이 한 칸씩 바뀌며 올라가 보인다.
/// `position` = 흘러간 줄 수(정수부=현재 줄 인덱스, 소수부=현재 줄 진행도).
struct KaraokeLyricScroll: View {
    let lines: [String]
    var position: Double
    var size: CGFloat = 32
    var spacing: CGFloat = 12

    var body: some View {
        guard !lines.isEmpty else { return AnyView(EmptyView()) }
        let n = lines.count
        let idx = Int(position.rounded(.down))
        let f = position - Double(idx)
        // 윗줄(현재 줄)이 부르는 만큼 0→1로 파랗게 칠해진다.
        let fill = min(1, max(0, f))

        return AnyView(
            VStack(alignment: .leading, spacing: spacing) {
                KaraokeLine(text: lines[idx % n], size: size, progress: fill, strokeWidth: 5)
                KaraokeLine(text: lines[(idx + 1) % n], size: size, progress: 0, strokeWidth: 4)
                    .opacity(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }
}

// MARK: - 현재곡 박스 (좌상단)

struct NowPlayingBox: View {
    var tag: String
    var tagColor: Color = KColor.green
    var title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 0) {
            Text(tag)
                .font(.myungjo(14))
                .padding(.horizontal, 9)
                .frame(maxHeight: .infinity)
                .background(tagColor)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.led(18))
                    .foregroundStyle(KColor.cyan)
                if let subtitle {
                    Text(subtitle)
                        .font(.myungjoLight(12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .fixedSize()
        .background(Color.black.opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.5), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 게이지(남은 시간)

struct KaraokeGauge: View {
    var progress: Double  // 0...1 (지나간 비율)
    var label: String

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                        .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1.5))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [KColor.green, KColor.yellow, KColor.pink],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                        .padding(2)
                }
            }
            .frame(height: 12)

            Text(label)
                .font(.led(14))
                .foregroundStyle(KColor.yellow)
                .fixedSize()
        }
    }
}

// MARK: - 노래방 버튼

struct KaraokeButtonStyle: ButtonStyle {
    var color: Color = KColor.green
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.myungjo(19))
            .foregroundStyle(enabled ? KColor.outline : .white.opacity(0.5))
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(enabled ? color : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .shadow(color: enabled ? color.opacity(0.5) : .clear, radius: 18)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - 노래방 채점 점수판 (과제 성공)

/// 옛날 노래방처럼 과제을 마치면 "100점"이 뜨는 점수판.
struct KaraokeScore: View {
    var score: Int = 100
    /// 자체 카드(배경+테두리)를 그릴지. 투어 모니터 틀 안에 넣을 땐 꺼서 카드 중첩을 막는다.
    var framed: Bool = true
    @State private var pop = false

    var body: some View {
        VStack(spacing: 2) {
            Text("♪  채  점  ♪")
                .font(.led(12))
                .foregroundStyle(KColor.cyan)
                .shadow(color: KColor.cyan.opacity(0.7), radius: 6)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 78, weight: .black, design: .rounded))
                    .foregroundStyle(KColor.yellow)
                    .shadow(color: KColor.yellow.opacity(0.9), radius: 18)
                    .shadow(color: KColor.pink.opacity(0.6), radius: 30)
                Text("점")
                    .font(.myungjo(30))
                    .foregroundStyle(.white)
            }

            Text(score >= 100 ? "★  PERFECT  ★" : "★  GOOD  ★")
                .font(.led(15))
                .foregroundStyle(KColor.pink)
                .shadow(color: KColor.pink.opacity(0.8), radius: 8)
        }
        .padding(.vertical, framed ? 18 : 0)
        .padding(.horizontal, framed ? 34 : 0)
        .background {
            if framed {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.42))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(KColor.yellow.opacity(0.65), lineWidth: 2))
            }
        }
        .shadow(color: KColor.yellow.opacity(framed ? 0.4 : 0), radius: framed ? 26 : 0)
        .scaleEffect(pop ? 1 : 0.6)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = true }
        }
    }
}

// MARK: - 풀스크린 노래방 채점 화면 (과제 성공)

/// 실제 노래방 채점처럼 화면 전체를 덮으며 등장하는 점수판.
/// - 스테이지 배경 + 둘러싼 전구 아치(체이싱 점멸)
/// - "SCORE" 배너
/// - 0 → 점수로 카운트업하는 큰 숫자
/// - 점수대별 코멘트, 탭하면 닫힘
struct KaraokeScoreScreen: View {
    var score: Int = 100
    /// 점프 성공으로 임시 해제된 시간(분). nil이면 순수 점수 화면.
    var unlockMinutes: Int? = nil
    /// 해제된 앱 목록(잠갔던 것과 동일). 점수와 함께 한꺼번에 보여준다.
    var unlockSelection: FamilyActivitySelection? = nil
    var onContinue: () -> Void

    @State private var displayed: Double = 0
    @State private var bannerIn = false
    @State private var showCaption = false
    /// 색종이 축포를 쏜 기준 시각. 등장 때 한 번만 채워지고, 이후엔 다시 쏘지 않는다.
    @State private var confettiStart: TimeInterval? = nil

    private var verdict: (line1: String, line2: String, color: Color) {
        switch score {
        case 100:
            // 간주점프 성공 vs 잠금 완창 — 결과 문구를 다르게.
            let line2 = hasUnlock ? "간주를 얻었어요!" : "끝까지 버텨냈어요!"
            return ("★  PERFECT  ★", line2, KColor.yellow)
        case 90...99:    return ("★  EXCELLENT  ★", "이 정도면 가수님이세요~", KColor.cyan)
        case 70...89:    return ("♪  GOOD  ♪", "노래방 사장님도 인정!", KColor.green)
        default:         return ("이 점수 어쩌면 좋지?", "진짜 모르게쒸요~", KColor.pink)
        }
    }

    private var hasUnlock: Bool { unlockMinutes != nil }

    var body: some View {
        ZStack {
            stage
            if hasUnlock {
                // 점수 카드 바깥을 어둡게 깔아 둔다 — 카드만 떠 보여서, 바깥을
                // 탭하면 자연스럽게 닫히는 구조임을 안내 문구 없이 디자인으로 전한다.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onContinue() }
                unlockCard
            } else {
                scoreOnlyLayout
            }
            confettiLayer
        }
        .onAppear { runIntro() }
    }

    /// 순수 점수 화면: 화면 어디나 탭하면 계속.
    private var scoreOnlyLayout: some View {
        VStack(spacing: 18) {
            Spacer()
            scoreBanner
            marqueeRing
            verdictText(showLine2: true)
            Spacer()
            Text("화면을 탭하면 계속돼요 ▶")
                .font(.myungjoLight(14))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 40)
                .opacity(showCaption ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .onTapGesture { onContinue() }
    }

    /// 점수 + 해제 안내를 담은 떠 있는 카드. 바깥의 어두운 영역을 탭하면 닫힌다.
    /// 카드 자체는 탭을 흡수하고(스크롤·내용 보호) 닫히지 않는다.
    private var unlockCard: some View {
        ScrollView {
            VStack(spacing: 14) {
                scoreBanner.padding(.top, 6)
                marqueeRing.frame(height: 190)   // 목록 공간 확보 위해 살짝 축소
                verdictText(showLine2: false)
                if let minutes = unlockMinutes, let selection = unlockSelection {
                    unlockPanel(minutes: minutes, selection: selection)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 28, y: 12)
        .overlay(alignment: .topTrailing) {
            Button { onContinue() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 64)              // 위아래로 어두운 여백을 남겨 카드처럼 떠 보이게
    }

    // 카드 바탕: 무대와 같은 남보라 계열이되 한 단계 밝게 — 카드가 도드라져 보이도록.
    private var cardBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.11, blue: 0.34),
                Color(red: 0.16, green: 0.13, blue: 0.42),
                Color(red: 0.10, green: 0.10, blue: 0.30)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// 🔓 해제 시간 + 풀린 앱 목록(시작 화면과 동일한 곡목록 컴포넌트).
    private func unlockPanel(minutes: Int, selection: FamilyActivitySelection) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(KColor.green)
                OutlinedText(text: "딱 \(minutes)분만 사용할 수 있어요", size: 19, fill: .white,
                             stroke: KColor.outline, strokeWidth: 3.5)
            }
            .padding(.top, 28)
            KaraokeSongList(selection: selection)
                .frame(maxHeight: 220)
        }
        .opacity(showCaption ? 1 : 0)
    }

    private func runIntro() {
        confettiStart = Date.timeIntervalSinceReferenceDate   // 점수 등장 순간 한 번만 축포
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { bannerIn = true }
        withAnimation(.easeOut(duration: 1.4).delay(0.35)) { displayed = Double(score) }
        withAnimation(.easeIn(duration: 0.4).delay(1.9)) { showCaption = true }
    }

    // 무대 배경: 짙은 남보라 + 천천히 도는 빛줄기(샤인) + 흩날리는 색종이
    private var stage: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.20),
                        Color(red: 0.10, green: 0.08, blue: 0.32),
                        Color(red: 0.06, green: 0.06, blue: 0.22)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                lightRays(t: t)
            }
            .ignoresSafeArea()
        }
    }

    // 축포 색종이는 카드 위로도 쏟아지도록 최상단 레이어로 둔다(탭은 통과).
    private var confettiLayer: some View {
        TimelineView(.animation) { ctx in
            confetti(t: ctx.date.timeIntervalSinceReferenceDate)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // 점수판 뒤에서 천천히 도는 빛줄기(샤인). 은은하게 화면을 받쳐준다.
    private func lightRays(t: TimeInterval) -> some View {
        Canvas { c, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.40)
            let reach = max(size.width, size.height) * 1.2
            let rays = 14
            let rot = t * 0.22
            for i in 0..<rays {
                let a0 = Double(i) / Double(rays) * 2 * .pi + rot
                let a1 = a0 + (.pi / Double(rays)) * 0.9
                var p = Path()
                p.move(to: center)
                p.addLine(to: CGPoint(x: center.x + CGFloat(cos(a0)) * reach,
                                      y: center.y + CGFloat(sin(a0)) * reach))
                p.addLine(to: CGPoint(x: center.x + CGFloat(cos(a1)) * reach,
                                      y: center.y + CGFloat(sin(a1)) * reach))
                p.closeSubpath()
                c.fill(p, with: .color(.white.opacity(0.05)))
            }
        }
        .blur(radius: 12)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    // 색종이가 위에서 한 번 쏟아진다 — PERFECT 축포. 등장 직후 1회만, 다 떨어지면 사라진다.
    private func confetti(t: TimeInterval) -> some View {
        Canvas { context, size in
            guard let start = confettiStart else { return }
            let elapsed = t - start
            let duration = 3.2                 // 축포가 완전히 사라질 때까지의 시간
            guard elapsed >= 0, elapsed < duration else { return }

            let colors: [Color] = [KColor.yellow, KColor.pink, KColor.cyan,
                                   KColor.green, Color(red: 1.0, green: 0.6, blue: 0.1)]
            let count = 60
            for i in 0..<count {
                let r1 = abs((sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1))
                let r2 = abs((sin(Double(i) * 78.233) * 12543.21).truncatingRemainder(dividingBy: 1))
                let speed = 320.0 + r2 * 260.0          // 위에서 아래로 단번에 쏟아지는 속도
                let startY = -40.0 - r1 * 260.0         // 화면 위쪽에 살짝 흩뿌려 출발
                let y = startY + speed * elapsed
                if y > Double(size.height) + 40 { continue }   // 바닥을 지나면 더 안 그림
                let x = r1 * size.width + sin(elapsed * 2 + Double(i)) * 20
                let spin = elapsed * 5 + Double(i)
                let color = colors[i % colors.count]
                let w: CGFloat = 7
                let h: CGFloat = 11 * CGFloat(abs(cos(spin))) + 2   // 뒤집히며 떨어지는 두께 변화
                let fade = elapsed > duration - 0.6
                    ? max(0, (duration - elapsed) / 0.6) : 1.0     // 끝에서 부드럽게 페이드아웃
                var c = context
                c.translateBy(x: x, y: CGFloat(y))
                c.rotate(by: .radians(spin))
                c.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)),
                       with: .color(color.opacity(0.85 * fade)))
            }
        }
        .allowsHitTesting(false)
    }

    // "SCORE" 리본 배너
    private var scoreBanner: some View {
        Text("S C O R E")
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(.white)
            .shadow(color: KColor.outline, radius: 0, x: 1.5, y: 1.5)
            .padding(.horizontal, 34)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [KColor.yellow, Color(red: 1.0, green: 0.6, blue: 0.1)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 2.5))
            )
            .shadow(color: KColor.yellow.opacity(0.6), radius: 16)
            .scaleEffect(bannerIn ? 1 : 0.5)
            .opacity(bannerIn ? 1 : 0)
            .padding(.vertical, 16)
    }

    // 전구가 둘러싼 원형 아치 + 가운데 카운트업 숫자
    private var marqueeRing: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                // 점멸하는 전구 링 (체이싱)
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = side / 2 - 14
                    let count = 28
                    let chase = Int((t * 9).truncatingRemainder(dividingBy: Double(count)))
                    ForEach(0..<count, id: \.self) { i in
                        let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
                        let on = (i % 3) == (chase % 3)
                        Circle()
                            .fill(on ? KColor.yellow : Color.white.opacity(0.30))
                            .frame(width: 10, height: 10)
                            .shadow(color: on ? KColor.yellow.opacity(0.9) : .clear, radius: 7)
                            .position(
                                x: center.x + CGFloat(cos(a)) * radius,
                                y: center.y + CGFloat(sin(a)) * radius
                            )
                    }
                }
                // 가운데 카운트업 숫자
                AnimatableNumber(number: displayed)
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        colors: [KColor.yellow, Color(red: 1.0, green: 0.7, blue: 0.2)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: KColor.yellow.opacity(0.9), radius: 18)
                    .shadow(color: KColor.pink.opacity(0.5), radius: 30)
            }
        }
        .frame(width: 240, height: 240)
    }

    private func verdictText(showLine2: Bool) -> some View {
        VStack(spacing: 6) {
            Text(verdict.line1)
                .font(.led(18))
                .foregroundStyle(verdict.color)
                .shadow(color: verdict.color.opacity(0.8), radius: 8)
            if showLine2 {
                Text(verdict.line2)
                    .font(.myungjo(20))
                    .foregroundStyle(.white)
            }
        }
        .opacity(showCaption ? 1 : 0)
        .scaleEffect(showCaption ? 1 : 0.8)
        .padding(.vertical, 14)
    }
}

// MARK: - 곡목록(앱 목록) 공통 컴포넌트

/// 노래방 곡목록처럼 보이는 앱/분류/웹 목록.
/// 시작 확인 화면(잠글 목록)과 점프 성공 화면(풀린 목록)이 공유한다.
struct KaraokeSongList: View {
    let selection: FamilyActivitySelection

    private var appCount: Int { selection.applicationTokens.count }
    private var categoryCount: Int { selection.categoryTokens.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(selection.applicationTokens.enumerated()), id: \.element) { idx, token in
                    KaraokeSongRow(number: Self.songCode(idx), tag: "") { Label(token) }
                }
                ForEach(Array(selection.categoryTokens.enumerated()), id: \.element) { idx, token in
                    KaraokeSongRow(number: Self.songCode(appCount + idx), tag: "분류") { Label(token) }
                }
                ForEach(Array(selection.webDomainTokens.enumerated()), id: \.element) { idx, token in
                    KaraokeSongRow(number: Self.songCode(appCount + categoryCount + idx), tag: "웹") { Label(token) }
                }
            }
        }
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    /// 곡번호처럼 보이는 가짜 5자리 코드. 인덱스로 고정 — 매번 같은 값.
    static func songCode(_ idx: Int) -> String {
        String(format: "%05d", 24400 + (idx * 1373) % 75000)
    }
}

/// 곡목록 한 줄: 곡번호 + 앱(아이콘/이름) + 우측 종류 태그.
/// `Label(token)`은 FamilyControls가 그리므로 다크 환경을 강제해 흰 글씨로 보이게 한다.
struct KaraokeSongRow<Content: View>: View {
    let number: String
    let tag: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.led(13))
                .foregroundStyle(KColor.cyan)
                .frame(width: 54, alignment: .leading)
            content
                .labelStyle(.titleAndIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            // 앱은 태그를 비워 깔끔하게, 분류/웹만 라벨로 구분한다.
            if !tag.isEmpty {
                Text(tag)
                    .font(.myungjoLight(13))
                    .foregroundStyle(KColor.yellow.opacity(0.9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
        }
    }
}

/// 정수 카운트업을 부드럽게 그리는 애니메이터블 텍스트.
struct AnimatableNumber: View, Animatable {
    var number: Double
    var animatableData: Double {
        get { number }
        set { number = newValue }
    }
    var body: some View {
        Text("\(Int(number.rounded()))")
            .monospacedDigit()
    }
}

// 세션 id → 노래방 곡 번호
func karaokeNumber(_ id: UUID) -> String {
    String(format: "№%04d", abs(id.hashValue % 10000))
}

// MARK: - 이별노래 곡 (제목/작사·작곡·노래 크레딧 + 완창 가사)

/// 노래방 한 곡. 제목과 작사/작곡/노래 크레딧, 그리고 8소절 완창 가사를 담는다.
struct KaraokeSong {
    let title: String
    let lyricist: String   // 작사
    let composer: String   // 작곡
    let singer: String     // 노래
    let lines: [String]
}

/// 세션마다 한 곡을 안정적으로 배정한다(session.id 기준). 인트로 제목·크레딧용.
func karaokeSong(for session: Session) -> KaraokeSong {
    let songs = karaokeSongs(for: session)
    return songs[abs(session.id.hashValue) % songs.count]
}

/// 잠근 시간(t)과 앱 수(n)를 발라드 클리셰에 녹인 전체 곡 목록.
/// 인트로(한 곡 배정)와 메들리(전 곡 합치기)가 함께 쓴다.
func karaokeSongs(for session: Session) -> [KaraokeSong] {
    let totalMinutes = Int((session.endsAt.timeIntervalSince(session.createdAt) / 60).rounded())
    let h = totalMinutes / 60, m = totalMinutes % 60
    let t: String = {
        if h > 0 && m > 0 { return "\(h)시간 \(m)분" }
        if h > 0 { return "\(h)시간" }
        return "\(max(1, m))분"
    }()
    let n = session.selection.applicationTokens.count

    return [
        KaraokeSong(
            title: "그대 없는 봄", lyricist: "김인내", composer: "박끈기", singer: "나",
            lines: [
                "그대 없는 \(t)", "어떻게 버텨야 하나요",
                "텅 빈 방에 홀로 앉아", "너의 이름만 불러봐",
                "자꾸만 떠오르는 너", "오늘도 꾹 눌러 담아",
                "시계만 바라보다가", "또 하루가 저물어가",
                "\(t)만 견뎌내면", "다시 너를 만날 텐데",
                "쉽지 않아 정말 쉽지 않아", "그래도 끝까지 불러볼게",
                "보고 싶어 사무쳐도", "오늘 밤은 참아낼게",
                "이 노래가 끝날 때쯤", "너에게 달려갈게"
            ]),
        KaraokeSong(
            title: "빗속의 연가", lyricist: "이빗물", composer: "정먹구름", singer: "나",
            lines: [
                "창밖엔 비가 내리고", "\(n)개의 추억이 번져",
                "우산도 없이 걷던 거리", "너의 온기가 그리워",
                "멀어지는 너의 뒷모습", "차마 잡지 못했네",
                "빗물인지 눈물인지", "자꾸만 흐려지는 밤",
                "이 밤이 지나고 나면", "다시 너를 만날 수 있을까",
                "\(t)의 긴 터널 속", "너의 불빛만 찾아",
                "어둠이 깊어질수록", "더 선명해지는 너",
                "비가 그치는 그날엔", "환하게 웃어줘"
            ]),
        KaraokeSong(
            title: "재회의 약속", lyricist: "한약속", composer: "오기다림", singer: "나",
            lines: [
                "우리 다시 만날 그날", "\(t) 뒤에 약속해",
                "손가락 걸고 맹세했던", "그 약속을 기억해",
                "흐르는 눈물 닦으며", "오늘 밤을 버텨내",
                "너의 빈자리가 너무 커", "이 \(t)이 천 년 같아",
                "한 걸음 또 한 걸음", "너에게 가는 길",
                "그래도 기다릴게", "단 \(t)만 기다려",
                "무너지지 않을게", "이 약속을 지킬게",
                "동이 트는 새벽이 오면", "너를 만나러 갈게"
            ]),
        KaraokeSong(
            title: "기다림", lyricist: "윤기다", composer: "송그리움", singer: "나",
            lines: [
                "사랑은 기다림이라고", "\(t) 동안 배워가",
                "모두가 등을 돌려도", "나만은 남을게",
                "보고 싶다는 그 말도", "가슴 깊이 묻어둘게",
                "별이 지는 새벽까지", "너를 향해 \(t)을 운다",
                "바보처럼 또 바보처럼", "\(t)을 너만 기다려",
                "미련한 줄 알면서도", "발길이 떨어지지 않아",
                "떠나간 너를 위해", "오늘도 불을 켜둬",
                "언젠가 돌아올 너를", "이 자리서 기다릴게"
            ]),
        KaraokeSong(
            title: "못다 한 말", lyricist: "최미련", composer: "강후회", singer: "나",
            lines: [
                "가지 말라고 말할걸", "\(t)이 야속하기만 해",
                "잡지 못한 그 순간이", "자꾸만 아려와",
                "차마 못다 한 그 말", "\(t)이 다 흘러가도",
                "닿을 수 없는 너에게", "\(t)의 편지를 쓴다",
                "그리움이 사무쳐도", "\(t)을 견뎌낼게",
                "한 글자 한 글자에", "내 맘을 적어 보내",
                "답장이 없어도 좋아", "너만 행복하면 돼",
                "못다 부른 이 노래를", "너에게 들려줄게"
            ]),
        KaraokeSong(
            title: "능금꽃 연가", lyricist: "길옥윤", composer: "길옥윤", singer: "나",
            lines: [
                "\(n)송이 꽃을 접으며", "너 오는 길 밝힐게",
                "추운 겨울 지나면", "따뜻한 봄이 오듯",
                "시든 줄만 알았던 맘", "\(t) 끝에 다시 피어",
                "어쩌면 우린 운명", "멀어져도 결국 만나",
                "내 청춘의 \(t)을", "너에게 바쳤었지",
                "후회는 없어 정말", "너라서 행복했어",
                "다시 봄이 찾아오면", "그때 그 자리에서",
                "활짝 핀 꽃이 되어", "너를 반겨줄게"
            ]),
        KaraokeSong(
            title: "잠시만 안녕", lyricist: "안녕", composer: "잠깐", singer: "나",
            lines: [
                "잠시만 안녕 내 사랑", "\(t)만 멀어져 있자",
                "돌아서는 발걸음이", "천근처럼 무거워",
                "미워도 다시 한번", "\(t)만 참으면 되잖아",
                "마음이 무너져도", "웃으며 보내줄게",
                "흔들리는 이 맘을", "두 손으로 붙잡아",
                "\(t)이 흘러가면", "환하게 웃어줘",
                "잠깐의 이별일 뿐", "영원한 안녕 아냐",
                "다시 만날 그날까지", "잘 지내고 있어줘"
            ]),
        KaraokeSong(
            title: "이별 노래", lyricist: "목메임", composer: "사무침", singer: "나",
            lines: [
                "멀리서 너를 그리며", "이 밤 \(t)을 노래해",
                "흥얼대던 멜로디에", "네 얼굴이 떠올라",
                "아무리 불러봐도", "\(t)은 줄지 않네",
                "추억은 방울방울", "\(n)개의 너로 남아",
                "이별 노래 부르며", "\(t)을 흘려보낸다",
                "목이 메어 와도", "끝까지 불러볼게",
                "이 노래가 닿는다면", "내 맘도 전해질까",
                "마지막 소절까지", "너를 사랑한다고"
            ])
    ]
}

// MARK: - 애창곡 메들리 (전 곡을 합쳐 랜덤으로 흐르는 가사 풀)

/// 모든 곡의 가사를 2줄(소절)씩 묶은 메들리 풀. (윗줄=현재, 아랫줄=다음)
/// 곡 경계를 넘나들며 계속 흐르도록 전 곡의 커플릿을 한데 모은다.
func karaokeMedleyCouplets(for session: Session) -> [(String, String)] {
    var couplets: [(String, String)] = []
    for song in karaokeSongs(for: session) {
        var i = 0
        while i + 1 < song.lines.count {
            couplets.append((song.lines[i], song.lines[i + 1]))
            i += 2
        }
    }
    return couplets
}

/// 모든 곡 가사를 한 줄씩 이어 붙인 평면 메들리(한 줄씩 올라오는 자막용).
func karaokeMedleyLines(for session: Session) -> [String] {
    karaokeSongs(for: session).flatMap { $0.lines }
}

/// 시드로 같은 순서를 재현하는 가벼운 난수기(xorshift). 세션마다 메들리 순서를 고정.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9e3779b97f4a7c15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - 노래방 인트로 (곡 시작 전 제목·작사·작곡이 뜨는 화면)

/// 옛날 노래방에서 곡이 시작될 때 풍경 위로 제목과 작사/작곡/노래 크레딧이
/// 떠오르던 그 화면을 재현한다. 가사처럼 3·2·1을 센 뒤 잠금 화면으로 넘어간다(탭하면 바로 건너뜀).
struct KaraokeIntroView: View {
    let song: KaraokeSong
    let number: String
    /// 화면에 크게 띄울 곡 제목. 사용자가 정한 곡 이름(세션 title)을 우선 쓰고,
    /// 비어 있으면 배정된 발라드 제목(song.title)으로 대체한다.
    var displayTitle: String? = nil
    var onFinish: () -> Void

    /// 실제로 그릴 제목 — 사용자 곡명 우선, 없으면 배정곡 제목.
    private var titleText: String {
        if let t = displayTitle?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
        return song.title
    }

    @State private var appear = false
    /// 가사처럼 떠오르는 시작 카운트(3·2·1). nil이면 아직/이미 끝.
    @State private var count: Int? = nil

    var body: some View {
        ZStack {
            KaraokeBackground()

            // 우상단: 노래방 기기 표시(키/음성) — 레퍼런스의 Ab · 여
            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    introTag("Ab", color: KColor.cyan)
                    introTag("여", color: KColor.pink)
                }
                Spacer()
            }
            .padding(20)

            // 좌측 중앙: 곡 번호 + 제목
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(KColor.cyan)
                    Text("\(number)  곡 들어갑니다")
                        .font(.led(13))
                        .foregroundStyle(KColor.cyan)
                        .shadow(color: KColor.cyan.opacity(0.7), radius: 6)
                }
                OutlinedText(text: titleText, size: 40, fill: KColor.yellow, strokeWidth: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .opacity(appear ? 1 : 0)
            .offset(x: appear ? 0 : -28)

            // 좌하단: 음표 장식
            HStack(spacing: 12) {
                noteGlyph(KColor.cyan)
                noteGlyph(KColor.pink)
                noteGlyph(KColor.yellow)
                noteGlyph(KColor.green)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 30)
            .padding(.bottom, 54)
            .opacity(appear ? 1 : 0)

            // 우하단: 작사 / 작곡 / 노래 크레딧
            VStack(alignment: .trailing, spacing: 8) {
                creditLine(song.lyricist, role: "작사")
                creditLine(song.composer, role: "작곡")
                creditLine(song.singer, role: "노래")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 28)
            .padding(.bottom, 50)
            .opacity(appear ? 1 : 0)
            .offset(x: appear ? 0 : 28)

            // 카운트다운 — 옛 노래방 인트로처럼 "3·2·1"이 가사같이 큼직하게 차례로 떠오른다.
            Group {
                if let n = count {
                    OutlinedText(text: "\(n)", size: 104, fill: KColor.yellow, strokeWidth: 7)
                        .id(n)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.7).combined(with: .opacity),
                            removal: .scale(scale: 0.6).combined(with: .opacity)
                        ))
                        .shadow(color: KColor.yellow.opacity(0.5), radius: 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 64)
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appear = true }
        }
        .task { await runCountdown() }
    }

    /// 제목·크레딧이 먼저 떠오를 틈을 준 뒤, 가사처럼 3·2·1을 세고 본 화면으로 넘어간다.
    private func runCountdown() async {
        try? await Task.sleep(nanoseconds: 900_000_000)
        for n in [3, 2, 1] {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) { count = n }
            try? await Task.sleep(nanoseconds: 820_000_000)
        }
        withAnimation(.easeOut(duration: 0.2)) { count = nil }
        onFinish()
    }

    private func introTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.led(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.7), lineWidth: 2))
    }

    private func noteGlyph(_ color: Color) -> some View {
        Image(systemName: "music.note")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.7), radius: 6)
    }

    private func creditLine(_ name: String, role: String) -> some View {
        OutlinedText(text: "\(name)  \(role)", size: 22, fill: KColor.yellow, strokeWidth: 4)
    }
}

// MARK: - 지지직 글리치 등장 프레젠테이션

extension View {
    /// 모달을 아래에서 위로 슬라이드하는 대신, 옛날 TV 채널을 맞출 때처럼
    /// "지지직" 하고 화면이 노이즈와 함께 나타났다 정착하게 띄운다.
    /// 닫기는 content 클로저로 전달되는 close 액션을 호출하면 역방향 지지직으로 사라진다.
    func glitchReveal<C: View>(
        isPresented: Binding<Bool>,
        dimmed: Bool = true,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> C
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                GlitchHost(isPresented: isPresented, dimmed: dimmed, content: content)
            }
        }
    }
}

/// 글리치로 등장/퇴장하는 풀스크린 호스트. 상태는 withAnimation 없이 프레임마다
/// 불연속으로 튀게 갱신해 "지지직"한 느낌을 낸다.
private struct GlitchHost<C: View>: View {
    @Binding var isPresented: Bool
    /// false면 뒤 배경(잠금 화면)이 비치도록 옅게만 덮는다. 카드형 표시에 사용.
    var dimmed: Bool = true
    let content: (@escaping () -> Void) -> C

    @State private var intensity: CGFloat = 1
    @State private var jx: CGFloat = 0
    @State private var jy: CGFloat = 0
    @State private var sy: CGFloat = 1
    @State private var bright: CGFloat = 0
    @State private var flash: CGFloat = 1
    @State private var seed: UInt64 = 0
    @State private var interactive = false
    @State private var closing = false

    var body: some View {
        ZStack {
            // 카드형(dimmed=false)일 땐 뒤 잠금 화면이 비치도록 옅게만 덮는다.
            Color.black.opacity(dimmed ? 1 : 0.45).ignoresSafeArea()

            content { requestClose() }
                .scaleEffect(x: 1, y: sy, anchor: .center)
                .offset(x: jx, y: jy)
                .brightness(Double(bright))
                .contrast(1 + Double(intensity) * 0.4)
                .saturation(1 + Double(intensity) * 0.7)
                .opacity(Double(flash))
                .overlay {
                    if intensity > 0.01 {
                        TVStatic(seed: seed)
                            .opacity(Double(intensity))
                            .ignoresSafeArea()
                    }
                }
                .compositingGroup()
                .allowsHitTesting(interactive)
        }
        // 배경(검정·네온·노이즈)은 각자 .ignoresSafeArea로 풀블리드를 유지하되,
        // 콘텐츠(헤더·버튼)는 세이프에어리어를 존중해 상태바/홈 인디케이터와 겹치지 않게 한다.
        .task { await runIntro() }
    }

    private func requestClose() {
        guard !closing else { return }
        closing = true
        Task { await runOutro() }
    }

    private func runIntro() async {
        interactive = false
        let frames = 16
        for f in 0..<frames {
            tick(progress: 1 - CGFloat(f) / CGFloat(frames - 1))
            try? await Task.sleep(nanoseconds: 32_000_000)
        }
        settle()
        interactive = true
    }

    private func runOutro() async {
        interactive = false
        let frames = 9
        for f in 0..<frames {
            tick(progress: CGFloat(f) / CGFloat(frames - 1))
            try? await Task.sleep(nanoseconds: 26_000_000)
        }
        isPresented = false
    }

    /// progress 1 = 완전 지지직, 0 = 정착.
    private func tick(progress p: CGFloat) {
        let i = max(0, min(1, p))
        seed = UInt64.random(in: 0...UInt64.max)
        intensity = i
        jx = CGFloat.random(in: -1...1) * 12 * i
        jy = CGFloat.random(in: -1...1) * 5 * i
        sy = 1 + CGFloat.random(in: -1...1) * 0.06 * i
        bright = CGFloat.random(in: -0.2...0.5) * i
        flash = (i > 0.4 && Bool.random()) ? CGFloat.random(in: 0.1...0.4) : 1
    }

    private func settle() {
        intensity = 0; jx = 0; jy = 0; sy = 1; bright = 0; flash = 1
    }
}

/// 한 프레임의 TV 화이트노이즈 + RGB 가로 찢김. seed가 바뀌면 다시 그려진다.
private struct TVStatic: View {
    let seed: UInt64

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix64(seed: seed)
            let rowH: CGFloat = 3

            // 화이트노이즈: 가로 줄을 따라 무작위 밝기의 작은 조각들.
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let w = CGFloat(rng.next() % 9) + 2
                    let b = Double(rng.next() % 100) / 100
                    if b > 0.55 {
                        ctx.fill(
                            Path(CGRect(x: x, y: y, width: w, height: rowH)),
                            with: .color(.white.opacity((b - 0.55) * 1.6))
                        )
                    }
                    x += w
                }
                y += rowH
            }

            // RGB 가로 찢김 바 몇 줄 — 채널 어긋남 느낌.
            let colors: [Color] = [
                Color(red: 1, green: 0.1, blue: 0.2),
                Color(red: 0.1, green: 1, blue: 0.9),
                Color(red: 0.3, green: 1, blue: 0.2)
            ]
            for c in colors {
                let by = CGFloat(rng.next() % UInt64(max(1, Int(size.height))))
                let bh = CGFloat(rng.next() % 14) + 3
                let dx = CGFloat(Int(rng.next() % 40)) - 20
                ctx.fill(
                    Path(CGRect(x: dx, y: by, width: size.width, height: bh)),
                    with: .color(c.opacity(0.35))
                )
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

/// 시드로 결정적 난수를 뽑는 가벼운 RNG (Canvas 재현용).
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 인트로는 곡(세션)당 한 번만 — 본 세션 id를 기록해 재진입 시 생략한다.
enum KaraokeIntroTracker {
    private static let key = "karaokeIntroShownSessionIDs"

    static func hasShown(_ id: UUID) -> Bool {
        let shown = UserDefaults.standard.stringArray(forKey: key) ?? []
        return shown.contains(id.uuidString)
    }

    static func markShown(_ id: UUID) {
        var shown = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !shown.contains(id.uuidString) else { return }
        shown.append(id.uuidString)
        // 최근 50개만 유지(무한 증가 방지).
        if shown.count > 50 { shown.removeFirst(shown.count - 50) }
        UserDefaults.standard.set(shown, forKey: key)
    }
}

// MARK: - 완료 축하 추적기 (잠금 완주 → 앱 진입 시 점수 축하)

/// 잠금을 끝까지 버틴 세션을 표시해 두었다가, 앱에 들어왔을 때 콘페티+100점을 한 번
/// 터뜨린다. 시작할 때 "대기"로 등록하고(=완료를 기다림), 축하를 보여주면 비운다.
/// (기능 도입 전의 옛 세션이 한꺼번에 축하되지 않도록 시작 시점에만 등록한다.)
enum KaraokeCelebrationTracker {
    private static let key = "karaokePendingCelebrationSessionIDs"

    /// 세션 시작 시 호출 — 완료되면 축하할 대상으로 등록.
    static func markStarted(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !ids.contains(id.uuidString) else { return }
        ids.append(id.uuidString)
        if ids.count > 50 { ids.removeFirst(ids.count - 50) }
        UserDefaults.standard.set(ids, forKey: key)
    }

    static func isPending(_ id: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id.uuidString)
    }

    /// 축하를 보여줬거나(또는 점수 제거로 건너뛸 때) 대상에서 제거.
    static func consume(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids.removeAll { $0 == id.uuidString }
        UserDefaults.standard.set(ids, forKey: key)
    }
}
