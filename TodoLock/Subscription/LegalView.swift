import SwiftUI

/// 이용약관 / 개인정보 처리방침 화면.
/// himeapp/etc(Mantra Reminder) 법무 문서를 투두락(구독형 + 기기 내 처리)에 맞게 각색.
/// 문서 본문은 섹션 배열로 관리하고 LegalDocumentView가 공통 렌더링한다.

enum LegalDoc {
    /// 법무 문의·운영자 정보. 필요 시 한곳만 바꾸면 두 문서에 반영된다.
    static let provider = "Jinyoung Kim(김진영)"
    static let contactEmail = "himeggim@gmail.com"
    static let effectiveDate = "2026-06-11"

    struct Section: Identifiable {
        let id = UUID()
        let heading: String?
        let body: String
    }

    static let terms: [Section] = [
        .init(heading: nil, body: """
        본 이용약관은 \(provider)(이하 "서비스 제공자")이 제공하는 투두락 앱(이하 "애플리케이션")에 적용됩니다. 애플리케이션을 다운로드하거나 이용하는 시점부터 귀하는 아래 약관에 동의한 것으로 간주됩니다. 이용 전 본 약관을 충분히 읽어주세요.
        """),
        .init(heading: "지적재산권", body: """
        애플리케이션, 그 일부 또는 상표에 대한 무단 복제·수정은 금지됩니다. 소스 코드 추출, 다른 언어로의 번역, 파생 버전 제작 시도는 허용되지 않습니다. 애플리케이션과 관련된 모든 상표·저작권·기타 지적재산권은 서비스 제공자에게 귀속됩니다.
        """),
        .init(heading: "구독 및 결제", body: """
        투두락은 월 자동 갱신 구독으로 제공됩니다. 신규 사용자에게는 7일 무료 체험이 제공될 수 있습니다.

        • 무료 체험 기간 종료 24시간 전까지 해지하지 않으면 유료 구독으로 자동 전환되며, 등록된 Apple 계정에 요금이 청구됩니다.
        • 체험 기간 안에 해지하면 요금이 청구되지 않습니다.
        • 구독은 현재 기간 종료 24시간 전까지 해지하지 않으면 동일 조건으로 자동 갱신됩니다.
        • 결제는 Apple App Store 계정을 통해 이루어지며, 구독 관리·해지는 기기의 [설정] > Apple 계정 > 구독에서 할 수 있습니다.
        • 환불은 Apple의 정책 및 절차를 따릅니다. 무료 체험의 남은 기간은 유료 구독 시작 시 소멸될 수 있습니다.
        • 가격은 사전 고지 후 변경될 수 있습니다.
        """),
        .init(heading: "데이터 및 기기 보안", body: """
        애플리케이션은 서비스 제공을 위해 잠금 설정·과제 기록 등을 귀하의 기기에 저장·처리합니다. 휴대전화 및 애플리케이션 접근의 보안 유지는 귀하의 책임입니다. 공식 운영체제의 제한을 제거하는 탈옥(jailbreak)·루팅(rooting)은 보안을 약화시키고 애플리케이션이 정상 동작하지 않게 할 수 있으므로 권장하지 않습니다.
        """),
        .init(heading: "책임의 한계", body: """
        애플리케이션의 스크린타임 기반 잠금 기능은 운영체제(iOS)의 동작에 의존하며, 서비스 제공자는 OS 정책 변경이나 기기 상태로 인해 기능이 제한되는 경우에 대해 책임지지 않습니다. 기기 충전 상태 유지 등 정상 이용을 위한 환경 관리는 귀하의 책임입니다.
        """),
        .init(heading: "업데이트 및 종료", body: """
        서비스 제공자는 애플리케이션을 업데이트하거나, 사전 통지 없이 제공을 중단할 수 있습니다. 운영체제 요구사항이 바뀌면 계속 이용을 위해 업데이트가 필요할 수 있습니다. 종료 시 본 약관에 따라 부여된 권리는 종료되며, 귀하는 이용을 중단해야 합니다.
        """),
        .init(heading: "약관의 변경", body: """
        서비스 제공자는 이용약관을 수시로 개정할 수 있습니다. 변경 사항은 본 화면에 게시함으로써 안내됩니다.

        시행일: \(effectiveDate)
        """),
        .init(heading: "문의", body: """
        이용약관에 관한 문의는 \(contactEmail)으로 연락해 주세요.
        """),
    ]

