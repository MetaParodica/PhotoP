import ARKit
import SwiftUI

private struct DepthCameraSurface: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) { }
    static func dismantleUIView(_ view: ARSCNView, coordinator: ()) { view.session.pause() }
}

@MainActor
struct DepthCaptureView: View {
    @StateObject private var model = DepthCaptureModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if model.supported {
                    DepthCameraSurface(session: model.session).overlay {
                        Image(systemName: "plus").foregroundStyle(.green).allowsHitTesting(false)
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                    if let distance = model.centerDistance { Text(String(format: "중앙 깊이 %.2f m", distance)).monospacedDigit() }
                    Text("LiDAR RGB + 미터 단위 깊이 + 신뢰도 + 카메라 보정 정보를 함께 보관합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("깊이 촬영") { Task { await model.capture() } }.buttonStyle(.borderedProminent)
                            .disabled(!model.ready || model.busy).accessibilityIdentifier("camera.depth.capture")
                        if !model.ready { Button("다시 연결") { Task { await model.restart() } }.buttonStyle(.bordered) }
                    }
                    if let latest = model.latest {
                        HStack {
                            ShareLink("깊이 패키지 공유", item: latest.package)
                            ShareLink("RGB 사진 공유", item: latest.photo)
                        }.buttonStyle(.bordered)
                    }
                    if model.busy { ProgressView("깊이 데이터 저장 중") }
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.orange) }
                } else {
                    ContentUnavailableView("LiDAR 지원 기기가 필요합니다", systemImage: "camera.metering.center.weighted",
                                           description: Text("이 기기는 ARKit sceneDepth 촬영을 지원하지 않습니다. LiDAR 탑재 후면 카메라에서 사용하세요."))
                }
            }.padding().navigationTitle("LiDAR 깊이 촬영").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { model.stop(); dismiss() }.disabled(model.busy) } }
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.start() } } else { model.stop() } }
                .onDisappear { model.stop() }
        }.preferredColorScheme(.dark)
    }
}
