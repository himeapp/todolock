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

            VStack(spacing: 18) {
                Spacer(minLength: 12)

                Image(systemName: "music.mic")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(accent)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .shadow(color: accent.opacity(0.7), radius: 16)

                if let trial = trialText {
                    Text("♪  \(trial) 무료 체험  ♪")
                        .font(.led(15).weight(.heavy))
                        .foregroundStyle(accent)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .shadow(color: accent.opacity(0.6), radius: 8)
                } else {
                    Text("♪  멤버십  ♪")
                        .font(.led(15).weight(.heavy))
                        .foregroundStyle(accent)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .shadow(color: accent.opacity(0.6), radius: 8)
                }

                OutlinedText(text: "투두락 멤버십",
                             size: 32, fill: KColor.yellow, strokeWidth: 4, alignment: .center)
                    .padding(.horizontal, 20)

                Text(headline)
                    .font(.myungjoLight(16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .shadow(color: .black.opacity(0.4), radius: 5)
                    .padding(.horizontal, 28)

                featureList
                    .padding(.horizontal, 32)
                    .padding(.top, 2)

                Spacer(minLength: 8)

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
        // 안심 팝업을 닫은 직후 딱 한 번 뜨는 앱 소개 투어.
        .fullScreenCover(isPresented: $showTour) {
            ScreenTourView { showTour = false }
        }
    }

    /// 메인 CTA 문구. 체험 자격이 있으면 "일주일 무료체험 시작".
    private var ctaTitle: String {
        if trialText != nil { return "일주일 무료체험 시작" }
        return "멤버십 시작하기"
    }

    private var headline: String {
        if let trial = trialText {
            return "\(trial) 동안 모든 기능을 무료로 써보세요.\n체험 중 취소하면 요금이 청구되지 않아요."
        }
        return "월 \(priceText)으로 앱 잠금·과업 기능을\n제한 없이 사용할 수 있어요."
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow("원하는 앱·카테고리 잠금")
            featureRow("과업(타이머·사진 인증)으로 15분만 잠금 해제")
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(accent)
                .shadow(color: .black.opacity(0.4), radius: 1.5)
            Text(text)
                .font(.myungjoLight(15))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.65), radius: 1.5)
            Spacer(minLength: 0)
        }
    }

    private var priceBadge: some View {
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
