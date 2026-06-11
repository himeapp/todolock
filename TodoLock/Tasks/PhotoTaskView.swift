import SwiftUI
import Vision
import UIKit
import AVFoundation

/// 온디바이스 사진 검수. VNClassifyImageRequest로 분류 → 카테고리 키워드와 매칭.
enum PhotoVerifier {
    static func verify(_ image: UIImage, category: VerifyCategory) async -> Bool {
        guard let cg = image.cgImage else { return false }
        return await withCheckedContinuation { cont in
            let request = VNClassifyImageRequest { req, _ in
                let obs = (req.results as? [VNClassificationObservation]) ?? []
                // 신뢰도 있는 후보만(노이즈 컷).
                let candidates = obs.filter { $0.confidence > 0.10 }
                let keywords = category.matchKeywords
                if keywords.isEmpty {
                    // '아무 사진' — 인식 가능한 내용이 있으면 통과(블랙/노이즈 컷).
                    cont.resume(returning: !candidates.isEmpty)
                } else {
                    let matched = candidates.contains { o in
                        let id = o.identifier.lowercased()
                        return keywords.contains { id.contains($0) }
                    }
                    cont.resume(returning: matched)
                }
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}

/// 사진찍기 과업 수행 카드. 촬영 → 온디바이스 검수 → 통과/재촬영.
/// 옛 캠코더 뷰파인더 룩: 코너 브래킷 · REC 표시 · 검수 스캔라인.
struct PhotoTaskView: View {
    let category: VerifyCategory
    let onComplete: () -> Void

    enum Phase: Equatable { case idle, verifying, passed, retry }
    @State private var phase: Phase = .idle
    @State private var showCamera = false
    @State private var captured: UIImage?
    @StateObject private var camera = CameraModel()

    var body: some View {
        VStack(spacing: 14) {
            viewfinder
            statusLine
            captureButton
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18), lineWidth: 1))
        )
        // 화면에 들어오면 카메라 세션을 미리 데워(pre-warm) 둔다 → 촬영 버튼 즉시 반응.
        .onAppear { camera.prewarm() }
        .onDisappear { camera.stop() }
        .fullScreenCover(isPresented: $showCamera) {
            if camera.canUseCamera {
                CameraCaptureView(model: camera) { image in
                    captured = image
                    runVerify(image)
                }
            } else {
                // 카메라 없음(시뮬레이터)·권한 거부 시 사진 보관함 폴백.
                CameraPicker { image in
                    captured = image
                    runVerify(image)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - 뷰파인더 (풀폭 4:3 카메라 화면)

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.45))

            if let captured {
                Image(uiImage: captured)
                    .resizable().scaledToFill()
            } else {
                idleContent
            }

            // 코너 프레이밍 브래킷 (상태색)
            CameraCorners(inset: 12, length: 30)
                .stroke(stateColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: stateColor.opacity(0.7), radius: 7)

            // 좌상단 REC 표시 (캠코더 무드)
            VStack {
                HStack { recTag; Spacer() }
                Spacer()
            }
            .padding(14)

            if phase == .verifying { verifyingOverlay }
            if phase == .passed { passedOverlay }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(stateColor.opacity(0.45), lineWidth: 1.5))
        .shadow(color: stateColor.opacity(0.35), radius: 14)
    }

