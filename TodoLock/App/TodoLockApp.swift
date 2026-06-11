import SwiftUI
import SwiftData
import FamilyControls

@main
struct TodoLockApp: App {
    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Session.self, TempUnlock.self,
                TaskItem.self, CompletionRecord.self, SessionPreset.self
            )
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }()

    @StateObject private var authState = AuthorizationState()
    @StateObject private var subscription = SubscriptionManager()

    init() {
        NotificationDelegate.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authState)
                .environmentObject(subscription)
                .onOpenURL { url in
                    DeepLinkHandler.shared.handle(url)
                }
        }
        .modelContainer(modelContainer)
    }
}

struct RootView: View {
    @EnvironmentObject var authState: AuthorizationState
    @EnvironmentObject var subscription: SubscriptionManager

    var body: some View {
        Group {
            if subscription.isLoading {
                // 구독 상태를 확인하는 동안의 스플래시(잠깐). 깜빡임 방지.
                ZStack {
                    KaraokeBackground()
                    ProgressView().tint(KColor.cyan)
                }
            } else if !subscription.isSubscribed {
                // 구독이 없으면 앱 전체를 막는다 — 멤버십이 있어야 사용 가능.
                PaywallView()
            } else if authState.isAuthorized {
                RemoteControlView()
            } else {
                PermissionRequestView()
            }
        }
        .task { await authState.refresh() }
    }
}

@MainActor
final class AuthorizationState: ObservableObject {
    @Published var isAuthorized: Bool = false

    func refresh() async {
        #if targetEnvironment(simulator)
        // 시뮬레이터는 Family Controls 권한이 정상 동작하지 않는다(스크린타임 비번 요구·미승인).
        // 화면 UI만 확인할 수 있도록 권한 게이트를 통과시킨다. 실기기 빌드엔 포함되지 않음.
        isAuthorized = true
        #else
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        #endif
    }

    func request() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await refresh()
        } catch {
            isAuthorized = false
        }
        // 스크린타임 다이얼로그가 닫힌 직후 알림 권한도 이어서 요청 — 같은 타이밍으로 묶는다.
        // (권한 거부로 catch에 빠져도 알림은 별개라 항상 요청한다.)
        await NotificationDelegate.shared.requestAuthorization()
    }
}
