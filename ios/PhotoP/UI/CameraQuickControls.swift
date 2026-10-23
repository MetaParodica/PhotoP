import SwiftUI

@MainActor
struct CameraQuickControls: View {
    @ObservedObject var model: CameraModel
    let tool: CameraTool
    let openStyles: () -> Void
    let openImports: () -> Void
    let openLongExposure: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch tool {
            case .iso, .shutter, .ev: exposure
            case .whiteBalance: whiteBalance
            case .focus: focus
            case .aperture: depth
            case .format: if model.snapshot.video.isVideoMode { video } else { format }
            case .monitor: monitoring
            case .guide: composition
            case .looks: if model.snapshot.video.isVideoMode { videoPreviewNotice } else { looks }
            case .longExposure: longExposure
            case .video: video
            }
        }.font(.subheadline).tint(.purple)
            .disabled(model.busy)
    }
    private func apply() { model.requestSettings() }
    private var exposureMode: Binding<Int> {
        Binding(get: { model.settings.exposure.manual ? 1 : model.settings.exposure.locked ? 2 : 0 }, set: { value in
            if value == 1, !model.settings.exposure.manual, let readout = model.snapshot.readout, let caps = model.snapshot.capabilities {
                model.settings.exposure.iso = min(max(readout.iso, caps.iso.lowerBound), caps.iso.upperBound)
                model.settings.exposure.shutterSeconds = min(max(readout.shutterSeconds, caps.shutterSeconds.lowerBound), caps.shutterSeconds.upperBound)
            }
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
            if tool == .ev {
                if !model.settings.exposure.manual && !model.settings.exposure.locked {
                    CameraValueSlider(title: "EV", value: $model.settings.exposure.ev, range: caps.exposureBias,
                        display: { String(format: "%+.1f", $0) }, onCommit: apply)
                } else { Text("EV는 AUTO 노출에서 조절합니다. 수동 모드에서는 ISO·셔터를 조절하세요.").font(.caption) }
            } else if model.settings.exposure.manual {
                if tool == .iso {
                    CameraValueSlider(title: "ISO", value: $model.settings.exposure.iso, range: caps.iso, logarithmic: true, onCommit: apply)
                } else {
                    CameraValueSlider(title: "노출 시간", value: $model.settings.exposure.shutterSeconds, range: caps.shutterSeconds, logarithmic: true,
                                      display: CameraControlScale.shutter, onCommit: apply)
                }
                Text("ISO와 셔터가 함께 고정됩니다. EV는 AUTO에서 조절합니다.").font(.caption).foregroundStyle(.secondary)
            } else if !model.settings.exposure.locked {
                Button("현재 노출에서 수동 조절") { exposureMode.wrappedValue = 1 }.disabled(!caps.manualExposure)
            }
        } else { unavailable }
    }
    private var wbMode: Binding<Int> {
        Binding(get: { model.settings.whiteBalance.manual ? 1 : model.settings.whiteBalance.locked ? 2 : 0 }, set: { value in
            if value == 1, !model.settings.whiteBalance.manual, let readout = model.snapshot.readout {
                model.settings.whiteBalance.kelvin = min(max(readout.kelvin ?? 5000, 2000), 10000)
                model.settings.whiteBalance.tint = min(max(readout.tint ?? 0, -150), 150)
            }
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
            if value == 1, !model.settings.focus.manual { model.settings.focus.lensPosition = model.snapshot.readout?.lensPosition ?? 0.5 }
            if value == 1 { model.focusAssistEnabled = true }
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
                Toggle("초록색 초점 보조", isOn: $model.focusAssistEnabled)
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
            CameraChoice(title: "사진 해상도 상한", selection: $model.photoResolution,
                         values: [Optional<PhotoResolution>.none] + caps.photoResolutions.map { Optional($0) },
                         identifier: "camera.resolution", key: { $0?.id ?? "maximum" }, label: { $0?.title ?? "현재 포맷 최대" })
                .disabled(model.rawMode != .processed || model.bracketEnabled)
            Toggle("노출 브래킷 · 원본 3장", isOn: $model.bracketEnabled).disabled(caps.maximumBracketCount < 3)
            if model.bracketEnabled {
                Picker("EV 간격", selection: $model.bracketStep) { Text("±0.5").tag(0.5); Text("±1").tag(1.0); Text("±2").tag(2.0) }.pickerStyle(.segmented)
            }
            if let reason = model.rawUnavailableReason ?? model.bracketUnavailableReason { Text(reason).font(.caption) }
            Text(caps.shutterSoundSuppression ? "셔터음 억제 적용" : "이 기기·iOS에서는 앱의 셔터음 억제가 허용되지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
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
            Text("초록색 피킹은 선명한 윤곽을 표시합니다. 실제 초점 거리(m) 측정값은 아닙니다.").font(.caption).foregroundStyle(.secondary)
            if model.livePreview != nil { Button("분석 프리뷰 끄기") { model.disableLiveLUT() } }
            else if model.monitoring.enabled { Button("프리뷰 다시 연결") { startMonitoring() }.disabled(model.snapshot.state != .running) }
        }
    }
    private var composition: some View {
        VStack(alignment: .leading, spacing: 12) {
            CameraChoice(title: "구도선", selection: $model.guideGrid, values: GuideGrid.allCases, identifier: "camera.guide.grid", key: { $0.id }, label: { $0.title })
            CameraChoice(title: "장면", selection: $model.guideScene, values: GuideScene.allCases, identifier: "camera.guide.scene", key: { $0.id }, label: { $0.title })
            CameraChoice(title: "인물 가이드", selection: $model.personGuide.framing, values: PersonFraming.allCases, identifier: "camera.guide.person", key: { $0.id }, label: { $0.title })
            if model.personGuide.framing != .off {
                Picker("인물 위치", selection: $model.personGuide.position) { ForEach(PersonPosition.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("camera.guide.person.position")
                Stepper("인원 \(model.personGuide.people)명", value: $model.personGuide.people, in: 1...3)
                Text(model.personGuide.framing.tip).font(.caption).foregroundStyle(.secondary)
                Text("AI 제안을 켜면 실제 인물 어깨·얼굴 위치를 흰 실루엣과 비교해 이동 방향을 알려 줍니다.").font(.caption2).foregroundStyle(.secondary)
            }
            CameraChoice(title: "포즈 골격", selection: $model.poseTemplate, values: PoseTemplate.allCases, identifier: "camera.guide.pose", key: { $0.id }, label: { $0.title })
            HStack { Text("선명도"); Slider(value: $model.guideOpacity, in: 0.1...1) { Text("구도선 투명도") } }
            AICompositionControls(model: model)
            Text("흰 선·점선은 목표 구도·실루엣, 노란 골격은 목표 포즈, 청록 선은 Vision 검출입니다. 이미지 서버 전송 없이 처리합니다.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of: model.guideGrid) { _, grid in model.showGrid = false; if grid != .off { model.compositionPresetID = nil } }
            .onChange(of: model.guideScene) { _, _ in model.updateComposition() }
            // Body joints are analysed only for the portrait scene. One guide family is drawn at a time.
            .onChange(of: model.personGuide.framing) { _, framing in if framing != .off { model.guideScene = .portrait; model.compositionPresetID = nil } }
            .onChange(of: model.guideAIEnabled) { _, enabled in model.updateComposition(); if enabled { startMonitoring() } }
    }
    private var looks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.liveLUTTitle ?? "원본 색상").font(.headline)
            Text(model.captureLookNotice).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("스타일 선택", action: openStyles).buttonStyle(.borderedProminent)
                Button("가져오기·프리셋", action: openImports)
            }
            if model.liveUsesLUT {
                HStack { Text("강도"); Slider(value: $model.liveIntensity, in: 0...1) { Text("룩 강도") }; Text("\(Int(model.liveIntensity * 100))%") }
                DisclosureGroup("그레인·필름 마감") {
                    Slider(value: $model.liveGrain, in: 0...1) { Text("그레인") }
                    FilmFinishControls(settings: $model.liveFinish)
                }
            }
            if model.liveUsesLUT { Button("룩 적용 해제") { Task { await model.selectOriginalLook() } } }
            Text("미리보기 없이 선택한 룩을 촬영 결과에만 적용합니다. 원본은 별도로 보존합니다. RAW·영상에는 적용하지 않습니다.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of: model.liveIntensity) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveCompareOriginal) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveGrain) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveFinish) { _, _ in model.updateLiveIntensity() }
    }
    private var longExposure: some View {
        VStack(alignment: .leading, spacing: 12) {
            LongExposureDurationControl(duration: $model.longConfiguration.duration)
            Picker("합성 방식", selection: $model.longConfiguration.blend) { ForEach(LongExposureConfiguration.Blend.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Toggle("평행이동 정렬", isOn: $model.longConfiguration.align)
            Text("최대 1280px SDR 다중 프레임 합성입니다. 총 합성 시간은 센서 셔터 시간이 아닙니다.").font(.caption).foregroundStyle(.secondary)
            Button("촬영·진행·결과", action: openLongExposure).buttonStyle(.borderedProminent)
        }
    }
    private var depth: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("심도 촬영", isOn: Binding(get: { model.depthEnabled }, set: { value in Task { await model.setDepthEnabled(value) } }))
                .disabled(!model.depthEnabled && (model.snapshot.capabilities?.depthAvailable != true || !model.depthModeAllowed))
                .accessibilityIdentifier("camera.depth.toggle")
            CameraValueSlider(title: "심도 f값", value: $model.depthAperture, range: 1.4...16,
                              display: { String(format: "f/%.1f", $0) }, onCommit: {})
                .disabled(!model.depthEnabled).accessibilityIdentifier("camera.depth.aperture")
            Text("작은 f값은 배경 흐림을 강하게, 큰 f값은 약하게 적용합니다. 실제 렌즈 조리개가 아닌 깊이 데이터 기반 소프트웨어 효과이며 촬영 결과에 적용합니다.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.depthModeAllowed { Text("심도는 PRO의 일반 단일 사진에서 사용합니다. RAW·브래킷·장노출·영상과 동시 사용하지 않습니다.").font(.caption) }
            else if model.snapshot.capabilities?.depthAvailable != true { Text("현재 카메라에서 사진 깊이 데이터를 제공하지 않습니다. 지원되는 듀얼/TrueDepth 카메라가 필요합니다.").font(.caption) }
            Text("심도 카메라로 전환하면 렌즈의 노출·초점 지원 범위가 바뀔 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var videoPreviewNotice: some View {
        Text("영상은 원본 색상으로 녹화합니다. 노출 분석은 장치가 녹화·분석 스트림 동시 사용을 허용하는 구성에서 제공합니다. 영상용 컬러 LUT 프리뷰·LUT 굽기는 아직 제공하지 않습니다.")
            .font(.callout).foregroundStyle(.secondary)
    }
    private func changeVideo(_ update: (inout VideoConfiguration) -> Void) {
        model.changeVideo(update)
    }
    @ViewBuilder private var video: some View {
        Text("SDR · 원본 색상 · \(VideoCapturePolicy.audioLabel(model.snapshot.video.configuration))").font(.headline)
        if let configuration = model.requestedVideo ?? model.snapshot.video.configuration, let caps = model.snapshot.video.capabilities {
          Group {
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
          }.disabled(model.recordingRequested)
            if model.recordingRequested { Text("녹화 중에는 해상도·FPS·코덱·오디오·보정 구성을 유지합니다. ISO·셔터·초점·WB·분석은 계속 조절할 수 있습니다.").font(.caption) }
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
