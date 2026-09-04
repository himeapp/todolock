import SwiftUI

// 위젯/Live Activity 전용 노래방 CRT 스타일.
// (앱의 KaraokeKit은 FamilyControls·무거운 뷰를 끌고와 위젯에 못 넣으므로 최소 버전을 따로 둔다.)

enum WKColor {
    static let outline = Color(red: 0.05, green: 0.07, blue: 0.34)   // 자막 테두리 남색
    static let fill = Color.white
    static let cyan = Color(red: 0.22, green: 0.91, blue: 0.91)
    static let highlight = Color(red: 0.30, green: 0.62, blue: 1.0)  // 노래방 파란 채움
    static let night1 = Color(red: 0.11, green: 0.18, blue: 0.46)
    static let night2 = Color(red: 0.04, green: 0.06, blue: 0.22)
    static let pink = Color(red: 1.0, green: 0.45, blue: 0.72)
    static let amber = Color(red: 1.0, green: 0.82, blue: 0.30)
    static let teal = Color(red: 0.20, green: 0.74, blue: 0.66)   // 감시 모드 액센트(앱과 동일)
}

extension Font {
    static func wkMyungjo(_ size: CGFloat) -> Font { .custom("NanumMyeongjoExtraBold", size: size) }
    static func wkMyungjoLight(_ size: CGFloat) -> Font { .custom("NanumMyeongjo", size: size) }
    static func wkSeg(_ size: CGFloat) -> Font { .custom("DSEG7Classic-Bold", size: size) }
}

// MARK: - 테두리 자막 가사 한 줄

struct WKLyricLine: View {
    let text: String
    var size: CGFloat = 18
    /// 0...1 진행에 따라 파란색으로 채워지는 노래방 효과.
    var fillProgress: Double = 1

    var body: some View {
        ZStack {
            // 테두리(여러 방향 스트로크 모사)
            ForEach(WKLyricLine.offsets, id: \.self) { o in
                base.foregroundStyle(WKColor.outline).offset(x: o.x, y: o.y)
            }
            // 채움: 흰 글자 위에 파란색이 왼→오로 차오름
            base.foregroundStyle(WKColor.fill)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        base.foregroundStyle(WKColor.highlight)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geo.size.width * fillProgress)
                            }
                    }
                }
                .mask { base }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private var base: some View {
        Text(text).font(.wkMyungjo(size))
    }

    private static let offsets: [CGPoint] = [
        .init(x: -1.2, y: 0), .init(x: 1.2, y: 0), .init(x: 0, y: -1.2), .init(x: 0, y: 1.2),
        .init(x: -1, y: -1), .init(x: 1, y: -1), .init(x: -1, y: 1), .init(x: 1, y: 1)
    ]
}

// MARK: - 가로 스캔라인

struct WKScanlines: View {
    var gap: CGFloat = 3
    var opacity: Double = 0.18
    var body: some View {
        GeometryReader { geo in
            Path { p in
                var y: CGFloat = 0
                while y < geo.size.height {
                    p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: geo.size.width, y: y))
                    y += gap
                }
            }
            .stroke(Color.black.opacity(opacity), lineWidth: 1)
        }
    }
}

// MARK: - 전체화면 노래방 CRT 배경 (홈 위젯용)

/// 앱 잠금화면(KaraokeBackground)의 저녁 하늘 + 스캔라인 + 비네트 — 정적 풀블리드 버전.
struct WKKaraokeScreen: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.68, blue: 0.88),
                    Color(red: 0.60, green: 0.72, blue: 0.90),
                    Color(red: 0.65, green: 0.75, blue: 0.90),
                    Color(red: 0.52, green: 0.65, blue: 0.82),
                    Color(red: 0.48, green: 0.60, blue: 0.78)
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.40), .clear],
                center: UnitPoint(x: 0.5, y: 0.28), startRadius: 8, endRadius: 200
            )
            .blendMode(.screen)
            WKScanlines(gap: 3, opacity: 0.20)
            RadialGradient(
                colors: [.clear, .black.opacity(0.42)],
                center: .center, startRadius: 50, endRadius: 320
            )
        }
    }
}

/// 옅은 하늘 위 글자가 묻히지 않게 까는 어두운 반투명 패널 (앱의 NowPlayingBox 톤).
struct WKPanel: ViewModifier {
    var padding: CGFloat = 8
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .padding(.vertical, padding * 0.6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.20).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
            )
    }
}

extension View {
    func wkPanel(_ padding: CGFloat = 8) -> some View { modifier(WKPanel(padding: padding)) }
}

// MARK: - 간주 중 한 줄 표시 (Live Activity / 위젯용)

/// 가사 자리를 대신하는 "간주 점프 중" 한 줄. 잠금화면 Live Activity와 다이나믹 아일랜드가 공유.
struct WKInterludeLine: View {
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: 6) {
            Text("♪")
                .font(.wkMyungjo(size))
                .foregroundStyle(WKColor.pink)
            WKLyricLine(text: "간주 점프 중", size: size)
                .foregroundStyle(WKColor.pink)
            Text("♪")
                .font(.wkMyungjo(size))
                .foregroundStyle(WKColor.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 미니 노래방 CRT 화면 (앱의 KaraokeBackground와 같은 룩)

/// 다이나믹 아일랜드에 들어갈 작은 노래방 TV.
/// 앱 잠금화면(KaraokeBackground)의 옅은 저녁 하늘 + 스캔라인 + 비네트를 정적 버전으로 옮겼다.
struct WKKaraokeTV: View {
    var corner: CGFloat = 4
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.68, blue: 0.88),
                    Color(red: 0.60, green: 0.72, blue: 0.90),
                    Color(red: 0.65, green: 0.75, blue: 0.90),
                    Color(red: 0.52, green: 0.65, blue: 0.82),
                    Color(red: 0.48, green: 0.60, blue: 0.78)
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.55), .clear],
                center: UnitPoint(x: 0.5, y: 0.32), startRadius: 1, endRadius: 34
            )
            .blendMode(.screen)
            WKScanlines(gap: 2, opacity: 0.28)
            RadialGradient(
                colors: [.clear, .black.opacity(0.42)],
                center: .center, startRadius: 2, endRadius: 30
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
        )
    }
}
