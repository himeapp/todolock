import WidgetKit
import SwiftUI
import ActivityKit

// 잠금화면 + 다이나믹 아일랜드 Live Activity.
// 남은시간 카운트다운과 진행바는 시스템이 알아서 실시간으로 흐른다(Text/ProgressView timerInterval).
// 가사 줄은 앱이 포그라운드일 때 lineIndex를 갱신해 넘어간다(로컬 푸시 한계상 백그라운드 자동 넘김은 불가).

@available(iOS 16.1, *)
struct LockLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockActivityAttributes.self) { context in
            LockLockScreenView(context: context)
                .activityBackgroundTint(WKColor.night2.opacity(0.92))
                .activitySystemActionForegroundColor(WKColor.cyan)
        } dynamicIsland: { context in
            // 잠금 시간이 끝나면(staleDate=endsAt 경과) 완료 상태로 바뀐다.
            // 간주(일시정지) 중엔 완료로 보지 않는다.
            let done = context.isStale && !context.state.isPaused
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        WKKaraokeTV().frame(width: 26, height: 18)
                        Text("🎵\(context.attributes.appCount)곡")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WKColor.fill)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if done {
                        Text(context.attributes.hideScore ? "완주 ♪" : "100점")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(WKColor.amber)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                            .font(.wkSeg(13))
                            .foregroundStyle(WKColor.amber)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.songTitle)
                        .font(.wkMyungjoLight(11))
                        .foregroundStyle(WKColor.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if done {
                        WKCompletionLine(hideScore: context.attributes.hideScore, size: 19)
                            .padding(.vertical, 3)
                    } else if context.state.isPaused {
                        WKInterludeLine()
                            .padding(.vertical, 3)
                    } else {
                        // 가사 줄 + 진행바. 큰 상태에서 글자 테두리가 위아래로 잘리지 않게
                        // 크기를 약간 줄이고 세로 여백을 둔다.
                        VStack(spacing: 5) {
                            WKLyricLine(text: currentLine(context), size: 17)
                                .padding(.top, 2)
                            ProgressView(timerInterval: context.state.startedAt...context.state.endsAt,
                                         countsDown: false) {
                                EmptyView()
                            } currentValueLabel: { EmptyView() }
                                .tint(WKColor.highlight)
                                .labelsHidden()
                        }
                        .padding(.bottom, 2)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    WKKaraokeTV(corner: 3).frame(width: 22, height: 15)
                    if context.state.isPaused && !done {
                        Text("간주")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WKColor.pink)
                            .lineLimit(1)
                    } else {
                        Text(context.attributes.nickname)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WKColor.cyan)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } compactTrailing: {
                if done {
                    Text("🎉")
                        .font(.system(size: 14))
                        .frame(width: 30)
                } else if context.state.isPaused {
                    Text("♪")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WKColor.pink)
                        .frame(width: 30)
                } else {
                    Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WKColor.amber)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 56)
                }
            } minimal: {
                if done {
                    Text("🎉").font(.system(size: 15))
                } else if context.state.isPaused {
                    Text("♪").font(.system(size: 15)).foregroundStyle(WKColor.pink)
                } else {
                    WKKaraokeTV(corner: 3).frame(width: 22, height: 16)
                }
            }
            .keylineTint(WKColor.highlight)
        }
    }

    private func currentLine(_ context: ActivityViewContext<LockActivityAttributes>) -> String {
        context.attributes.lyrics[safe: context.state.lineIndex] ?? context.attributes.lyrics.first ?? ""
    }
}

// MARK: - 완료 축하 한 줄 (잠금 완주)

/// 잠금 시간을 끝까지 버틴 순간 보여줄 한 줄. 점수 제거가 켜져 있으면 점수 대신
/// 차분한 완주 문구를 쓴다. 가사 자막과 같은 테두리 명조 룩으로 통일.
@available(iOS 16.1, *)
struct WKCompletionLine: View {
    var hideScore: Bool
    var size: CGFloat = 19

    var body: some View {
        HStack(spacing: 8) {
            Text("🎉")
                .font(.system(size: size * 0.9))
            if hideScore {
                WKLyricLine(text: "완주! 수고했어요", size: size)
            } else {
                WKLyricLine(text: "완창! 100점", size: size)
            }
            Text("🎉")
                .font(.system(size: size * 0.9))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 잠금화면 카드

@available(iOS 16.1, *)
struct LockLockScreenView: View {
    let context: ActivityViewContext<LockActivityAttributes>

    private var line: String {
        context.attributes.lyrics[safe: context.state.lineIndex] ?? context.attributes.lyrics.first ?? ""
    }
    private var nextLine: String {
        context.attributes.lyrics[safe: context.state.lineIndex + 1] ?? context.attributes.lyrics.first ?? ""
    }

    /// 잠금 시간이 끝났는지(간주 중이 아니고 staleDate 경과).
    private var isDone: Bool { context.isStale && !context.state.isPaused }

    var body: some View {
        if isDone {
            completionCard
        } else {
            playingCard
        }
    }

    // 끝까지 버틴 완료 카드 — 성취감을 주는 축하 화면(점수 제거 시 차분한 완주).
    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("🎤").font(.system(size: 13))
                Text(context.attributes.songTitle)
                    .font(.wkMyungjoLight(12))
                    .foregroundStyle(WKColor.cyan)
                    .lineLimit(1)
                Spacer()
                Text("완창 ★")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WKColor.amber)
            }

            HStack(spacing: 10) {
                Text("🎉").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    if context.attributes.hideScore {
                        WKLyricLine(text: "완주했어요!", size: 24)
                        Text("끝까지 잘 참았어요")
                            .font(.wkMyungjoLight(13))
                            .foregroundStyle(WKColor.fill.opacity(0.7))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("100")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(WKColor.amber)
                            Text("점")
                                .font(.wkMyungjo(18))
                                .foregroundStyle(WKColor.fill)
                        }
                        Text("완창했어요! 끝까지 잘 참았어요")
                            .font(.wkMyungjoLight(13))
                            .foregroundStyle(WKColor.fill.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                Text("🎉").font(.system(size: 30))
            }
        }
        .padding(14)
    }

    private var playingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("🎤").font(.system(size: 13))
                Text(context.attributes.songTitle)
                    .font(.wkMyungjoLight(12))
                    .foregroundStyle(WKColor.cyan)
                    .lineLimit(1)
                Spacer()
                if context.state.isPaused {
                    Text("간주중 ♪")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WKColor.pink)
                } else {
                    Text("🎵 \(context.attributes.appCount)곡 예약")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WKColor.fill.opacity(0.85))
                }
            }

            if context.state.isPaused {
                WKInterludeLine()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    WKLyricLine(text: line, size: 22)
                    Text(nextLine)
                        .font(.wkMyungjo(15))
                        .foregroundStyle(WKColor.fill.opacity(0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                ProgressView(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
                    .tint(WKColor.highlight)
                    .labelsHidden()
                Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                    .font(.wkSeg(17))
                    .foregroundStyle(WKColor.amber)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: 92, alignment: .trailing)
            }
        }
        .padding(14)
    }
}
