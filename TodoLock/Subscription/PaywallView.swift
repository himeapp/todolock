import SwiftUI
import StoreKit

/// 구독이 없을 때 보이는 시작 화면.
/// 막아서는 느낌 대신 "일주일 무료로 시작" 톤으로 부드럽게 안내한다.
struct PaywallView: View {
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var legal: LegalKind?
    /// 최초 실행 시 딱 한 번 자동으로 띄우는 앱 소개 투어 표시 여부.
    @State private var showTour = false
    /// 최초 실행 시 투어를 자동으로 딱 한 번 띄웠는지.
    @AppStorage("hasSeenTour") private var hasSeenTour = false

    /// 수록 기능 목록에서 노래방 커서처럼 강조되는 행 인덱스. 일정 간격으로 번갈아 움직인다.
    @State private var selectedSong = 0
    /// 강조 행을 번갈아 옮기는 타이머.
    private let songTimer = Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()

    /// 상품에서 받은 표시 가격(예: "₩3,000"). 로드 전이면 기본 문구.
    private var priceText: String {
        subscription.monthlyProduct?.displayPrice ?? "₩3,000"
    }

    /// 무료 체험 기간(예: "7일"). 자격이 없으면 nil.
    private var trialText: String? {
        subscription.showsTrial ? (subscription.trialPeriodText ?? "7일") : nil
    }

    /// 페이월 강조색(네온 청록). 어두운 스크림 위에서 밝게 떠 보이도록 다시 올림.
    private let accent = Color(red: 0.32, green: 0.93, blue: 0.97)

