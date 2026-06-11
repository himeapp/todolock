import Foundation
import SwiftData

/// 과업 1회 통과 시 기록되는 가벼운 로그. 투두 탭의 "최근 완료" 리스트 소스.
@Model
final class CompletionRecord {
    @Attribute(.unique) var id: UUID
    var completedAt: Date
    var summary: String
    var sessionId: UUID

    init(sessionId: UUID, summary: String) {
        self.id = UUID()
        self.completedAt = Date()
        self.summary = summary
        self.sessionId = sessionId
    }
}
