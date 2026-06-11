import Foundation
import Combine

/// Shield의 "허용" 버튼이 누르면 우리 앱으로 들어오는 URL을 파싱.
/// URL 형식: todolock://task?sessionId=<UUID>
final class DeepLinkHandler: ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var pendingSessionId: UUID?

    func handle(_ url: URL) {
        guard url.scheme == "todolock" else { return }
        guard url.host == "task" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        guard let idString = components.queryItems?.first(where: { $0.name == "sessionId" })?.value else { return }
        guard let id = UUID(uuidString: idString) else { return }
        pendingSessionId = id
    }

    func clear() {
        pendingSessionId = nil
    }
}
