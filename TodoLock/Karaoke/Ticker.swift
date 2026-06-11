import Foundation
import Combine

/// 1초마다 `now`를 갱신하는 전역 틱. 잠금 TV의 남은시간/게이지 갱신용.
final class Ticker: ObservableObject {
    static let shared = Ticker()

    @Published var now: Date = Date()
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
    }
}
