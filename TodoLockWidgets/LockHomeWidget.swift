import WidgetKit
import SwiftUI

// 홈 화면 위젯 — 세 가지 상태.
//  1) 노래 중      : 잠금 세션 진행 — 가사가 한 줄씩 흘러감(미리 구운 타임라인)
//  2) 감시 중      : 감시 모드가 걸려 있음 — 하루 한도 표시
//  3) 노래 안하는중 : 아무것도 안 걸림 — 대기 화면
//
// 가사 "흐름" 트릭: WidgetKit 타임라인에 미래 시점 엔트리를 줄당 cadence초로 미리 구워 넣으면,
// 시스템이 앱을 깨우지 않고도 그 시각마다 다음 가사 엔트리를 렌더한다.

struct HomeEntry: TimelineEntry {
    let date: Date
    let lock: LockWidgetState?         // 노래 중이면 채워짐
    let lineIndex: Int
    let watchdog: WatchdogWidgetState? // 감시 중이면 채워짐
}

struct LockHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: Date(), lock: nil, lineIndex: 0, watchdog: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(resolve(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let now = Date()
        let lock = LockWidgetBridge.read()

        // 1) 노래 중 — 가사 타임라인을 굽는다(최우선).
        if let s = lock, s.endsAt > now, !s.lyrics.isEmpty {
            var entries: [HomeEntry] = []
            let cadence = LockWidgetBridge.lineCadence
            let maxEntries = 200            // 약 47분치 가사를 미리 굽는다.
            var t = now
            while t < s.endsAt && entries.count < maxEntries {
                let idx = LockWidgetBridge.lineIndex(at: t, startedAt: s.startedAt, lineCount: s.lyrics.count)
                entries.append(HomeEntry(date: t, lock: s, lineIndex: idx, watchdog: nil))
                t = t.addingTimeInterval(cadence)
            }
            completion(Timeline(entries: entries, policy: .after(t)))
            return
        }

        // 2) 감시 중
        if let w = LockWidgetBridge.readWatchdog() {
            let entry = HomeEntry(date: now, lock: nil, lineIndex: 0, watchdog: w)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(1800))))
            return
        }

        // 3) 노래 안하는중
        completion(Timeline(entries: [HomeEntry(date: now, lock: nil, lineIndex: 0, watchdog: nil)],
                            policy: .after(now.addingTimeInterval(600))))
    }

    private func resolve(at now: Date) -> HomeEntry {
        if let s = LockWidgetBridge.read(), s.endsAt > now, !s.lyrics.isEmpty {
            let idx = LockWidgetBridge.lineIndex(at: now, startedAt: s.startedAt, lineCount: s.lyrics.count)
            return HomeEntry(date: now, lock: s, lineIndex: idx, watchdog: nil)
        }
        if let w = LockWidgetBridge.readWatchdog() {
            return HomeEntry(date: now, lock: nil, lineIndex: 0, watchdog: w)
        }
        return HomeEntry(date: now, lock: nil, lineIndex: 0, watchdog: nil)
    }
}

struct LockHomeWidget: Widget {
    let kind = "LockHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockHomeProvider()) { entry in
            LockHomeView(entry: entry)
                .containerBackground(for: .widget) { WKKaraokeScreen() }
        }
        .configurationDisplayName("노래방 가사")
        .description("노래 부르는 동안 이별노래 가사가 흘러갑니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct LockHomeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeEntry

    var body: some View {
        Group {
            if let s = entry.lock, s.isActive {
                singing(s)
            } else if let w = entry.watchdog {
                watching(w)
            } else {
                idle
            }
        }
        // 시스템 기본 콘텐츠 마진(~16pt)을 끄고(.contentMarginsDisabled) 더 작은 자체 여백으로 공간 확보.
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: 1) 노래 중

    private func singing(_ s: LockWidgetState) -> some View {
        let line = s.lyrics[safe: entry.lineIndex] ?? ""
        let next = s.lyrics[safe: entry.lineIndex + 1] ?? s.lyrics.first ?? ""
        return VStack(alignment: .leading, spacing: family == .systemMedium ? 8 : 4) {
            HStack(spacing: 4) {
                Text(s.isPaused ? "⏸" : "🎤").font(.system(size: 11))
                Text(s.songTitle)
                    .font(.wkMyungjoLight(family == .systemMedium ? 12 : 10))
                    .foregroundStyle(s.isPaused ? WKColor.pink : WKColor.cyan)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if s.isPaused {
                    Text("간주 중")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WKColor.pink)
                } else {
                    Text("🎵\(s.appCount)곡")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WKColor.fill.opacity(0.9))
                }
            }
            .wkPanel(8)

            Spacer(minLength: 0)

            if s.isPaused {
                WKInterludeLine(size: family == .systemMedium ? 18 : 13)
            } else {
                WKLyricLine(text: line, size: family == .systemMedium ? 20 : 15)
                if family == .systemMedium {
                    Text(next)
                        .font(.wkMyungjo(15))
                        .foregroundStyle(WKColor.fill.opacity(0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text(s.isPaused ? "멈춤" : "남은 시간")
                    .font(.system(size: 9))
                    .foregroundStyle(WKColor.fill.opacity(0.7))
                Spacer()
                Text(timerInterval: entry.date...s.endsAt, countsDown: true)
                    .font(.wkSeg(family == .systemMedium ? 18 : 14))
                    .foregroundStyle(s.isPaused ? WKColor.pink : WKColor.amber)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: family == .systemMedium ? 120 : 90, alignment: .trailing)
            }
            .wkPanel(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: 2) 감시 중

    private func watching(_ w: WatchdogWidgetState) -> some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 8 : 4) {
            HStack(spacing: 4) {
                Text("👀").font(.system(size: 11))
                Text("감시 중")
                    .font(.wkMyungjoLight(family == .systemMedium ? 12 : 10))
                    .foregroundStyle(WKColor.teal)
                Spacer(minLength: 0)
                Text("🎵\(w.appCount)곡")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WKColor.fill.opacity(0.9))
            }
            .wkPanel(8)

            Spacer(minLength: 0)

            WKLyricLine(text: "오늘은 적당히 부르기로 해요", size: family == .systemMedium ? 18 : 13)

            Spacer(minLength: 0)

            HStack {
                Text("하루 한도")
                    .font(.system(size: 9))
                    .foregroundStyle(WKColor.fill.opacity(0.7))
                Spacer()
                Text(limitLED(w.dailyLimitMinutes))
                    .font(.wkSeg(family == .systemMedium ? 18 : 14))
                    .foregroundStyle(WKColor.teal)
                    .monospacedDigit()
            }
            .wkPanel(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 하루 한도(분) → "HH:MM" LED 표기.
    private func limitLED(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: 3) 노래 안하는중

    private var idle: some View {
        VStack(spacing: 6) {
            Text("🎤").font(.system(size: 26))
            Text("다음 곡 대기중")
                .font(.wkMyungjo(family == .systemMedium ? 18 : 15))
                .foregroundStyle(WKColor.fill)
            Text("노래를 시작하면 가사가 흘러요")
                .font(.wkMyungjoLight(11))
                .foregroundStyle(WKColor.cyan.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .wkPanel(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
