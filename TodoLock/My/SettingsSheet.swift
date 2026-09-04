import SwiftUI
import SwiftData
import FamilyControls
import StoreKit

/// 리모컨 우상단 ⚙︎ 가 여는 미니 설정 시트. (기존 "마이 탭" 흡수)
/// 꼭 필요한 것만: 이번 주 통계 1줄 + 권한 상태 + 삭제보호 가이드 + 버전/문의.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authState: AuthorizationState
    @EnvironmentObject var subscription: SubscriptionManager
    @Query private var allSessions: [Session]
    @AppStorage("hideKaraokeScore") private var hideKaraokeScore = false
    @State private var showingManageSubscriptions = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PatienceTimeCard(sessions: allSessions)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    Toggle("점수 제거", isOn: $hideKaraokeScore)
                } footer: {
                    Text(hideKaraokeScore
                         ? "점수 제거 됐어요. 점프 과제을 성공하거나 잠금을 완주해도 점수·축하가 안나와요."
                         : "잠금을 완주하거나 점프 과제을 마치면 100점과 축하 화면이 표시돼요.")
                }

                Section("도움말") {
                    statusRow("스크린타임 권한",
                              ok: authState.isAuthorized,
                              okText: "허용됨", noText: "필요")
                    NavigationLink {
                        DeleteProtectionGuide()
                    } label: {
                        Text("앱 삭제 보호 가이드")
                    }
                }

                Section("정보") {
                    LabeledContent("버전", value: "1.0.0")
                    NavigationLink("이용약관") { TermsView() }
                    NavigationLink("개인정보 처리방침") { PrivacyView() }
                    Link(destination: URL(string: "mailto:dontseewhatever@gmail.com")!) {
                        HStack {
                            Text("문의하기").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // 구독 관리(해지) 진입구. 굳이 강조하지 않고 맨 아래 작게.
                    Button("구독 관리") { showingManageSubscriptions = true }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("구매 복원") { Task { await subscription.restore() } }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .disabled(subscription.purchaseInProgress)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func statusRow(_ title: String, ok: Bool, okText: String, noText: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(ok ? okText : noText)
                .foregroundStyle(ok ? .green : .red)
                .font(.subheadline.weight(.semibold))
        }
    }
}

/// 앱 삭제 보호 안내. (스크린타임으로 본 앱 삭제를 막는 방법)
private struct DeleteProtectionGuide: View {
    var body: some View {
        List {
            Section {
                Text("스크린타임 → 콘텐츠 및 개인정보 보호 제한 → '앱 삭제 허용 안 함'을 켜두면, 잠금 중에 투두락을 지워서 빠져나가는 걸 막을 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("단계") {
                Label("설정 앱 → 스크린타임", systemImage: "1.circle")
                Label("콘텐츠 및 개인정보 보호 제한 켜기", systemImage: "2.circle")
                Label("iTunes 및 App Store 구입 → 앱 삭제 → '허용 안 함'", systemImage: "3.circle")
            }
        }
        .navigationTitle("앱 삭제 보호")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 설정 화면 맨 위 카드. 옛날 노래방 CRT 화면처럼 남색 네온 배경 + 스캔라인 위에
/// DSEG7 LED 숫자로 두 기록을 나눠 보여준다.
///  ① 잠금으로 참고 견딘 누적 "시간"  ② 감시를 켜둔 누적 "날 수"
struct PatienceTimeCard: View {
    let sessions: [Session]

    // ① 모든 잠금 세션에서 실제로 잠겨 있던 시간을 누적. (진행 중 세션은 지금까지의 경과분만)
    private var totalSeconds: TimeInterval {
        sessions.reduce(0) { acc, s in
            acc + max(0, min(s.endsAt, Date()).timeIntervalSince(s.createdAt))
        }
    }
    private var hours: Int { Int(totalSeconds / 3600) }
    private var minutes: Int { Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60) }

    // ② 감시를 켜둔 누적 날 수. (시간 합산엔 넣지 않고 따로 '며칠'로 표시)
    private var watchdogDays: Int { LockWidgetBridge.watchdogTotalDays() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("지금까지 쌓은 기록")
                .font(.myungjoLight(12))
                .foregroundStyle(KColor.cyan.opacity(0.85))

            // ① 잠금 인내 시간
            metricRow(label: "참은 시간") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ledNumber("\(hours)", unit: "시간")
                    ledNumber(String(format: "%02d", minutes), unit: "분")
                }
            }

            neonDivider

            // ② 감시 누적 일수 (시간엔 안 넣고 따로 '며칠')
            metricRow(label: "감시한 날") {
                ledNumber("\(watchdogDays)", unit: "일")
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(KColor.cyan.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // 왼쪽 라벨 + 오른쪽 LED 값 한 줄
    private func metricRow<Content: View>(label: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.myungjoLight(14))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 8)
            content()
        }
    }

    // LED 숫자 1칸: 꺼진 세그먼트가 비치는 룩(뒤에 흐린 "8" 고스트) + 단위
    private func ledNumber(_ shown: String, unit: String) -> some View {
        let ghost = String(repeating: "8", count: shown.count)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            ZStack {
                Text(ghost)
                    .font(.seg7(26))
                    .foregroundStyle(KColor.cyan.opacity(0.12))
                Text(shown)
                    .font(.seg7(26))
                    .foregroundStyle(KColor.cyan)
            }
            Text(unit)
                .font(.myungjo(13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var neonDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(colors: [.clear, KColor.cyan.opacity(0.30), .clear],
                               startPoint: .leading, endPoint: .trailing)
            )
            .frame(height: 1)
    }

    // 남색 네온 + 은은한 글로우 + 스캔라인 (노래방 CRT 화면). 정적으로 가볍게.
    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.06, blue: 0.24),
                    Color(red: 0.14, green: 0.09, blue: 0.34),
                    Color(red: 0.11, green: 0.07, blue: 0.28)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            GeometryReader { geo in
                ZStack {
                    RadialGradient(colors: [KColor.cyan.opacity(0.30), .clear],
                                   center: .center, startRadius: 0, endRadius: 90)
                        .frame(width: 180, height: 180)
                        .position(x: geo.size.width * 0.15, y: geo.size.height * 0.2)
                    RadialGradient(colors: [KColor.pink.opacity(0.25), .clear],
                                   center: .center, startRadius: 0, endRadius: 90)
                        .frame(width: 180, height: 180)
                        .position(x: geo.size.width * 0.9, y: geo.size.height * 0.85)
                }
                .blur(radius: 28)
            }

            Canvas { c, size in
                let spacing: CGFloat = 3
                var y: CGFloat = 0
                while y < size.height {
                    c.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1.1)),
                        with: .color(.black.opacity(0.16))
                    )
                    y += spacing
                }
            }
            .allowsHitTesting(false)
        }
    }
}
