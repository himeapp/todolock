import ManagedSettings
import ManagedSettingsUI
import FamilyControls
import UIKit

/// 차단된 앱을 사용자가 열 때 iOS가 띄우는 화면 구성.
/// 별도 타깃 (App Extension)으로 빌드. 메인 앱과 App Group 공유.
///
/// ShieldConfiguration은 SwiftUI를 쓸 수 없고 색/아이콘/라벨만 지정할 수 있다.
/// 그래서 옛날 노래방 TV의 컬러바(화면조정) 패턴을 UIImage로 직접 그려 아이콘에 넣고,
/// 남보라 무대 배경 + 노래방 멘트로 마무리한다.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    /// 간주 점프로 풀리는 시간(분). 앱이 세션 시작 때 App Group에 적어둔 값을 읽는다.
    private var jumpMinutes: Int {
        let v = UserDefaults(suiteName: "group.hime.app.todolock")?.integer(forKey: "passDurationMinutes") ?? 0
        return v > 0 ? v : 15
    }

    private static let appGroupId = "group.hime.app.todolock"
    private var defaults: UserDefaults? { UserDefaults(suiteName: Self.appGroupId) }

    /// 이 앱이 "감시 한도 초과"로 막힌 건지 판단한다.
    /// 잠금 세션이 같은 앱을 막고 있으면 잠금(간주 점프 제공)이 우선이라 false.
    private func isWatchdogBlocked(_ token: ApplicationToken) -> Bool {
        if lockedBySession(token) { return false }
        guard let data = defaults?.data(forKey: "watchdogSelectionData"),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return false }
        return sel.applicationTokens.contains(token)
    }

    /// 활성 잠금 세션 중 하나라도 이 앱을 잠그고 있는지.
    private func lockedBySession(_ token: ApplicationToken) -> Bool {
        guard let map = defaults?.dictionary(forKey: "sessionSelections") as? [String: Data] else { return false }
        for data in map.values {
            if let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
               sel.applicationTokens.contains(token) { return true }
        }
        return false
    }

    /// 노래방 무대 팔레트 (KColor와 동일 톤의 UIKit 버전).
    private enum KShield {
        // 무대 남보라 — 가려진 앱 위로 거의 불투명하게 덮어 노래방 배경처럼 보이게 한다.
        static let stage = UIColor(red: 0.05, green: 0.05, blue: 0.16, alpha: 0.96)
        static let yellow = UIColor(red: 1.0, green: 0.82, blue: 0.23, alpha: 1)
        static let cyan = UIColor(red: 0.55, green: 0.93, blue: 0.93, alpha: 1)
        static let green = UIColor(red: 0.41, green: 0.79, blue: 0.31, alpha: 1)
        static let darkInk = UIColor(red: 0.04, green: 0.15, blue: 0.02, alpha: 1)
        static let secondary = UIColor(white: 1, alpha: 0.6)

        /// 옛날 노래방 TV의 컬러바(화면조정) + 지지직 + 스캔라인을 그린 카드.
        static var tvIcon: UIImage? {
            let size = CGSize(width: 300, height: 210)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { ctx in
                let c = ctx.cgContext
                // SMPTE 7색 세로 컬러바 (위 80%)
                let bars: [UIColor] = [
                    UIColor(white: 0.78, alpha: 1),
                    UIColor(red: 0.93, green: 0.80, blue: 0.20, alpha: 1),  // 옐로
                    UIColor(red: 0.30, green: 0.85, blue: 0.85, alpha: 1),  // 시안
                    UIColor(red: 0.25, green: 0.78, blue: 0.30, alpha: 1),  // 그린
                    UIColor(red: 0.82, green: 0.24, blue: 0.62, alpha: 1),  // 마젠타
                    UIColor(red: 0.88, green: 0.22, blue: 0.22, alpha: 1),  // 레드
                    UIColor(red: 0.20, green: 0.30, blue: 0.80, alpha: 1)   // 블루
                ]
                let barW = size.width / CGFloat(bars.count)
                let barH = size.height * 0.78
                for (i, color) in bars.enumerated() {
                    c.setFillColor(color.cgColor)
                    c.fill(CGRect(x: CGFloat(i) * barW, y: 0, width: barW + 1, height: barH))
                }
                // 아래 어두운 띠
                c.setFillColor(UIColor(white: 0.06, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: barH, width: size.width, height: size.height - barH))

                // 스캔라인
                c.setFillColor(UIColor.black.withAlphaComponent(0.14).cgColor)
                var y: CGFloat = 0
                while y < size.height { c.fill(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }

                // 지지직 노이즈 (결정적)
                var s: UInt64 = 0x9E3779B97F4A7C15
                func rnd() -> Double { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return Double(s % 1000) / 1000 }
                for _ in 0..<420 {
                    let a = 0.05 + rnd() * 0.30
                    c.setFillColor(UIColor.white.withAlphaComponent(a).cgColor)
                    c.fill(CGRect(x: rnd() * size.width, y: rnd() * size.height, width: 0.8 + rnd() * 1.6, height: 1))
                }

                // 가운데 "♪ 반주 중 ♪" 노래방 자막
                let label = "♪ 반주 중 ♪"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let textSize = (label as NSString).size(withAttributes: attrs)
                let pad: CGFloat = 10
                let box = CGRect(
                    x: (size.width - textSize.width) / 2 - pad,
                    y: barH - textSize.height - pad * 1.4,
                    width: textSize.width + pad * 2,
                    height: textSize.height + pad
                )
                c.setFillColor(UIColor.black.withAlphaComponent(0.62).cgColor)
                let path = UIBezierPath(roundedRect: box, cornerRadius: 5)
                c.addPath(path.cgPath); c.fillPath()
                (label as NSString).draw(
                    at: CGPoint(x: box.minX + pad, y: box.minY + pad / 2),
                    withAttributes: attrs
                )
            }
            return img.withRenderingMode(.alwaysOriginal)
        }
    }

    /// 앱·웹·분류 어디서 막혔든 같은 노래방 룩을 쓴다.
    private var karaokeConfiguration: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: KShield.stage,
            icon: KShield.tvIcon,
            title: ShieldConfiguration.Label(
                text: "지금은 열창중",
                color: KShield.yellow
            ),
            subtitle: ShieldConfiguration.Label(
                text: "정말 꼭 필요하다면\n과제을 수행하세요",
                color: KShield.cyan
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "\(jumpMinutes)분만 간주 점프",
                color: KShield.darkInk
            ),
            primaryButtonBackgroundColor: KShield.green,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "닫기",
                color: KShield.secondary
            )
        )
    }

    /// 감시 한도 초과로 막힌 화면. 간주 점프가 없으므로 닫기만 둔다.
    private var watchdogConfiguration: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: KShield.stage,
            icon: KShield.tvIcon,
            title: ShieldConfiguration.Label(
                text: "오늘은 충분히 불렀어요 🎤",
                color: KShield.yellow
            ),
            subtitle: ShieldConfiguration.Label(
                text: "하루 한도를 다 썼어요\n내일 다시 만나요 👋",
                color: KShield.cyan
            ),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "확인",
                color: KShield.secondary
            )
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        if let token = application.token, isWatchdogBlocked(token) {
            return watchdogConfiguration
        }
        return karaokeConfiguration
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        karaokeConfiguration
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        karaokeConfiguration
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        karaokeConfiguration
    }
}
