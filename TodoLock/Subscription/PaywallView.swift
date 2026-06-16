import SwiftUI
import StoreKit

/// 구독이 없을 때 보이는 시작 화면.
/// 막아서는 느낌 대신 "일주일 무료로 시작" 톤으로 부드럽게 안내한다.
struct PaywallView: View {
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var legal: LegalKind?
    /// X 버튼을 누르면 뜨는 "부담 갖지 마세요" 안심 팝업 표시 여부.
    @State private var showReassure = false
    /// 안심 팝업을 닫을 때마다 띄우는 앱 소개 투어 표시 여부.
    @State private var showTour = false
    /// 최초 실행 시 투어를 자동으로 딱 한 번 띄웠는지. (X→닫기 수동 경로는 이 값과 무관하게 매번 동작)
    @AppStorage("hasSeenTour") private var hasSeenTour = false

    /// 수록곡 목록에서 노래방 커서처럼 강조되는 행 인덱스. 일정 간격으로 번갈아 움직인다.
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

            // 우상단 X — 막아서는 느낌을 덜기 위해, 닫는 대신 "부담 갖지 마세요" 안내를 띄운다.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showReassure = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.black.opacity(0.35)))
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if showReassure {
                ReassurePopup(
                    ctaTitle: ctaTitle,
                    onStartTrial: {
                        withAnimation(.easeOut(duration: 0.2)) { showReassure = false }
                        Task { await subscription.purchase() }
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.25)) { showReassure = false }
                        // 팝업을 닫을 때마다 앱 소개 투어를 띄운다.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            showTour = true
                        }
                    }
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(2)
            }
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
        // 안심 팝업을 닫은 직후, 그리고 최초 실행 시 자동으로 뜨는 앱 소개 투어.
        .fullScreenCover(isPresented: $showTour) {
            ScreenTourView {
                showTour = false
                hasSeenTour = true   // 어떤 경로로 봤든 본 뒤엔 자동 노출을 끈다.
            }
        }
        // 최초 실행 1회 자동 노출. (이후엔 X→닫기 수동 경로로만 다시 뜬다.)
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
            // 헤더 — "🔍 수록곡"
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KColor.cyan)
                Text("수록곡")
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

// MARK: - 부담 갖지 마세요 팝업 (노래방 리모컨 룩)

/// X를 누르면 뜨는 안심 팝업. 막아서는 대신 "부담 없이 체험해보세요"라고 토닥인다.
/// 시작 확인/모드 이름 변경 팝업과 같은 노래방 디자인 — 파란 타이틀바·CRT 다크 본문·하단 액션바.
private struct ReassurePopup: View {
    let ctaTitle: String
    let onStartTrial: () -> Void
    let onClose: () -> Void

    /// 안심 메시지 세 줄 — 아이콘과 함께 곡목록처럼 보여준다.
    private let lines: [(icon: String, text: String)] = [
        ("music.note", "부담없이 체험해보세요!"),
        ("hand.tap.fill", "바로 취소 눌러두어도 돼요."),
        ("checkmark.shield.fill", "억지로 결제되지 않아요.")
    ]

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
    }

    // MARK: 파란 타이틀바

    private var titleBar: some View {
        HStack(spacing: 10) {
            waveCircle
            OutlinedText(text: "잠깐, 가기 전에", size: 19,
                         fill: Color(hex: 0xeaff6a), stroke: KColor.outline, strokeWidth: 3.5)
            Spacer(minLength: 6)
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.black.opacity(0.25)))
            }
            .buttonStyle(.plain)
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

    // MARK: 본문 (안심 메시지 목록)

    private var bodyArea: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(spacing: 12) {
                    Image(systemName: line.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(KColor.cyan)
                        .frame(width: 24)
                    Text(line.text)
                        .font(.myungjo(17))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    if idx < lines.count - 1 {
                        Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                    }
                }
            }
        }
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: 하단 액션바

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Spacer()
            actionButton("닫기", color: Color(hex: 0x4a5568)) { onClose() }
            actionButton(ctaTitle, color: KColor.green) { onStartTrial() }
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
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(color))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
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
