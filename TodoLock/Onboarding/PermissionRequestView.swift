import SwiftUI

/// 앱 첫 런칭 시 보이는 권한 요청 화면. 잠금/점프 화면과 같은 노래방 CRT 룩으로 통일한다.
struct PermissionRequestView: View {
    @EnvironmentObject var authState: AuthorizationState

    var body: some View {
        ZStack {
            KaraokeBackground()

            VStack(spacing: 22) {
                Spacer()

                // 곡 들어가기 전 노래방 인트로 톤의 마이크.
                Image(systemName: "music.mic")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(KColor.cyan)
                    .shadow(color: KColor.cyan.opacity(0.7), radius: 16)

                OutlinedText(text: "투두락에 권한이 필요해요", size: 28,
                             fill: KColor.yellow, strokeWidth: 5, alignment: .center)
                    .padding(.horizontal, 24)

                Text("이어서 뜨는 화면에서 권한을 허용해주세요.\n앱을 정상적으로 사용하려면 필수예요.")
                    .font(.myungjo(16))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer()

                Button {
                    Task { await authState.request() }
                } label: {
                    Text("권한 허용 ▶")
                }
                .buttonStyle(KaraokeButtonStyle(color: KColor.green))
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
            }
        }
    }
}