    // 촬영 전 안내 — 펄스 글로우 카메라 + 안내 칩
    private var idleContent: some View {
        VStack(spacing: 12) {
            Spacer()
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let pulse = sin(t * 2) * 0.5 + 0.5
                ZStack {
                    Circle()
                        .fill(KColor.cyan.opacity(0.12 + 0.10 * pulse))
                        .frame(width: 92, height: 92)
                        .blur(radius: 6)
                        .scaleEffect(0.9 + 0.18 * pulse)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(KColor.cyan)
                        .shadow(color: KColor.cyan.opacity(0.5 + 0.4 * pulse), radius: 8 + 8 * pulse)
                }
            }
            Spacer()
            Text(category.hint)
                .font(.myungjoLight(13))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(Capsule().stroke(KColor.cyan.opacity(0.4), lineWidth: 1))
                .padding(.bottom, 14)
        }
    }

    private var recTag: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let on = sin(t * 3) > -0.3
            HStack(spacing: 6) {
                Circle()
                    .fill(KColor.pink)
                    .frame(width: 8, height: 8)
                    .shadow(color: KColor.pink.opacity(0.9), radius: 5)
                    .opacity(on ? 1 : 0.25)
                Text("REC").font(.led(11)).foregroundStyle(.white)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.5)))
        }
    }

    // 검수 중 — 어둡게 + 위아래로 쓸고 가는 스캔라인
    private var verifyingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let p = sin(t * 2.2 - .pi / 2) * 0.5 + 0.5
                    let y = 16 + p * max(0, geo.size.height - 32)
                    LinearGradient(
                        colors: [.clear, KColor.cyan, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 2)
                    .shadow(color: KColor.cyan.opacity(0.9), radius: 8)
                    .position(x: geo.size.width / 2, y: y)
                }
            }
            VStack(spacing: 10) {
                ProgressView().tint(KColor.cyan)
                Text("온디바이스 AI 검수 중…").font(.myungjoLight(12)).foregroundStyle(.white)
            }
        }
    }

    // 통과 — 초록 체크 글로우
    private var passedOverlay: some View {
        ZStack {
            KColor.green.opacity(0.18)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(KColor.green)
                .shadow(color: KColor.green.opacity(0.8), radius: 16)
        }
    }

    private var captureButton: some View {
        Button { showCamera = true } label: {
            Label(captureTitle, systemImage: phase == .passed ? "checkmark" : "camera.fill")
        }
        .buttonStyle(KaraokeButtonStyle(
            color: phase == .passed ? KColor.green : KColor.cyan,
            enabled: phase != .verifying
        ))
        .disabled(phase == .verifying || phase == .passed)
    }

    private var captureTitle: String {
        switch phase {
        case .passed: return "인증 완료 ✓"
        case .retry: return "다시 촬영 ▶"
        default: return "사진 촬영 ▶"
        }
    }

    private var stateColor: Color {
        switch phase {
        case .passed: return KColor.green
        case .retry: return KColor.pink
        default: return KColor.cyan
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch phase {
        case .idle, .verifying:
            EmptyView()
        case .passed:
            OutlinedText(text: "인증 완료! ✓", size: 20, fill: KColor.green)
        case .retry:
            Text("과업과 맞지 않아요. 다시 찍어주세요.")
                .font(.myungjoLight(14)).foregroundStyle(KColor.pink)
        }
    }

    private func runVerify(_ image: UIImage) {
        phase = .verifying
        Task {
            let ok = await PhotoVerifier.verify(image, category: category)
            await MainActor.run {
                if ok {
                    phase = .passed
                    onComplete()
                } else {
                    phase = .retry
                }
            }
        }
    }
}

/// 카메라 뷰파인더 네 모서리의 ㄱ자 프레이밍 브래킷.
struct CameraCorners: Shape {
    var inset: CGFloat = 12
    var length: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let L = min(length, min(r.width, r.height) / 2)
        var p = Path()
        // 좌상
        p.move(to: CGPoint(x: r.minX, y: r.minY + L))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + L, y: r.minY))
        // 우상
        p.move(to: CGPoint(x: r.maxX - L, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + L))
        // 우하
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - L))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - L, y: r.maxY))
        // 좌하
        p.move(to: CGPoint(x: r.minX + L, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - L))
        return p
    }
}

/// 카메라(없으면 사진 보관함) 촬영용 UIImagePickerController 래퍼.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 미리 데워두는 커스텀 카메라 (실기기 촬영 진입 즉시화)

/// AVCaptureSession을 화면 진입 시 미리 구성·구동해 둔다. UIImagePickerController는
/// 탭한 순간에야 카메라를 콜드 스타트해 실기기에서 1~3초씩 걸리는데, 이걸 없앤다.
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "todolock.camera.session")
    private var configured = false
    private var onCapture: ((UIImage) -> Void)?

    /// 카메라 하드웨어 존재 여부(시뮬레이터는 false).
    var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    /// 커스텀 카메라를 쓸 수 있는가(하드웨어 + 권한 허용).
    var canUseCamera: Bool {
        hasCamera && AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// 화면 진입 시 호출 — 권한 확인 후 세션을 미리 구동.
    func prewarm() {
        guard hasCamera else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.start() }
            }
        default:
            break
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            guard self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = !session.inputs.isEmpty
    }

    func capture(_ completion: @escaping (UIImage) -> Void) {
        onCapture = completion
        queue.async { [weak self] in
            guard let self else { return }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = (error == nil)
            ? photo.fileDataRepresentation().flatMap(UIImage.init(data:))
            : nil
        DispatchQueue.main.async { [weak self] in
            if let image { self?.onCapture?(image) }
            self?.onCapture = nil
        }
    }
}

/// AVCaptureVideoPreviewLayer를 띄우는 실시간 프리뷰.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// 풀스크린 커스텀 카메라 UI — 프리뷰 + 프레이밍 코너 + 셔터.
struct CameraCaptureView: View {
    @ObservedObject var model: CameraModel
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var capturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: model.session).ignoresSafeArea()

            CameraCorners(inset: 28, length: 42)
                .stroke(KColor.cyan.opacity(0.9),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: KColor.cyan.opacity(0.6), radius: 8)
                .padding(34)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Button {
                    guard !capturing else { return }
                    capturing = true
                    model.capture { image in
                        onImage(image)
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 5).frame(width: 76, height: 76)
                        Circle().fill(.white).frame(width: 62, height: 62)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .opacity(capturing ? 0.5 : 1)
                }
                .disabled(capturing)
                .padding(.bottom, 42)
            }
        }
        .onAppear { model.start() }
    }
}
