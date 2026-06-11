import ManagedSettings
import ManagedSettingsUI
import UIKit

/// 차단된 앱을 사용자가 열 때 iOS가 띄우는 화면 구성.
/// 별도 타깃 (App Extension)으로 빌드. 메인 앱과 App Group 공유.
///
/// ShieldConfiguration은 SwiftUI를 쓸 수 없고 색/아이콘/라벨만 지정할 수 있다.
/// 그래서 노래방 테마는 메인 앱의 CRT 룩과 같은 팔레트(남보라 무대 배경 · 노란 자막 ·
/// 시안 부제 · 초록 점프 버튼)와 마이크 아이콘으로 최대한 맞춘다.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    /// 노래방 무대 팔레트 (KColor와 동일 톤의 UIKit 버전).
    private enum KShield {
        // 무대 남보라 — 가려진 앱 위로 거의 불투명하게 덮어 노래방 배경처럼 보이게 한다.
        static let stage = UIColor(red: 0.07, green: 0.06, blue: 0.22, alpha: 0.94)
        static let yellow = UIColor(red: 1.0, green: 0.82, blue: 0.23, alpha: 1)
        static let cyan = UIColor(red: 0.55, green: 0.93, blue: 0.93, alpha: 1)
        static let green = UIColor(red: 0.41, green: 0.79, blue: 0.31, alpha: 1)
        static let darkInk = UIColor(red: 0.04, green: 0.15, blue: 0.02, alpha: 1)
        static let secondary = UIColor(white: 1, alpha: 0.6)

        /// 노란 마이크 아이콘 — 인트로 화면의 music.mic과 같은 톤.
        static var micIcon: UIImage? {
            let config = UIImage.SymbolConfiguration(pointSize: 56, weight: .bold)
            return UIImage(systemName: "music.mic", withConfiguration: config)?
                .withTintColor(yellow, renderingMode: .alwaysOriginal)
        }
    }

    /// 앱·웹·분류 어디서 막혔든 같은 노래방 룩을 쓴다.
    private var karaokeConfiguration: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: KShield.stage,
            icon: KShield.micIcon,
            title: ShieldConfiguration.Label(
                text: "지금은 노래 부르는 중 🎤",
                color: KShield.yellow
            ),
            subtitle: ShieldConfiguration.Label(
                text: "과업을 완료하면 잠깐 점프할 수 있어요",
                color: KShield.cyan
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "과업 수행하기 ▶",
                color: KShield.darkInk
            ),
            primaryButtonBackgroundColor: KShield.green,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "닫기",
                color: KShield.secondary
            )
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        karaokeConfiguration
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