    var body: some View {
        ZStack {
            KaraokeBackground()
            // 균일한 어둠 대신 '무대 조명' 느낌의 방사형 스크림.
            // 가운데(타이틀 근처)는 연하게 둬서 배경의 동그란 조명이 비치고,
            // 가장자리로 갈수록 어두워져 글씨 대비(비네트)를 만든다.
            RadialGradient(
                colors: [.black.opacity(0.06), .black.opacity(0.30), .black.opacity(0.62)],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 60,
                endRadius: 560
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 36)

                Image(systemName: "music.mic")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(accent)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .shadow(color: accent.opacity(0.7), radius: 16)

                Text(trialText != nil ? "♪  무료 체험  ♪" : "♪  멤버십  ♪")
                    .font(.led(15).weight(.heavy))
                    .foregroundStyle(accent)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .shadow(color: accent.opacity(0.6), radius: 8)

                // 제목 '노래방 가사 채움' — 청록(빈색)에서 노랑(채움)이 왼→오로 차오르고
                // 다 채우면 3초 유지 후 다음 소절처럼 리셋. 남색 외곽선은 그대로 유지.
                KaraokeFillTitle(text: "투두락 멤버십",
                                 size: 32, strokeWidth: 4,
                                 base: accent, fill: KColor.yellow)
                    .padding(.horizontal, 20)

                benefitSongList
                    .padding(.top, 8)

                // 가운데 여백은 상한을 둬서, 남는 공간이 위쪽으로 가도록(=콘텐츠가 더 내려오도록) 한다.
                Spacer(minLength: 8)
                    .frame(maxHeight: 44)

                priceBadge

                Button {
                    Task { await subscription.purchase() }
                } label: {
                    if subscription.purchaseInProgress {
                        ProgressView().tint(KColor.outline)
                    } else {
                        Text(ctaTitle)
                    }
                }
                .buttonStyle(TrialCTAButtonStyle())
                .disabled(subscription.purchaseInProgress)
                .padding(.horizontal, 18)

                legalText
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
            }

            // 구독이 없으면 앱을 쓸 수 없는 하드 페이월이라 닫기(X) 버튼을 두지 않는다.
            // (거절 직후 재유도하는 패턴은 App Store 가이드라인 5.6 위반이므로 제거함.)
        }
        .sheet(item: $legal) { kind in
            NavigationStack {
                Group {
                    switch kind {
                    case .terms:   TermsView()
                    case .privacy: PrivacyView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { legal = nil }
                    }
                }
            }
        }
        .alert("알림", isPresented: Binding(
            get: { subscription.errorMessage != nil },
            set: { if !$0 { subscription.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { subscription.errorMessage = nil }
        } message: {
            Text(subscription.errorMessage ?? "")
        }
        // 최초 실행 시 딱 한 번 자동으로 뜨는 앱 소개 투어(정보성 안내).
        .fullScreenCover(isPresented: $showTour) {
            ScreenTourView {
                showTour = false
                hasSeenTour = true   // 한 번 본 뒤엔 자동 노출을 끈다.
            }
        }
        // 최초 실행 1회만 자동 노출.
        .onAppear {
            if !hasSeenTour {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !hasSeenTour { showTour = true }
                }
            }
        }
    }

    /// 메인 CTA 문구. 체험 자격이 있으면 "7일 무료로 시작하기"(기간은 동적).
    private var ctaTitle: String {
        if let trial = trialText { return "\(trial) 무료로 시작하기" }
        return "멤버십 시작하기"
    }

    /// 멤버십 혜택을 '노래방 선곡 화면'처럼 보여준다.
    /// 컬러·룩은 앱의 KaraokeSongList(검정 반투명 · 청록 LED 코드 · 흰 곡명 · 노랑 태그)에 맞췄고,
    /// 강조 행은 앱의 노래방 파랑(KColor.highlight)으로. 강조는 두 행을 번갈아 옮겨 다닌다.
    private var benefitSongList: some View {
        VStack(spacing: 0) {
            // 헤더 — "🔍 수록 기능"
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KColor.cyan)
                Text("수록 기능")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.28))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            }

            songRow(code: KaraokeSongList.songCode(0),
                    title: "참아야 할 앱 잠금 · 감시", tag: "무제한", selected: selectedSong == 0)
            songRow(code: KaraokeSongList.songCode(1),
                    title: "급할 땐 간주 점프", tag: "15분", selected: selectedSong == 1)
        }
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
        .padding(.horizontal, 24)
        .environment(\.colorScheme, .dark)
        .onReceive(songTimer) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                selectedSong = (selectedSong + 1) % 2
            }
        }
    }

    /// 선곡 화면의 한 곡 행 — [코드번호] [곡명] ……… [태그].
    /// 강조 행은 노래방처럼 파란 막대가 깔린다(크로스페이드로 부드럽게 옮겨 다님).
    private func songRow(code: String, title: String, tag: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Text(code)
                .font(.led(13))
                .foregroundStyle(KColor.cyan)
                .frame(width: 54, alignment: .leading)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(tag)
                .font(.myungjoLight(13))
                .foregroundStyle(KColor.yellow.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [KColor.highlight, Color(red: 0.10, green: 0.34, blue: 0.72)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(selected ? 1 : 0)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var priceBadge: some View {
        ZStack {
            // 가격 주변을 살랑살랑 떠다니는 음표들 (가격 텍스트 뒤).
            FloatingNotes(accent: accent)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .allowsHitTesting(false)

            VStack(spacing: 2) {
                if let trial = trialText {
                    Text("\(trial) 무료 · 이후 월 \(priceText)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(KColor.yellow)
                        .shadow(color: KColor.yellow.opacity(0.6), radius: 10)
                } else {
                    Text("월 \(priceText)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(KColor.yellow)
                        .shadow(color: KColor.yellow.opacity(0.6), radius: 10)
                }
                Text("자동 갱신 · 언제든 해지 가능")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var legalText: some View {
        VStack(spacing: 6) {
            Text("결제는 App Store 계정에 청구되며, 무료 체험 종료(또는 현재 기간 종료) 24시간 전까지 해지하지 않으면 자동 갱신됩니다. 구독은 설정 앱 > Apple 계정에서 관리·해지할 수 있어요.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)


            HStack(spacing: 10) {
                Button("이용약관") { legal = .terms }
                Text("·").foregroundStyle(.white.opacity(0.4))
                Button("개인정보 처리방침") { legal = .privacy }
                Text("·").foregroundStyle(.white.opacity(0.4))
                Button("구매 복원") { Task { await subscription.restore() } }
                    .disabled(subscription.purchaseInProgress)
            }
            .font(.system(size: 12))
            .tint(accent)
        }
    }
}

// MARK: - 제목 노래방 가사 채움

/// 제목을 노래방 가사처럼 왼쪽부터 채운다.
/// `base`(빈 색)로 깔린 글자 위에 `fill`(채움 색) 글자를 얹고, 왼쪽에서부터 마스크 폭을
/// 0→1로 키워 색이 차오르게 한다. 다 채우면 `holdDuration`만큼 유지 후 다음 소절처럼 리셋.
/// 외곽선(stroke)은 두 레이어 모두 동일해 항상 또렷하게 유지된다.
private struct KaraokeFillTitle: View {
    let text: String
    var size: CGFloat = 32
    var strokeWidth: CGFloat = 4
    var base: Color          // 빈 색 (예: 청록)
    var fill: Color          // 채움 색 (예: 노랑)

    /// 왼→오로 차오르는 데 걸리는 시간(초).
    private let fillDuration: Double = 1.8
    /// 다 채운 뒤 머무는 시간(초).
    private let holdDuration: Double = 3.0

    var body: some View {
        let cycle = fillDuration + holdDuration
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let local = t.truncatingRemainder(dividingBy: cycle)
            let raw = local < fillDuration ? local / fillDuration : 1.0
            let progress = easeInOut(raw)

            OutlinedText(text: text, size: size, fill: base,
                         strokeWidth: strokeWidth, alignment: .center)
                .overlay(alignment: .leading) {
                    OutlinedText(text: text, size: size, fill: fill,
                                 strokeWidth: strokeWidth, alignment: .center)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                }
        }
    }

    private func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}

// MARK: - 가격 주변에 떠다니는 음표

/// '월 ₩3,000' 주위를 살랑살랑 떠다니는 음표들.
/// 가격 폭보다 넓게 좌우로 흩뿌려 두고, 각자 다른 속도·위상으로 위아래로 까딱이며 살짝 회전한다.
private struct FloatingNotes: View {
    /// 청록 포인트색(페이월 강조색)을 받아 음표 색에 섞어 쓴다.
    let accent: Color

    /// 까딱임 한 주기(초).
    private let period: Double = 3.4

    private struct Note {
        let symbol: String
        let x: CGFloat        // 가로 위치(0~1)
        let y: CGFloat        // 세로 위치(0~1)
        let size: CGFloat
        let color: Color
        let baseRotation: Double
        let delay: Double     // 위상 차
        let opacity: Double
    }

    private var notes: [Note] {
        [
            Note(symbol: "♪", x: 0.05, y: 0.62, size: 18, color: accent,       baseRotation: -14, delay: 0.0, opacity: 1.0),
            Note(symbol: "♫", x: 0.20, y: 0.18, size: 13, color: KColor.yellow, baseRotation:   9, delay: 1.0, opacity: 0.8),
            Note(symbol: "♩", x: 0.33, y: 0.85, size: 12, color: accent,       baseRotation:  -7, delay: 2.0, opacity: 0.7),
            Note(symbol: "♪", x: 0.69, y: 0.12, size: 13, color: KColor.pink,   baseRotation:  12, delay: 0.5, opacity: 0.8),
            Note(symbol: "♬", x: 0.82, y: 0.80, size: 14, color: accent,       baseRotation: -11, delay: 1.6, opacity: 0.85),
            Note(symbol: "♪", x: 0.96, y: 0.55, size: 19, color: KColor.yellow, baseRotation:  15, delay: 0.3, opacity: 1.0),
            Note(symbol: "♫", x: 0.48, y: 0.04, size: 12, color: KColor.pink,   baseRotation:   0, delay: 2.4, opacity: 0.65),
        ]
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ForEach(notes.indices, id: \.self) { i in
                    let note = notes[i]
                    // 0~1 사이를 오가는 사인 위상 (까딱임).
                    let u = (sin(2 * .pi * (t + note.delay) / period) + 1) / 2
                    Text(note.symbol)
                        .font(.system(size: note.size, weight: .bold))
                        .foregroundStyle(note.color)
                        .opacity(note.opacity)
                        .shadow(color: note.color.opacity(0.75), radius: 6)
                        .rotationEffect(.degrees(note.baseRotation + 7 * u))
                        .position(
                            x: note.x * geo.size.width,
                            y: note.y * geo.size.height - 9 * u
                        )
                }
            }
        }
    }
}

/// 페이월에서 띄울 법무 문서 종류.
enum LegalKind: Identifiable {
    case terms, privacy
    var id: Self { self }
}

/// 무료 체험 시작 CTA — 더 크고, 빛나고, 은은하게 맥동해서 눈에 띈다.
struct TrialCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CTALabel(configuration: configuration)
    }

    private struct CTALabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var pulse = false

        var body: some View {
            configuration.label
                .font(.myungjo(22))
                .foregroundStyle(KColor.outline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 19)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.78, blue: 0.38), KColor.green],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: KColor.green.opacity(0.9), radius: pulse ? 28 : 12)
                .scaleEffect(configuration.isPressed ? 0.97 : (pulse ? 1.025 : 1.0))
                .opacity(configuration.isPressed ? 0.9 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
    }
}
