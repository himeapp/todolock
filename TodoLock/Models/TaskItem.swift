import Foundation
import SwiftData

/// 과업 종류 — 단일 과업은 둘 중 하나다.
/// - timer: 타이머가 끝날 때까지 버티기.
/// - photo: 사진 1장 촬영 → 온디바이스 Vision 검수로 통과.
enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case timer
    case photo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: return "타이머 버티기"
        case .photo: return "사진찍기"
        }
    }
    var symbol: String {
        switch self {
        case .timer: return "timer"
        case .photo: return "camera.fill"
        }
    }
    var badge: String {
        switch self {
        case .timer: return "타이머"
        case .photo: return "사진"
        }
    }
}

/// 사진 검수 카테고리 — 온디바이스 Vision이 "확실하게 알아보는 사물"만 딱 3종.
/// (정리·식사·반려동물처럼 판정이 모호하거나 무의미한 항목은 일부러 뺐다.)
enum VerifyCategory: String, Codable, CaseIterable, Identifiable {
    case exercise, book, outdoors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exercise: return "운동 기구"
        case .book: return "책"
        case .outdoors: return "하늘/나무"
        }
    }

    /// 무엇을 찍으면 되는지 한 줄 안내.
    var hint: String {
        switch self {
        case .exercise: return "운동 기구를 찍어요"
        case .book: return "읽은 책을 찍어요"
        case .outdoors: return "하늘이나 나무를 찍어요"
        }
    }

    /// VNClassifyImageRequest 식별자에 부분일치시킬 키워드들(소문자).
    var matchKeywords: [String] {
        switch self {
        case .exercise: return ["gym", "fitness", "dumbbell", "weight", "exercise", "sport", "yoga", "treadmill", "barbell", "athletic", "machine"]
        case .book: return ["book", "library", "paper", "magazine", "document", "text", "newspaper", "notebook"]
        case .outdoors: return ["outdoor", "sky", "cloud", "tree", "park", "mountain", "nature", "landscape", "grass", "forest", "plant", "leaf"]
        }
    }
}

/// 사용자가 등록해 두는 "자주 쓰는 과업" 한 건. 전역 풀(pool)에 저장되고,
/// 잠긴 앱을 열어 점프할 때 이 중 하나를 골라 즉시 수행한다.
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var timerSeconds: Int            // timer 전용
    var verifyCategoryRaw: String    // photo 전용
    var useCount: Int
    var createdAt: Date

    var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw) ?? .timer }
        set { kindRaw = newValue.rawValue }
    }
    var verifyCategory: VerifyCategory {
        get { VerifyCategory(rawValue: verifyCategoryRaw) ?? .exercise }
        set { verifyCategoryRaw = newValue.rawValue }
    }

    init(
        name: String,
        kind: TaskKind = .timer,
        timerSeconds: Int = 1800,
        verifyCategory: VerifyCategory = .exercise
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.timerSeconds = timerSeconds
        self.verifyCategoryRaw = verifyCategory.rawValue
        self.useCount = 0
        self.createdAt = Date()
    }

    /// 한 줄 요약 (목록 부제용).
    var subtitle: String {
        switch kind {
        case .timer:
            let m = timerSeconds / 60, s = timerSeconds % 60
            if m > 0 && s > 0 { return "타이머 \(m)분 \(s)초 버티기" }
            if m > 0 { return "타이머 \(m)분 버티기" }
            return "타이머 \(s)초 버티기"
        case .photo:
            return verifyCategory.title
        }
    }

    /// 첫 실행 시 비어 있지 않도록 기본 과업 풀.
    static func seeds() -> [TaskItem] {
        [
            TaskItem(name: "30분 독서", kind: .timer, timerSeconds: 1800),
            TaskItem(name: "바깥 산책 인증", kind: .photo, verifyCategory: .outdoors),
            TaskItem(name: "5분 스트레칭", kind: .timer, timerSeconds: 300),
            TaskItem(name: "운동 인증", kind: .photo, verifyCategory: .exercise)
        ]
    }
}
