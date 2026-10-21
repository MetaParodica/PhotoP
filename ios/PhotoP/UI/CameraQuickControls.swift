import SwiftUI

@MainActor
struct CameraQuickControls: View {
    @ObservedObject var model: CameraModel
    let tool: CameraTool
    let openStyles: () -> Void
    let openImports: () -> Void
    let openLongExposure: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch tool {
            case .iso, .shutter, .ev: exposure
            case .whiteBalance: whiteBalance
            case .focus: focus
            case .format: if model.snapshot.video.isVideoMode { video } else { format }
            case .monitor: if model.snapshot.video.isVideoMode { videoPreviewNotice } else { monitoring }
            case .guide: composition
            case .looks: if model.snapshot.video.isVideoMode { videoPreviewNotice } else { looks }
            case .longExposure: longExposure
            case .video: video
            }
        }.font(.subheadline).tint(.purple)
            .disabled(model.busy || model.snapshot.isApplyingSettings)
    }
    private func apply() { Task { await model.applySettings() } }
    private var exposureMode: Binding<Int> {
        Binding(get: { model.settings.exposure.manual ? 1 : model.settings.exposure.locked ? 2 : 0 }, set: { value in
            model.settings.exposure.manual = value == 1; model.settings.exposure.locked = value == 2; apply()
        })
    }
    @ViewBuilder private var exposure: some View {
        if let caps = model.snapshot.capabilities {
            Picker("노출 제어", selection: exposureMode) {
                Text("AUTO").tag(0)
                if caps.manualExposure { Text("수동").tag(1) }
                if caps.exposureLock { Text("AE 잠금").tag(2) }
            }.pickerStyle(.segmented)
            if model.settings.exposure.manual {
                if tool == .iso {
                    CameraValueSlider(title: "ISO", value: $model.settings.exposure.iso, range: caps.iso, logarithmic: true, onCommit: apply)
                } else {
                    CameraValueSlider(title: "노출 시간", value: $model.settings.exposure.shutterSeconds, range: caps.shutterSeconds, logarithmic: true,
                                      display: CameraControlScale.shutter, onCommit: apply)
                }
                Text("ISO와 셔터가 함께 고정됩니다. EV는 AUTO에서 조절합니다.").font(.caption).foregroundStyle(.secondary)
            } else if !model.settings.exposure.locked {
                CameraValueSlider(title: "EV", value: $model.settings.exposure.ev, range: caps.exposureBias,
                    display: { String(format: "%+.1f", $0) }, onCommit: apply)
            }
        } else { unavailable }
    }
    private var wbMode: Binding<Int> {
        Binding(get: { model.settings.whiteBalance.manual ? 1 : model.settings.whiteBalance.locked ? 2 : 0 }, set: { value in
            model.settings.whiteBalance.manual = value == 1; model.settings.whiteBalance.locked = value == 2; apply()
        })
    }
    @ViewBuilder private var whiteBalance: some View {
        if let caps = model.snapshot.capabilities {
            Picker("화이트밸런스 제어", selection: wbMode) {
                Text("자동").tag(0)
                if caps.manualWhiteBalance { Text("수동").tag(1) }
                if caps.whiteBalanceLock { Text("잠금").tag(2) }
            }.pickerStyle(.segmented)
            if model.settings.whiteBalance.manual {
                CameraValueSlider(title: "색온도", value: $model.settings.whiteBalance.kelvin, range: 2000...10000, display: { "\(Int($0)) K" }, onCommit: apply)
                CameraValueSlider(title: "Tint", value: $model.settings.whiteBalance.tint, range: -150...150, onCommit: apply)
            }
        } else { unavailable }
    }
    private var focusMode: Binding<Int> {
        Binding(get: { model.settings.focus.manual ? 1 : model.settings.focus.locked ? 2 : 0 }, set: { value in
            model.settings.focus.manual = value == 1; model.settings.focus.locked = value == 2; apply()
        })
    }
    @ViewBuilder private var focus: some View {
        if let caps = model.snapshot.capabilities {
            Picker("초점 제어", selection: focusMode) {
                Text("AF").tag(0)
                if caps.manualFocus { Text("수동").tag(1) }
                if caps.focusLock { Text("AF 잠금").tag(2) }
            }.pickerStyle(.segmented)
            if model.settings.focus.manual {
                CameraValueSlider(title: "렌즈 위치", value: $model.settings.focus.lensPosition, range: 0...1,
                                  display: { String(format: "%.2f", $0) }, onCommit: apply)
                Text("정규화된 렌즈 위치이며 거리(m)가 아닙니다.").font(.caption).foregroundStyle(.secondary)
            }
        } else { unavailable }
    }
    @ViewBuilder private var format: some View {
        if let caps = model.snapshot.capabilities {
            Picker("파일 포맷", selection: $model.photoFormat) {
                ForEach(caps.photoFormats) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(model.rawMode != .processed)
            Picker("촬영 데이터", selection: $model.rawMode) { ForEach(caps.rawModes) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented)
            Picker("사진 해상도 상한", selection: $model.photoResolution) {
                Text("현재 포맷 최대").tag(Optional<PhotoResolution>.none)
                ForEach(caps.photoResolutions) { Text($0.title).tag(Optional($0)) }
            }.disabled(model.rawMode != .processed || model.bracketEnabled)
            Toggle("노출 브래킷 · 원본 3장", isOn: $model.bracketEnabled).disabled(caps.maximumBracketCount < 3)
            if model.bracketEnabled {
                Picker("EV 간격", selection: $model.bracketStep) { Text("±0.5").tag(0.5); Text("±1").tag(1.0); Text("±2").tag(2.0) }.pickerStyle(.segmented)
            }
            if let reason = model.rawUnavailableReason ?? model.bracketUnavailableReason { Text(reason).font(.caption) }
        } else { unavailable }
    }
    private func startMonitoring() {
        Task { await model.enableMonitoring() }
    }
    private var monitoring: some View {
        VStack(spacing: 12) {
            Toggle("RGB 히스토그램", isOn: $model.monitoring.histogram)
            Toggle("Zebra", isOn: $model.monitoring.zebra)
            if model.monitoring.zebra {
                Slider(value: $model.monitoring.zebraThreshold, in: 0.5...1) { Text("Zebra 임계값") }
                Text("밝은 채널 \(Int(model.monitoring.zebraThreshold * 100))% 이상").font(.caption)
            }
            Toggle("포커스 피킹", isOn: $model.monitoring.peaking)
            if model.monitoring.peaking { Slider(value: $model.monitoring.peakingThreshold, in: 0.01...1) { Text("피킹 임계값") } }
            Text("SDR 프리뷰 분석입니다. RAW 센서 클리핑·초점 거리를 측정하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            if model.livePreview != nil { Button("LUT·분석 프리뷰 끄기") { model.disableLiveLUT() } }
        }.onChange(of: model.monitoring) { _, value in
            model.updateMonitoring()
            if value.enabled && model.livePreview == nil { startMonitoring() }
        }
    }
    private var composition: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("구도선"); Spacer(); Picker("구도선", selection: $model.guideGrid) { ForEach(GuideGrid.allCases) { Text($0.title).tag($0) } }.labelsHidden().accessibilityValue(model.guideGrid.title).accessibilityIdentifier("camera.guide.grid") }
            HStack { Text("장면"); Spacer(); Picker("장면", selection: $model.guideScene) { ForEach(GuideScene.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
            HStack { Text("인물 가이드"); Spacer(); Picker("인물 가이드", selection: $model.personGuide.framing) { ForEach(PersonFraming.allCases) { Text($0.title).tag($0) } }.labelsHidden().accessibilityIdentifier("camera.guide.person") }
            if model.personGuide.framing != .off {
                Picker("인물 위치", selection: $model.personGuide.position) { ForEach(PersonPosition.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("camera.guide.person.position")
                Stepper("인원 \(model.personGuide.people)명", value: $model.personGuide.people, in: 1...3)
                Text(model.personGuide.framing.tip).font(.caption).foregroundStyle(.secondary)
                Text("AI 제안을 켜면 실제 인물 어깨·얼굴 위치를 흰 실루엣과 비교해 이동 방향을 알려 줍니다.").font(.caption2).foregroundStyle(.secondary)
            }
            HStack { Text("포즈 골격"); Spacer(); Picker("포즈", selection: $model.poseTemplate) { ForEach(PoseTemplate.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
            HStack { Text("선명도"); Slider(value: $model.guideOpacity, in: 0.1...1) { Text("구도선 투명도") } }
            Toggle("온디바이스 AI 제안", isOn: $model.guideAIEnabled).disabled(model.snapshot.video.isVideoMode)
            Text("흰 점선 실루엣·노란 선은 목표 구도, 청록 선은 Vision 검출입니다. 이미지 서버 전송 없이 처리합니다.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of: model.guideGrid) { _, _ in model.showGrid = false }
            .onChange(of: model.guideScene) { _, _ in model.updateComposition() }
            // Body joints are analysed only for the portrait scene.
            .onChange(of: model.personGuide.framing) { _, framing in if framing != .off { model.guideScene = .portrait } }
            .onChange(of: model.guideAIEnabled) { _, enabled in model.updateComposition(); if enabled { startMonitoring() } }
    }
    private var looks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.liveLUTTitle ?? "원본 색상").font(.headline)
            HStack {
                Button("스타일 선택", action: openStyles).buttonStyle(.borderedProminent).disabled(model.livePreview != nil || model.snapshot.state != .running)
                Button("가져오기·프리셋", action: openImports)
            }
            if model.liveUsesLUT {
                HStack { Text("강도"); Slider(value: $model.liveIntensity, in: 0...1) { Text("룩 강도") }; Text("\(Int(model.liveIntensity * 100))%") }
                Toggle("원본과 비교", isOn: $model.liveCompareOriginal)
                DisclosureGroup("그레인·필름 마감") {
                    Slider(value: $model.liveGrain, in: 0...1) { Text("그레인") }
                    FilmFinishControls(settings: $model.liveFinish)
                }
            }
            if model.livePreview != nil { Button("프리뷰 해제 · 다른 룩 선택") { model.disableLiveLUT() } }
            Text("룩은 프리뷰에 적용합니다. 촬영 원본은 보존하며 사진 편집에서 완성본을 저장합니다. 프리뷰 사용 중 렌즈·터치 AF/AE·RAW는 제한됩니다.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of: model.liveIntensity) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveCompareOriginal) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveGrain) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveFinish) { _, _ in model.updateLiveIntensity() }
    }
    private var longExposure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("합성 방식", selection: $model.longConfiguration.blend) { ForEach(LongExposureConfiguration.Blend.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("총 합성 시간", selection: $model.longConfiguration.duration) {
                ForEach([1.0, 2, 4, 8, 15, 30, 60, 120, 300], id: \.self) { Text("\(Int($0))초").tag($0) }
            }
            Toggle("평행이동 정렬", isOn: $model.longConfiguration.align)
            Text("최대 1280px SDR 다중 프레임 합성입니다. 총 합성 시간은 센서 셔터 시간이 아닙니다.").font(.caption).foregroundStyle(.secondary)
            Button("촬영·진행·결과", action: openLongExposure).buttonStyle(.borderedProminent)
        }
    }
    private var videoPreviewNotice: some View {
        Text("영상은 원본 색상으로 녹화합니다. 영상용 LUT·노출 분석 프리뷰는 다음 구현 단위입니다.")
            .font(.callout).foregroundStyle(.secondary)
    }
    private func changeVideo(_ update: (inout VideoConfiguration) -> Void) {
        guard var configuration = model.snapshot.video.configuration else { return }
        update(&configuration)
        Task { await model.setVideoMode(true, configuration: configuration) }
    }
    @ViewBuilder private var video: some View {
        Text("SDR · 원본 색상 · \(VideoCapturePolicy.audioLabel(model.snapshot.video.configuration))").font(.headline)
        if let configuration = model.snapshot.video.configuration, let caps = model.snapshot.video.capabilities {
            Picker("영상 해상도", selection: Binding(get: { configuration.resolution }, set: { value in changeVideo { $0.resolution = value } })) {
                ForEach(caps.resolutions) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("camera.video.resolution")
            Picker("프레임레이트", selection: Binding(get: { configuration.framesPerSecond }, set: { value in changeVideo { $0.framesPerSecond = value } })) {
                ForEach(caps.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }.pickerStyle(.segmented)
            Picker("영상 코덱", selection: Binding(get: { configuration.codec }, set: { value in changeVideo { $0.codec = value } })) {
                ForEach(caps.codecs) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if caps.stabilizationModes.count > 1 {
                Picker("손떨림 보정", selection: Binding(get: { configuration.stabilization ?? .off }, set: { value in changeVideo { $0.stabilization = value } })) {
                    ForEach(caps.stabilizationModes) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("camera.video.stabilization")
            }
            Toggle("오디오 녹음", isOn: Binding(get: { configuration.audio }, set: { value in changeVideo { $0.audio = value } }))
                .disabled(!caps.audio && !configuration.audio).accessibilityIdentifier("camera.video.audio")
            if let limits = model.snapshot.capabilities?.shutterSeconds {
                let seconds = VideoCapturePolicy.suggestedShutter(fps: configuration.framesPerSecond, limits: limits)
                Button("180° 셔터 제안 · \(CameraControlScale.shutter(seconds))") {
                    model.settings.exposure.manual = true; model.settings.exposure.locked = false
                    model.settings.exposure.iso = model.snapshot.readout?.iso ?? model.settings.exposure.iso
                    model.settings.exposure.shutterSeconds = seconds
                    apply()
                }.disabled(model.snapshot.capabilities?.manualExposure != true)
            }
        } else {
            Text("카메라 연결 후 지원 해상도·FPS·코덱이 표시됩니다.").foregroundStyle(.secondary)
        }
        Text("최대 10분·2GiB. 전면 영상은 미러링 없이 저장합니다. 해상도별 FPS·코덱·손떨림 보정은 다시 조회하며 모드·구성 변경 시 노출·초점·WB를 AUTO로 초기화합니다. 시네마틱 보정은 화각을 줄이고 지연이 늘어납니다.")
            .font(.caption).foregroundStyle(.secondary)
    }
    private var unavailable: some View {
        Label("카메라를 연결하면 이 렌즈가 지원하는 제어 범위가 표시됩니다.", systemImage: "camera.badge.ellipsis")
            .font(.callout).foregroundStyle(.secondary)
    }
}
