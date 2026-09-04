import SwiftUI

struct TimerTaskView: View {
    let seconds: Int
    let rewardMinutes: Int
    let onComplete: () -> Void

    @State private var remaining: Int
    @State private var running = false
    @State private var done = false

    init(seconds: Int, rewardMinutes: Int, onComplete: @escaping () -> Void) {
        self.seconds = seconds
        self.rewardMinutes = rewardMinutes
        self.onComplete = onComplete
        _remaining = State(initialValue: seconds)
    }

    private var progress: Double {
        guard seconds > 0 else { return 1 }
        return 1 - Double(remaining) / Double(seconds)
    }

    /// 남은 시간을 통일된 분:초 형식으로 표시 (예: 1800 → "30:00").
    private var clock: String {
        String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [KColor.cyan, KColor.green],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
                Text(clock)
                    .font(.led(44))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
            }
            .frame(width: 160, height: 160)

            if done {
                OutlinedText(text: "완료! ✓", size: 22, fill: KColor.cyan)
            } else if !running {
                Button("과제 도전 ▶") { start() }
                    .buttonStyle(KaraokeButtonStyle(color: KColor.yellow))
                    .fixedSize()
            } else {
                Text("타이머가 끝나면 간주 \(rewardMinutes)분을 획득해요…")
                    .font(.myungjoLight(16))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
        )
    }

    private func start() {
        running = true
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if remaining > 0 {
                remaining -= 1
            } else {
                timer.invalidate()
                done = true
                onComplete()
            }
        }
    }
}
