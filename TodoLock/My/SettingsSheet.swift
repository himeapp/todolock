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
                    WeeklyStatsCard(sessions: allSessions)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    Toggle("점수 제거", isOn: $hideKaraokeScore)
                } footer: {
                    Text(hideKaraokeScore
                         ? "점수 제거 됐어요. 점프 과업을 성공해도 점수가 안나와요."
                         : "잠금 상태를 점프할 때, 과업을 마치고 나면 100점이 표시돼요.")
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

/// 이번 주 통계 1줄 카드. (기존 MyView의 WeeklyStatsCard 이전)
struct WeeklyStatsCard: View {
    let sessions: [Session]

    private var weekStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    private var weekSessions: [Session] {
        sessions.filter { $0.createdAt >= weekStart }
    }

    private var totalLockedSeconds: TimeInterval {
        weekSessions.reduce(0) { $0 + min($1.endsAt, Date()).timeIntervalSince($1.createdAt) }
    }

    private var totalLockedString: String {
        let hours = Int(totalLockedSeconds / 3600)
        let minutes = Int((totalLockedSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "\(hours)시간" }
        return "\(minutes)분"
    }

    private var passRate: Int {
        let attempts = weekSessions.reduce(0) { $0 + $1.attemptCount }
        let passes = weekSessions.reduce(0) { $0 + $1.passCount }
        guard attempts > 0 else { return 0 }
        return Int(Double(passes) / Double(attempts) * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이번 주")
                .font(.caption.bold())
                .opacity(0.85)
                .textCase(.uppercase)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text(totalLockedString)
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                    Text("총 잠금 시간")
                        .font(.footnote)
                        .opacity(0.85)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(passRate)%")
                        .font(.title3.bold().monospacedDigit())
                    Text("통과율")
                        .font(.caption)
                        .opacity(0.85)
                }
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