    static let privacy: [Section] = [
        .init(heading: nil, body: """
        본 개인정보 처리방침은 \(provider)(이하 "서비스 제공자")이 제공하는 투두락 앱(이하 "애플리케이션")에 적용됩니다. 본 서비스는 "있는 그대로(AS IS)" 제공됩니다.
        """),
        .init(heading: "기기 내 처리 원칙", body: """
        투두락은 동작에 필요한 데이터를 가능한 한 귀하의 기기 안에서만 처리합니다.

        • 잠금 대상 앱·카테고리 선택은 Apple의 스크린타임(Family Controls) 프레임워크가 관리하며, 서비스 제공자는 귀하가 어떤 앱을 잠갔는지에 대한 식별 정보를 받지 않습니다.
        • 사진 인증 과제으로 촬영·선택한 사진은 기기 안에서만 검수되며 외부로 전송·저장되지 않습니다.
        • 잠금 기록·통계·모드 설정 등은 귀하의 기기에 저장됩니다.
        """),
        .init(heading: "결제 정보", body: """
        구독 결제는 Apple App Store가 처리합니다. 서비스 제공자는 귀하의 결제 수단(카드번호 등) 정보를 수집하거나 보관하지 않습니다. 결제·구독 상태 확인은 Apple이 제공하는 범위 내에서만 이루어집니다.
        """),
        .init(heading: "수집하는 정보", body: """
        애플리케이션은 서비스 운영·개선을 위해 기기·이용 환경에 관한 제한적 정보(예: 운영체제 버전, 앱 이용 중 발생한 오류 정보)를 처리할 수 있습니다. 애플리케이션은 정확한 위치 정보를 수집하지 않으며, 귀하의 데이터를 처리하기 위해 인공지능(AI) 기술을 사용하지 않습니다.
        """),
        .init(heading: "제3자 제공", body: """
        서비스 제공자는 법령에 따른 요구가 있는 경우, 또는 권리·안전 보호를 위해 필요하다고 선의로 판단하는 경우에 한해 정보를 공개할 수 있습니다. 그 밖에 마케팅 목적으로 귀하의 개인정보를 제3자에게 판매하지 않습니다.
        """),
        .init(heading: "수집 거부 및 삭제", body: """
        애플리케이션을 삭제하면 기기에 저장된 데이터 수집이 중단됩니다. 서비스 제공자에게 제공한 데이터의 삭제를 원하시면 \(contactEmail)으로 연락해 주세요.
        """),
        .init(heading: "아동", body: """
        서비스 제공자는 만 13세 미만 아동으로부터 고의로 개인정보를 수집하지 않습니다. 아동이 개인정보를 제공했다고 판단되는 경우 \(contactEmail)으로 연락해 주시면 필요한 조치를 취하겠습니다.
        """),
        .init(heading: "보안", body: """
        서비스 제공자는 처리·유지하는 정보를 보호하기 위해 물리적·전자적·절차적 안전조치를 마련합니다.
        """),
        .init(heading: "변경", body: """
        본 개인정보 처리방침은 수시로 업데이트될 수 있으며, 변경 시 본 화면에 게시하여 안내합니다.

        시행일: \(effectiveDate)
        """),
        .init(heading: "문의", body: """
        개인정보에 관한 문의는 \(contactEmail)으로 연락해 주세요.
        """),
    ]
}

/// 약관/방침 공통 렌더러.
struct LegalDocumentView: View {
    let title: String
    let sections: [LegalDoc.Section]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.headline)
                        }
                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsView: View {
    var body: some View { LegalDocumentView(title: "이용약관", sections: LegalDoc.terms) }
}

struct PrivacyView: View {
    var body: some View { LegalDocumentView(title: "개인정보 처리방침", sections: LegalDoc.privacy) }
}
