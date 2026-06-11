import SwiftUI
import FamilyControls

// 사용량 감시 기능 — 고른 앱을 하루 N시간 넘게 쓰면 알림으로 찔러주고,
// 탭하면 곧장 잠금 세션으로 이어준다. 자동 갱신 구독 만료 알림은 역효과라
// "앱을 쓰게 만드는" 방향으로 대신 넣은 기능.
//
// ⚠️ FamilyControls 프라이버시상 실제 사용 분(分)·앱 이름을 코드로 못 읽으므로,
//    "정확히 몇 시간"이 아니라 "내가 정한 한도를 넘는 순간"만 알 수 있다(threshold).
//
// 배경/헤더/하단은 TaskPoolSheet과 같은 네온 룩(NeonBlurBackground)으로 통일하고,
// 한도 입력부의 베이지 키캡·LED만 리모컨 질감을 유지한다.
//
// 현재 파일은 화면만 담는다. 저장·DeviceActivity 등록·알림 발사는 아래 save()의 TODO.

// MARK: - 홈 리모컨 "감시" 버튼

/// 모드 줄 3번째 자리에 들어가는 감시 버튼.
/// 프리셋(아이보리)·점프(초록)와 한눈에 구분되도록 **인디고 키캡 + 눈 아이콘**으로 차별화한다.
struct WatchdogButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // 감시: 이모지 없이 텍스트만 (좌측 컬럼 컴팩트 키)
            // 높이·폰트를 같은 줄의 모드/점프 키(FuncButton·PresetButton)와 동일하게 맞춘다.
            Text("감시")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(
                        LinearGradient(colors: [Color(wd: 0x7b6ef0), Color(wd: 0x5638d6)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                )
                .overlay(alignment: .top) { keycapGloss(radius: 8) }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 감시 설정 시트 (TaskPool과 같은 네온 룩)

/// 감시 버튼을 누르면 뜨는 설정 시트.
/// - 감시할 앱(familyActivityPicker 재사용)
/// - 하루 한도(LED + 베이지 ▲▼, 30분 단위 — 세션 시간 맞추던 리모컨 메타포 유지)
struct WatchdogSheet: View {
    let onClose: () -> Void

    @State private var selection = FamilyActivitySelection()
    /// 하루 한도(분). 30분 단위, 30분~12시간.
    @State private var limitMinutes = 120
    @State private var showingPicker = false

    private let minMinutes = 30
    private let maxMinutes = 12 * 60
    private let step = 30

    private var appCount: Int {
        selection.applicationTokens.count
        + selection.categoryTokens.count
        + selection.webDomainTokens.count
    }
    /// 감시할 앱이 최소 1개는 있어야 저장(감시 시작) 가능.
    private var canSave: Bool { appCount > 0 }

    var body: some View {
        ZStack {
            NeonBlurBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        appSection
                        limitSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                }

                bottomBar
            }
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $selection)
    }

    // MARK: 헤더 (타이틀 + 닫기 — TaskPool/과업편집과 동일 패턴)

    private var header: some View {
        HStack {
            OutlinedText(text: "앱 사용시간 제한하기", size: 22, alignment: .leading)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    // MARK: 감시할 앱

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("감시할 앱")

            Button { showingPicker = true } label: {
                HStack(spacing: 8) {
                    Text(appCount == 0 ? "탭해서 고르기" : "\(appCount)개 · 다시 고르기")
                        .font(.myungjo(17))
                        .foregroundStyle(Color(wd: 0x222222))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color(wd: 0x6b6453))
                }
                .padding(.horizontal, 16)
                // 아래 −[LED]+ 줄과 폭을 맞춰 가운데로.
                .frame(maxWidth: 290, minHeight: 50)
                .keycap(top: Color(wd: 0xf4eedd), bottom: Color(wd: 0xd6cbac))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)

            if appCount > 0 {
                KaraokeSongList(selection: selection)
                    .frame(maxHeight: 150)
            }
        }
    }

    // MARK: 하루 한도 (LED + 베이지 ▲▼)

    private var limitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("하루 한도")

            // − [ LED ] + 를 한 덩어리로 가운데 모은다(숫자 좌우에 딱 붙게).
            HStack(spacing: 8) {
                analogStepper(systemImage: "minus", enabled: limitMinutes > minMinutes) {
                    limitMinutes = max(minMinutes, limitMinutes - step)
                }
                limitLED
                analogStepper(systemImage: "plus", enabled: limitMinutes < maxMinutes) {
                    limitMinutes = min(maxMinutes, limitMinutes + step)
                }
            }
            .frame(maxWidth: .infinity)

            // 핵심 설명 — 더 크고 또렷하게, 가운데로.
            Text("하루에 이 시간을 넘게 쓰면 알림으로 알려드려요")
                .font(.myungjo(15))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// LED 디스플레이 — 홈 화면 시간 표시와 같은 7세그먼트 룩(시:분).
    private var limitLED: some View {
        let h = limitMinutes / 60
        let m = limitMinutes % 60
        let lit = Color(wd: 0xff5a32)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            ledGroup(String(h), label: "HOUR", lit: lit)
            Text(":").font(.seg7(34)).foregroundStyle(lit).shadow(color: lit.opacity(0.8), radius: 8)
            ledGroup(String(format: "%02d", m), label: "MIN", lit: lit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 7).fill(
                RadialGradient(colors: [Color(wd: 0x14120b), Color(wd: 0x050503)],
                               center: .center, startRadius: 1, endRadius: 160)
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(wd: 0x2c281c), lineWidth: 2))
    }

    private func ledGroup(_ value: String, label: String, lit: Color) -> some View {
        VStack(spacing: 3) {
            ZStack {
                // 꺼진 세그먼트가 비치는 LED 느낌 — 뒤에 "88"을 흐리게 깐다.
                Text(String(repeating: "8", count: value.count))
                    .font(.seg7(34)).foregroundStyle(lit.opacity(0.10))
                Text(value)
                    .font(.seg7(34)).foregroundStyle(lit)
                    .shadow(color: lit.opacity(0.8), radius: 8)
            }
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(lit.opacity(0.55))
        }
    }

    /// 아날로그 키캡 ▲▼ 버튼 — 옛 리모컨처럼 상아색 베벨. 모서리는 "애매하게" 둥글게(radius 16).
    private func analogStepper(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Color(wd: 0x2a2a2a))
                .frame(width: 56, height: 56)
                .keycap(top: Color(wd: 0xf4eedd), bottom: Color(wd: 0xd6cbac), radius: 16)
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// 섹션 헤더 — 명조는 무겁고 커 보여서 고딕(시스템 산세리프)으로, 한 단계 작게.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.75))
    }

    // MARK: 하단 — 단일 저장 버튼(과업 편집과 동일 패턴, 닫기는 헤더의 X)

    private var bottomBar: some View {
        Button { save() } label: {
            Text("저장")
        }
        .buttonStyle(KaraokeButtonStyle(color: KColor.green, enabled: canSave))
        .disabled(!canSave)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    // MARK: 동작

    private func save() {
        guard canSave else { return }
        // TODO(피드백 후 배선): 감시 설정을 App Group에 저장 →
        //   DeviceActivityCenter에 daily 스케줄 + threshold(limitMinutes) 이벤트 등록.
        //   알림 권한이 거절 상태면 "설정에서 알림 켜기" 안내를 띄운다.
        //   넘는 순간 익스텐션 eventDidReachThreshold → 로컬 알림 → 탭 시 시작 확인 시트(딥링크).
        onClose()
    }
}

// MARK: - 리모컨 키캡 룩 (레퍼런스 노래방 리모컨 TJ미디어)

/// 베이스색 세로 그라데이션 + 상단 광택 + 위밝/아래어둠 베벨 테두리 + 바닥 그림자.
/// 실제 노래방 리모컨 키캡처럼 도톰하게 솟아 보이는 느낌을 준다.
private struct Keycap: ViewModifier {
    var top: Color
    var bottom: Color
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius).fill(
                    LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(alignment: .top) { keycapGloss(radius: radius) }
            // 위 모서리는 하얗게(빛 받는 면), 아래 모서리는 어둡게(눌린 면) — 베벨.
            .overlay(
                RoundedRectangle(cornerRadius: radius).stroke(
                    LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.3)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.3)
            )
            .shadow(color: .black.opacity(0.32), radius: 3, y: 2)
    }
}

private extension View {
    func keycap(top: Color, bottom: Color, radius: CGFloat = 12) -> some View {
        modifier(Keycap(top: top, bottom: bottom, radius: radius))
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
