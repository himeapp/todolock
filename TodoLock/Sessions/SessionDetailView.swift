import SwiftUI
import SwiftData

/// 잠금 진행 중인 세션을 탭하면 보이는 노래방 TV 화면.
struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let sessionId: UUID

    private var session: Session? {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
        return try? modelContext.fetch(descriptor).first
    }

    var body: some View {
        ZStack {
            if let session {
                ActiveLockView(session: session)
            } else {
                KaraokeBackground()
                OutlinedText(text: "세션을 찾을 수 없어요", size: 26, alignment: .center)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
