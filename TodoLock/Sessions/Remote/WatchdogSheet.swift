import SwiftUI

// 사용량 감시 기능 — 고른 앱을 하루 N시간 넘게 쓰면 알림으로 찔러주고,
// 탭하면 곧장 잠금 세션으로 이어준다. 자동 갱신 구독 만료 알림은 역효과라
// "앱을 쓰게 만드는" 방향으로 대신 넣은 기능.
//
// ⚠️ FamilyControls 프라이버시상 실제 사용 분(分)·앱 이름을 코드로 못 읽으므로,
//    "정확히 몇 시간"이 아니라 "내가 정한 한도를 넘는 순간"만 알 수 있다(threshold).
//
// 감시는 별도 시트가 아니라 리모컨의 한 "모드"다 — 감시 키를 누르면 같은 LED·
// 숫자패드·시간키·시작 버튼이 감시용으로 변신한다(RemoteControlView의 vm.mode).
// 따라서 이 파일엔 그 토글 키(WatchdogButton)만 남는다. 한도 입력·앱 선택·걸기는
// 전부 RemoteControlView가 모드 분기로 처리한다.

// MARK: - 홈 리모컨 "감시" 모드 토글 키

/// 모드 줄 3번째 자리에 들어가는 감시 키.
/// 프리셋(아이보리)·점프(초록)와 한눈에 구분되도록 **인디고 키캡**으로 차별화한다.
/// 감시 모드가 켜져 있으면 흰색 테두리로 발광시켜 현재 모드를 알린다.
struct WatchdogButton: View {
    /// 감시 모드가 켜져 있는지. 켜져 있으면 테두리가 흰색으로 발광한다.
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // 같은 줄의 모드/점프 키(FuncButton·PresetButton)와 동일한 균일 볼드 고딕 18pt.
            Text("감시")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(
                        LinearGradient(colors: [Color(wd: 0x6f7bf2), Color(wd: 0x4f56d8)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 2.5, y: 1.5)
                )
                .overlay(alignment: .top) { keycapGloss(radius: 16) }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isActive ? Color.white : .black.opacity(0.12),
                                lineWidth: isActive ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// 이 파일 전용 hex 색 이니셜라이저(RemoteControlView의 것은 file-private이라 재정의).
private extension Color {
    init(wd hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
