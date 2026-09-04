import Foundation
import StoreKit

/// 월 구독 상태를 관리한다(StoreKit 2).
/// - 현재 구독권(entitlement) 보유 여부를 `isSubscribed`로 노출.
/// - 앱 실행 중 들어오는 트랜잭션 업데이트(갱신/환불 등)를 실시간 반영.
/// - 구독이 없으면 앱 본화면을 막는 게이트로 쓰인다(RootView).
@MainActor
final class SubscriptionManager: ObservableObject {
    /// App Store Connect에 등록할 자동 갱신 구독 상품 ID(월 ₩3,000).
    static let monthlyProductID = "hime.app.todolock.pro.monthly"

    /// 구독권 보유 여부. 이 값이 true일 때만 앱을 쓸 수 있다.
    @Published private(set) var isSubscribed = false
    /// 판매용 월 구독 상품. 로드 실패 시 nil.
    @Published private(set) var monthlyProduct: Product?
    /// 최초 상태 확인이 끝나기 전. 스플래시로 가리는 동안 깜빡임을 막는다.
    @Published private(set) var isLoading = true
    /// 구매/복원 진행 중. 버튼 중복 탭 방지.
    @Published var purchaseInProgress = false
    /// 사용자에게 보여줄 마지막 오류 메시지.
    @Published var errorMessage: String?

    /// 이 사용자가 무료 체험(introductory offer)을 받을 자격이 있는지.
    /// 이미 한 번 체험·구독했던 사용자에겐 false가 되어 "무료 체험" 문구를 숨긴다.
    @Published private(set) var isEligibleForTrial = true
    private var storeKitTrialEligibility = true

    private var updatesTask: Task<Void, Never>?

    /// 상품에 설정된 무료 체험 기간(예: "7일"). 없으면 nil.
    var trialPeriodText: String? {
        guard let offer = monthlyProduct?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return Self.localizedPeriod(offer.period)
    }

    /// 무료 체험을 표시할지(상품에 체험이 있고 + 자격이 있을 때만).
    var showsTrial: Bool { trialPeriodText != nil && isEligibleForTrial }

    private static func localizedPeriod(_ period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day:   return "\(n)일"
        case .week:  return "\(n * 7)일"
        case .month: return "\(n)개월"
        case .year:  return "\(n)년"
        @unknown default: return "\(n)"
        }
    }

    init() {
        // 백그라운드 갱신·구매 복원 등으로 들어오는 트랜잭션을 계속 감시.
        updatesTask = listenForTransactions()
        Task {
            // 콜드 런치 직후 네트워크가 덜 올라와 상품이 비어 오는 경우가 있어 몇 번 재시도한다.
            await loadProducts(retryCount: 3)
            await refreshSubscriptionStatus()
            isLoading = false
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 판매 상품 정보를 App Store에서 로드.
    /// 빈 결과(ASC 전파 지연 등)나 일시 오류면 잠깐 쉬고 `retryCount`만큼 더 시도한다.
    /// - Returns: 상품을 실제로 받았으면 true.
    @discardableResult
    func loadProducts(retryCount: Int = 0) async -> Bool {
        let attempts = max(0, retryCount)
        for attempt in 0...attempts {
            do {
                let products = try await Product.products(for: [Self.monthlyProductID])
                if let product = products.first {
                    monthlyProduct = product
                    // 무료 체험을 이미 소진했는지 확인(같은 구독 그룹 기준).
                    if let sub = product.subscription {
                        updateTrialEligibility(storeKitEligible: await sub.isEligibleForIntroOffer)
                    } else {
                        updateTrialEligibility(storeKitEligible: false)
                    }
                    return true
                }
                // 상품이 비어 돌아옴 — 남은 시도가 있으면 잠깐 뒤 다시.
            } catch {
                // 네트워크 등 일시 오류 — 남은 시도가 있으면 다시.
            }
            if attempt < attempts {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5초
            }
        }
        monthlyProduct = nil
        updateTrialEligibility(storeKitEligible: false)
        return false
    }

    /// 현재 유효한 구독권이 있는지 확인. currentEntitlements는
    /// 만료/환불되지 않은 트랜잭션만 내보내므로, 우리 상품이 있으면 구독 중.
    func refreshSubscriptionStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.monthlyProductID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
    }


    /// 월 구독 구매.
    func purchase() async {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        // 상품이 아직 로드되지 않았으면(일시 오류 등) 한 번 더 받아본 뒤 진행한다.
        if monthlyProduct == nil {
            await loadProducts(retryCount: 1)
        }
        guard let product = monthlyProduct else {
            errorMessage = "상품 정보를 불러오지 못했어요. 네트워크를 확인하고 잠시 후 다시 시도해주세요."
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshSubscriptionStatus()
                } else {
                    errorMessage = "결제 검증에 실패했어요. 다시 시도해주세요."
                }
            case .userCancelled:
                break
            case .pending:
                // '구매 요청 승인 대기'(가족 공유 승인 등). 승인되면 updates로 들어온다.
                errorMessage = "구매 승인 대기 중이에요. 승인되면 자동으로 열려요."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "결제 중 문제가 생겼어요. 다시 시도해주세요."
        }
    }

    /// 기기 변경·재설치 후 기존 구독 복원.
    func restore() async {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()
            if !isSubscribed {
                errorMessage = "복원할 구독을 찾지 못했어요."
            }
        } catch {
            errorMessage = "구독 복원에 실패했어요. 다시 시도해주세요."
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshSubscriptionStatus()
            }
        }
    }

    private func updateTrialEligibility(storeKitEligible: Bool) {
        storeKitTrialEligibility = storeKitEligible
        isEligibleForTrial = storeKitEligible
    }
}
