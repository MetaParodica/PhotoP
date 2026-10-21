@preconcurrency import AVFoundation
import Foundation
import CoreVideo

// All session/device mutations and delegate state live on queue. Only the preview
// layer binds to the immutable session reference on the main thread.
final class CameraService: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.photop.capture", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoConfiguration: VideoConfiguration?
    private var videoCapabilities: VideoCapabilities?
    private var recording = VideoRecordingLifecycle()
    private var movieCompletion: CheckedContinuation<URL, Error>?
    private var movieTimeout: DispatchWorkItem?
    private var photoWideColor = true
    private var photoAutoHDR = true
    private let longOutput = AVCaptureVideoDataOutput()
    private var longExposure: LongExposureCapture?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var livePreview: LiveLUTPreview?
    private var removeLivePreviewRequested = false
    private var devices: [AVCaptureDevice] = []
    private var input: AVCaptureDeviceInput?
    private var observers: [NSObjectProtocol] = []
    private var wantsRunning = false
    private var state: CaptureSessionState = .stopped
    private var snapshotRevision: UInt64 = 0
    private var readoutTimer: DispatchSourceTimer?
    private var controls = CameraControlApplication()
    private var settingsCompletion: CheckedContinuation<CameraReadout, Error>?
    private var settingsTimeout: DispatchWorkItem?
    private var photoTimeout: DispatchWorkItem?
    private var photoError: Error?
    private var photoID: Int64?
    private var photoDelivery: PhotoSeriesDelivery?
    private var continuation: CheckedContinuation<CapturedSeries, Error>?
    private let onSnapshot: @Sendable (CameraSnapshot) -> Void

    init(onSnapshot: @escaping @Sendable (CameraSnapshot) -> Void) {
        self.onSnapshot = onSnapshot
        super.init()
        let center = NotificationCenter.default
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification] {
            observers.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                let name = note.name
                let reset = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
                self?.queue.async { [weak self] in self?.handleNotification(name, reset: reset) }
            })
        }
    }

    deinit {
        readoutTimer?.cancel()
        settingsTimeout?.cancel()
        photoTimeout?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func setActive(_ active: Bool) {
        #if targetEnvironment(simulator)
        if active {
            queue.async { [self] in publish(CameraError.unavailable.localizedDescription) }
            return
        }
        #endif
        queue.async { [self] in
            wantsRunning = active
            if !active {
                stopVideoOnQueue()
                longExposure?.cancel()
                state = .stopped
                livePreview?.setRunning(false)
                stopReadouts()
                finishApplying(.failure(CameraError.interrupted))
                finishPhoto(.failure(CameraError.interrupted))
                if session.isRunning { session.stopRunning() }
                state = .stopped
                publish()
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: startAuthorized()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    self.queue.async {
                        guard self.wantsRunning else { return }
                        if granted { self.startAuthorized() }
                        else { self.publish(CameraError.permission.localizedDescription) }
                    }
                }
            default: publish(CameraError.permission.localizedDescription)
            }
        }
    }

    private func startAuthorized() {
        do {
            if input == nil { try configure() }
            guard wantsRunning, !session.isInterrupted else {
                state = .interrupted; publish(); return
            }
            if !session.isRunning { session.startRunning() }
            state = session.isRunning ? .running : .stopped
            livePreview?.setRunning(state == .running)
            if state == .running { startReadouts() }
            publish(session.isRunning ? nil : "카메라를 시작하지 못했습니다.")
        } catch { livePreview?.setRunning(false); state = .stopped; publish(error.localizedDescription) }
    }

    private func configure() throws {
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .unspecified
        ).devices
        guard let device = devices.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }) ?? devices.first
        else { throw CameraError.unavailable }
        let candidate = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        guard session.canAddInput(candidate) else { throw CameraError.configuration }
        session.addInput(candidate)
        guard session.canAddOutput(output) else {
            session.removeInput(candidate)
            throw CameraError.configuration
        }
        session.addOutput(output)
        input = candidate
        output.maxPhotoQualityPrioritization = .quality
        configureRAW()
        configureDimensions()
    }

    func selectLens(_ id: String) {
        queue.async { [self] in
            guard videoConfiguration == nil, continuation == nil, longExposure == nil, !controls.isPending else { publish(CameraError.busy.localizedDescription); return }
            guard livePreview == nil else { publish("LUT를 끈 뒤 렌즈를 전환해 주세요."); return }
            guard let old = input, let device = devices.first(where: { $0.uniqueID == id }),
                  device.uniqueID != old.device.uniqueID else { return }
            do {
                let candidate = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                session.removeInput(old)
                if session.canAddInput(candidate) {
                    session.addInput(candidate)
                    input = candidate
                } else {
                    session.addInput(old)
                    session.commitConfiguration()
                    throw CameraError.configuration
                }
                configureRAW()
                configureDimensions()
                session.commitConfiguration()
                // Switching a lens explicitly returns controls to AUTO.
                try applyOnQueue(CameraSettings())
                publish()
            } catch { publish(error.localizedDescription) }
        }
    }

    private func configureDimensions() {
        guard let device = input?.device,
              let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
                  Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
              }) else { return }
        if output.maxPhotoDimensions.width != largest.width || output.maxPhotoDimensions.height != largest.height {
            output.maxPhotoDimensions = largest
        }
    }

    private func configureRAW() {
        // Configure before startRunning and again after changing the input.
        output.isAppleProRAWEnabled = output.isAppleProRAWSupported
    }

    private func rawPixelFormats() -> [OSType] {
        guard output.availableRawPhotoFileTypes.contains(.dng) else { return [] }
        return output.supportedRawPhotoPixelFormatTypes(for: .dng)
    }
    private func rawModes() -> [RawCaptureMode] {
        RawCapturePolicy.modes(formats: rawPixelFormats()) { format in
            if AVCapturePhotoOutput.isAppleProRAWPixelFormat(format) { return .appleProRAW }
            if AVCapturePhotoOutput.isBayerRAWPixelFormat(format) { return .bayer }
            return nil
        }
    }

    private func capabilities() -> CameraCapabilities? {
        guard let d = input?.device else { return nil }
        let format = d.activeFormat
        return CameraCapabilities(
            lensID: d.uniqueID, iso: Double(format.minISO)...Double(format.maxISO),
            shutterSeconds: (videoConfiguration.flatMap { try? VideoCapturePolicy.shutterLimit(sensor: format.minExposureDuration.seconds...format.maxExposureDuration.seconds, fps: $0.framesPerSecond) }) ?? (format.minExposureDuration.seconds...format.maxExposureDuration.seconds),
            exposureBias: Double(d.minExposureTargetBias)...Double(d.maxExposureTargetBias),
            manualExposure: d.isExposureModeSupported(.custom),
            manualFocus: d.isLockingFocusWithCustomLensPositionSupported,
            manualWhiteBalance: d.isWhiteBalanceModeSupported(.locked) && d.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            exposureLock: d.isExposureModeSupported(.locked),
            focusLock: d.isFocusModeSupported(.locked),
            whiteBalanceLock: d.isWhiteBalanceModeSupported(.locked),
            photoFormats: PhotoFileFormat.supported(by: output.availablePhotoCodecTypes), rawModes: rawModes(), maximumBracketCount: output.maxBracketedCapturePhotoCount,
            photoResolutions: PhotoResolutionPolicy.options(supported: format.supportedMaxPhotoDimensions.map { .init(width: $0.width, height: $0.height) },
                ceiling: .init(width: output.maxPhotoDimensions.width, height: output.maxPhotoDimensions.height))
        )
    }

    func setLivePreview(_ preview: LiveLUTPreview) async throws {
        try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard state == .running, session.isRunning, !session.isInterrupted, input != nil else { throw CameraError.interrupted }
                    guard videoConfiguration == nil, continuation == nil, longExposure == nil, !controls.isPending, livePreview == nil else { throw CameraError.busy }
                    session.beginConfiguration()
                    do {
                        guard session.canAddOutput(videoOutput) else { throw CameraError.configuration }
                        session.addOutput(videoOutput)
                        guard let format = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                            .first(where: { videoOutput.availableVideoPixelFormatTypes.contains($0) }),
                              let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90)
                        else { throw CameraError.configuration }
                        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
                        videoOutput.alwaysDiscardsLateVideoFrames = true
                        videoOutput.automaticallyConfiguresOutputBufferDimensions = true
                        connection.videoRotationAngle = 90
                        if input?.device.position == .front && !connection.isVideoMirroringSupported { throw CameraError.configuration }
                        if connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = input?.device.position == .front
                        }
                        livePreview = preview
                        removeLivePreviewRequested = false
                        videoOutput.setSampleBufferDelegate(preview, queue: preview.frameQueue)
                        session.commitConfiguration()
                        configureDimensions()
                        preview.setRunning(true)
                        publish()
                        completion.resume()
                    } catch {
                        if session.outputs.contains(videoOutput) { session.removeOutput(videoOutput) }
                        session.commitConfiguration()
                        throw error
                    }
                } catch { completion.resume(throwing: error) }
            }
        }
    }

    func removeLivePreview() {
        queue.async { [self] in
            livePreview?.setRunning(false)
            removeLivePreviewRequested = true
            removeLivePreviewIfRequested()
        }
    }

    private func removeLivePreviewIfRequested() {
        guard removeLivePreviewRequested, continuation == nil, !controls.isPending else { return }
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        if session.outputs.contains(videoOutput) {
            session.beginConfiguration()
            session.removeOutput(videoOutput)
            session.commitConfiguration()
            configureDimensions()
        }
        livePreview = nil
        removeLivePreviewRequested = false
        publish()
    }

    func apply(_ settings: CameraSettings) async throws -> CameraReadout {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                do {
                    guard state == .running, session.isRunning, !session.isInterrupted else {
                        throw CameraError.interrupted
                    }
                    guard !recording.phase.isActive, continuation == nil, longExposure == nil, !controls.isPending else { throw CameraError.busy }
                    try applyOnQueue(settings, completion: completion)
                } catch { completion.resume(throwing: error) }
            }
        }
    }

    private func applyOnQueue(_ settings: CameraSettings,
                              completion: CheckedContinuation<CameraReadout, Error>? = nil) throws {
        guard let d = input?.device, let caps = capabilities() else { throw CameraError.unavailable }
        try CameraSettingsValidator.validate(settings, for: caps)
        guard settings.exposure.manual || settings.exposure.locked || d.isExposureModeSupported(.continuousAutoExposure)
        else { throw CameraError.invalidSettings }
        try d.lockForConfiguration()
        defer { d.unlockForConfiguration() }

        var steps: Set<CameraControlApplication.Step> = [.exposure]
        if settings.focus.manual || settings.focus.locked { steps.insert(.focus) }
        if settings.whiteBalance.manual || settings.whiteBalance.locked { steps.insert(.whiteBalance) }
        let id = try controls.begin(steps: steps)
        settingsCompletion = completion

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.controls.id == id else { return }
            self.wantsRunning = false
            self.livePreview?.setRunning(false)
            self.state = .stopped
            self.stopReadouts()
            if self.session.isRunning { self.session.stopRunning() }
            self.finishApplying(.failure(CameraError.settingsTimedOut))
        }
        settingsTimeout = timeout
        // The completion may require a full exposure interval.
        let currentSeconds = d.exposureDuration.seconds
        let longestExposure = max(settings.exposure.shutterSeconds,
                                  currentSeconds.isFinite ? max(0, currentSeconds) : 0)
        queue.asyncAfter(deadline: .now() + max(5, longestExposure + 3), execute: timeout)

        if settings.exposure.locked {
            // This mode setter is synchronous; it has no device completion callback.
            d.exposureMode = .locked
            queue.async { [self] in acknowledgeControl(.exposure, id: id) }
        } else if settings.exposure.manual {
            d.setExposureModeCustom(
                duration: CMTime(seconds: settings.exposure.shutterSeconds, preferredTimescale: 1_000_000_000),
                iso: Float(settings.exposure.iso),
                completionHandler: controlCompletion(.exposure, id: id))
        } else {
            d.exposureMode = .continuousAutoExposure
            d.setExposureTargetBias(Float(settings.exposure.ev),
                                    completionHandler: controlCompletion(.exposure, id: id))
        }
        if settings.focus.manual || settings.focus.locked {
            d.setFocusModeLocked(lensPosition: settings.focus.locked ? AVCaptureDevice.currentLensPosition : Float(settings.focus.lensPosition),
                                completionHandler: controlCompletion(.focus, id: id))
        } else if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
        if settings.whiteBalance.locked {
            d.setWhiteBalanceModeLocked(with: AVCaptureDevice.currentWhiteBalanceGains,
                                       completionHandler: controlCompletion(.whiteBalance, id: id))
        } else if settings.whiteBalance.manual {
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: Float(settings.whiteBalance.kelvin), tint: Float(settings.whiteBalance.tint))
            var gains = d.deviceWhiteBalanceGains(for: values)
            gains.redGain = min(max(gains.redGain, 1), d.maxWhiteBalanceGain)
            gains.greenGain = min(max(gains.greenGain, 1), d.maxWhiteBalanceGain)
            gains.blueGain = min(max(gains.blueGain, 1), d.maxWhiteBalanceGain)
            d.setWhiteBalanceModeLocked(with: gains,
                                       completionHandler: controlCompletion(.whiteBalance, id: id))
        } else if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            d.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        publish()
    }

    private func controlCompletion(_ step: CameraControlApplication.Step, id: UUID) -> (CMTime) -> Void {
        { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.acknowledgeControl(step, id: id)
            }
        }
    }

    private func acknowledgeControl(_ step: CameraControlApplication.Step, id: UUID) {
        guard controls.acknowledge(step, id: id) else { return }
        if let readout = currentReadout() { finishApplying(.success(readout)) }
        else { finishApplying(.failure(CameraError.configuration)) }
    }

    private func finishApplying(_ result: Result<CameraReadout, Error>) {
        let wasPending = controls.isPending || settingsCompletion != nil || settingsTimeout != nil
        controls.cancel()
        settingsTimeout?.cancel()
        settingsTimeout = nil
        let completion = settingsCompletion
        settingsCompletion = nil
        guard wasPending else { return }
        switch result {
        case .success: publish()
        case .failure(let error): publish(error.localizedDescription)
        }
        completion?.resume(with: result)
        removeLivePreviewIfRequested()
    }

    private func currentReadout() -> CameraReadout? {
        guard state == .running, let d = input?.device else { return nil }
        let iso = Double(d.iso)
        let seconds = d.exposureDuration.seconds
        let bias = Double(d.exposureTargetBias)
        let position = Double(d.lensPosition)
        guard [iso, seconds, bias, position].allSatisfy(\.isFinite), iso > 0, seconds > 0 else { return nil }
        let gains = d.deviceWhiteBalanceGains
        var kelvin: Double?
        var tint: Double?
        if [gains.redGain, gains.greenGain, gains.blueGain].allSatisfy({
            $0.isFinite && $0 >= 1 && $0 <= d.maxWhiteBalanceGain
        }) {
            let values = d.temperatureAndTintValues(for: gains)
            if values.temperature.isFinite, values.tint.isFinite {
                kelvin = Double(values.temperature)
                tint = Double(values.tint)
            }
        }
        return CameraReadout(iso: iso, shutterSeconds: seconds, exposureBias: bias,
                             lensPosition: position, kelvin: kelvin, tint: tint,
                             isAdjusting: d.isAdjustingExposure || d.isAdjustingFocus || d.isAdjustingWhiteBalance,
                             exposureLocked: d.exposureMode == .locked || d.exposureMode == .custom,
                             focusLocked: d.focusMode == .locked, whiteBalanceLocked: d.whiteBalanceMode == .locked)
    }

    private func startReadouts() {
        guard readoutTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self, self.wantsRunning, self.state == .running,
                  self.session.isRunning, !self.session.isInterrupted else { return }
            self.publish()
        }
        readoutTimer = timer
        timer.resume()
    }

    private func stopReadouts() {
        readoutTimer?.cancel()
        readoutTimer = nil
    }

    func focusAndMeter(at point: CameraMeteringPoint, lensID: String) async throws -> PointMeteringActions {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                do {
                    guard state == .running, session.isRunning, !session.isInterrupted,
                          let d = input?.device, d.uniqueID == lensID else { throw CameraError.interrupted }
                    guard !recording.phase.isActive, continuation == nil, longExposure == nil, !controls.isPending else { throw CameraError.busy }
                    let actions = PointMeteringPolicy.actions(
                        focusSupported: d.isFocusPointOfInterestSupported && d.isFocusModeSupported(.continuousAutoFocus),
                        exposureSupported: d.isExposurePointOfInterestSupported && d.isExposureModeSupported(.continuousAutoExposure),
                        focusLocked: d.focusMode == .locked,
                        exposureLocked: d.exposureMode == .locked || d.exposureMode == .custom)
                    guard !actions.isEmpty else { throw CameraError.invalidSettings }
                    try d.lockForConfiguration()
                    if actions.focus {
                        d.focusPointOfInterest = point.cgPoint
                        d.focusMode = .continuousAutoFocus
                    }
                    if actions.exposure {
                        d.exposurePointOfInterest = point.cgPoint
                        d.exposureMode = .continuousAutoExposure
                    }
                    d.unlockForConfiguration()
                    publish()
                    // A point request is accepted; AF/AE may still be adjusting.
                    completion.resume(returning: actions)
                } catch { completion.resume(throwing: error) }
            }
        }
    }

    func captureLongExposure(_ configuration: LongExposureConfiguration,
                             progress: @escaping @Sendable (LongExposureProgress) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                var archive: LongExposureArchive?
                do {
                    guard state == .running, session.isRunning, !session.isInterrupted else { throw CameraError.interrupted }
                    guard videoConfiguration == nil, continuation == nil, longExposure == nil, !controls.isPending, livePreview == nil,
                          !session.outputs.contains(videoOutput) else { throw CameraError.busy }
                    try configuration.validate()
                    let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    let free = try FileManager.default.attributesOfFileSystem(forPath: documents.path)[.systemFreeSize] as? NSNumber
                    guard free?.int64Value ?? 0 > 32 * 1024 * 1024 else { throw ImageEditingError.invalid("합성 시작에 최소 32MiB의 저장 공간이 필요합니다.") }
                    let nextArchive = try LongExposureArchive(root: documents.appendingPathComponent("LongExposures"))
                    archive = nextArchive
                    let job = try LongExposureCapture(configuration: configuration, archive: nextArchive, onProgress: progress) { [weak self] result in
                        guard let self else { completion.resume(throwing: CameraError.interrupted); return }
                        self.queue.async {
                            self.longOutput.setSampleBufferDelegate(nil, queue: nil)
                            if self.session.outputs.contains(self.longOutput) {
                                self.session.beginConfiguration(); self.session.removeOutput(self.longOutput); self.session.commitConfiguration()
                                self.configureDimensions()
                            }
                            self.longExposure = nil
                            self.publish()
                            completion.resume(with: result)
                        }
                    }
                    session.beginConfiguration()
                    do {
                        guard session.canAddOutput(longOutput) else { throw CameraError.configuration }
                        session.addOutput(longOutput)
                        guard let format = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                            .first(where: { longOutput.availableVideoPixelFormatTypes.contains($0) }),
                              let connection = longOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) else { throw CameraError.configuration }
                        longOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
                        longOutput.alwaysDiscardsLateVideoFrames = true
                        connection.videoRotationAngle = 90
                        if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
                        longExposure = job
                        longOutput.setSampleBufferDelegate(job, queue: job.frameQueue)
                        session.commitConfiguration(); configureDimensions(); job.start(); publish()
                    } catch {
                        if session.outputs.contains(longOutput) { session.removeOutput(longOutput) }
                        session.commitConfiguration(); longExposure = nil; throw error
                    }
                } catch { archive?.cancel(); completion.resume(throwing: error) }
            }
        }
    }
    func cancelLongExposure() { queue.async { [self] in longExposure?.cancel() } }

    func capturePhoto(format: PhotoFileFormat, rawMode: RawCaptureMode = .processed) async throws -> CapturedPhoto {
        let series = try await captureSeries(format: format, rawMode: rawMode)
        guard series.photos.count == 1, let photo = series.photos.first else { throw CameraError.missingPhoto }
        return photo
    }

    func captureSeries(format: PhotoFileFormat, rawMode: RawCaptureMode = .processed, bracketStep: Double? = nil, resolution: PhotoResolution? = nil) async throws -> CapturedSeries {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                guard state == .running, session.isRunning, !session.isInterrupted else {
                    completion.resume(throwing: CameraError.interrupted); return
                }
                guard videoConfiguration == nil, continuation == nil, longExposure == nil, !controls.isPending else { completion.resume(throwing: CameraError.busy); return }
                let settings: AVCapturePhotoSettings
                let expectedFormat: PhotoFileFormat
                var biases: [Double]?
                guard RawCapturePolicy.unavailableReason(mode: rawMode, available: rawModes(), live: livePreview != nil,
                                                        exposureMode: input?.device.exposureMode) == nil else {
                    completion.resume(throwing: CameraError.invalidSettings); return
                }
                if rawMode == .processed {
                    guard let codec = format.codec, output.availablePhotoCodecTypes.contains(codec) else {
                        completion.resume(throwing: CameraError.invalidSettings); return
                    }
                    if let bracketStep, let device = input?.device {
                        do {
                            let plan = try ExposureBracketPlan.make(center: Double(device.exposureTargetBias), step: bracketStep,
                                limits: Double(device.minExposureTargetBias)...Double(device.maxExposureTargetBias),
                                maximumCount: output.maxBracketedCapturePhotoCount, rawMode: rawMode, live: livePreview != nil,
                                exposureMode: device.exposureMode)
                            let variations = plan.biases.map { AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: Float($0)) }
                            let bracket = AVCapturePhotoBracketSettings(rawPixelFormatType: 0, processedFormat: [AVVideoCodecKey: codec], bracketedSettings: variations)
                            bracket.isLensStabilizationEnabled = output.isLensStabilizationDuringBracketedCaptureSupported
                            settings = bracket
                            biases = plan.biases
                        } catch { completion.resume(throwing: error); return }
                    } else { settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec]) }
                    expectedFormat = format
                } else {
                    guard bracketStep == nil else { completion.resume(throwing: CameraError.invalidSettings); return }
                    guard let raw = rawPixelFormats().first(where: {
                        rawMode == .bayer ? AVCapturePhotoOutput.isBayerRAWPixelFormat($0) : AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
                    }) else { completion.resume(throwing: CameraError.invalidSettings); return }
                    // RAW only: no processed callback can replace the requested DNG.
                    settings = AVCapturePhotoSettings(rawPixelFormatType: raw, rawFileType: .dng, processedFormat: nil, processedFileType: nil)
                    expectedFormat = .dng
                }
                do {
                    let chosen = try PhotoResolutionPolicy.resolve(resolution,
                        supported: input?.device.activeFormat.supportedMaxPhotoDimensions.map { .init(width: $0.width, height: $0.height) } ?? [],
                        ceiling: .init(width: output.maxPhotoDimensions.width, height: output.maxPhotoDimensions.height),
                        raw: rawMode, bracket: bracketStep != nil)
                    settings.maxPhotoDimensions = CMVideoDimensions(width: chosen.width, height: chosen.height)
                } catch { completion.resume(throwing: error); return }
                settings.photoQualityPrioritization = biases != nil ? .speed : (rawMode == .appleProRAW ? .quality : PhotoCapturePolicy.quality(for: input?.device.exposureMode))
                // Initial release is portrait-only. Front preview is mirrored; saved photo is not.
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                }
                continuation = completion
                photoDelivery = PhotoSeriesDelivery(format: expectedFormat, biases: biases)
                photoID = settings.uniqueID
                photoError = nil
                let id = settings.uniqueID
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self, self.photoID == id else { return }
                    self.wantsRunning = false
                    self.state = .stopped
                    self.livePreview?.setRunning(false)
                    self.stopReadouts()
                    if self.session.isRunning { self.session.stopRunning() }
                    self.finishPhoto(.failure(CameraError.captureTimedOut))
                    self.publish(CameraError.captureTimedOut.localizedDescription)
                }
                photoTimeout = timeout
                let exposure = input?.device.exposureDuration.seconds ?? 0
                queue.asyncAfter(deadline: .now() + max(30, (exposure.isFinite ? max(0, exposure) : 0) * Double(biases?.count ?? 1) + 15), execute: timeout)
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let data = photo.fileDataRepresentation()
        let isRaw = photo.isRawPhoto
        let bracketBias = (photo.bracketSettings as? AVCaptureAutoExposureBracketedStillImageSettings).map { Double($0.exposureTargetBias) }
        let sequence = photo.bracketSettings == nil ? 1 : photo.sequenceCount
        queue.async { [self] in
            guard photoID == id else { return }
            if let error { photoError = error }
            else {
                do {
                    guard photoDelivery != nil else { throw CameraError.missingPhoto }
                    try photoDelivery?.receive(data, isRaw: isRaw, sequence: sequence, bracketBias: bracketBias)
                } catch { photoError = error }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let id = resolvedSettings.uniqueID
        let expectedCount = Int(resolvedSettings.expectedPhotoCount)
        queue.async { [self] in
            guard photoID == id else { return }
            if let error = error ?? photoError { finishPhoto(.failure(error)) }
            else {
                do {
                    guard let photoDelivery, photoDelivery.expectedCount == expectedCount else { throw CameraError.missingPhoto }
                    finishPhoto(.success(try photoDelivery.result()))
                } catch { finishPhoto(.failure(error)) }
            }
        }
    }

    private func finishPhoto(_ result: Result<CapturedSeries, Error>) {
        let pending = continuation
        photoTimeout?.cancel(); photoTimeout = nil
        continuation = nil; photoID = nil; photoDelivery = nil; photoError = nil
        pending?.resume(with: result)
        removeLivePreviewIfRequested()
    }

    private func handleNotification(_ name: Notification.Name, reset: Bool) {
        stopVideoOnQueue()
        longExposure?.cancel()
        livePreview?.setRunning(false)
        if name == AVCaptureSession.wasInterruptedNotification {
            state = .interrupted
            stopReadouts()
            finishApplying(.failure(CameraError.interrupted))
            finishPhoto(.failure(CameraError.interrupted))
            publish(CameraError.interrupted.localizedDescription)
        } else if name == AVCaptureSession.interruptionEndedNotification || reset {
            if reset {
                finishApplying(.failure(CameraError.interrupted))
                finishPhoto(.failure(CameraError.interrupted))
            }
            if wantsRunning { startAuthorized() }
        } else {
            state = .stopped
            stopReadouts()
            finishApplying(.failure(CameraError.interrupted))
            finishPhoto(.failure(CameraError.interrupted))
            publish("카메라 오류가 발생했습니다. 다시 시작을 눌러 주세요.")
        }
    }

    private func publish(_ message: String? = nil) {
        snapshotRevision += 1
        onSnapshot(CameraSnapshot(lenses: devices.map { d in
            CameraLens(id: d.uniqueID, name: d.localizedName, isFront: d.position == .front)
        }, selectedLens: input?.device.uniqueID, capabilities: capabilities(), state: state, message: message,
           revision: snapshotRevision, readout: currentReadout(), isApplyingSettings: controls.isPending,
           video: VideoSnapshot(configuration: videoConfiguration, capabilities: videoCapabilities, phase: recording.phase,
               elapsedSeconds: movieOutput.recordedDuration.seconds.isFinite ? max(0, movieOutput.recordedDuration.seconds) : 0)))
    }
}

private extension VideoResolution {
    var preset: AVCaptureSession.Preset {
        switch self { case .hd720: return .hd1280x720; case .hd1080: return .hd1920x1080; case .uhd4K: return .hd4K3840x2160 }
    }
}

private extension VideoCodec {
    var avCodec: AVVideoCodecType { self == .h264 ? .h264 : .hevc }
}

extension CameraService {
    func setVideoMode(_ enabled: Bool, configuration requested: VideoConfiguration? = nil) async throws {
        try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard state == .running, session.isRunning, !session.isInterrupted else { throw CameraError.interrupted }
                    guard !recording.phase.isActive, !movieOutput.isRecording, continuation == nil,
                          longExposure == nil, !controls.isPending, livePreview == nil else { throw CameraError.busy }
                    if enabled {
                        let previous = videoConfiguration
                        if previous == nil {
                            photoWideColor = session.automaticallyConfiguresCaptureDeviceForWideColor
                            photoAutoHDR = input?.device.automaticallyAdjustsVideoHDREnabled ?? true
                        }
                        do { try configureVideo(requested, entering: previous == nil) }
                        catch {
                            // Restore a known mode before exposing any controls after a failed change.
                            do {
                                if let previous { try configureVideo(previous, entering: false) }
                                else { try restorePhotoMode() }
                            } catch { state = .stopped; session.stopRunning(); stopReadouts() }
                            throw error
                        }
                    } else { try restorePhotoMode() }
                    publish("촬영 모드를 변경했습니다. 노출·초점·WB는 AUTO로 초기화됩니다.")
                    completion.resume()
                } catch { publish(error.localizedDescription); completion.resume(throwing: error) }
            }
        }
    }

    private func configureVideo(_ requested: VideoConfiguration?, entering: Bool) throws {
        guard let device = input?.device else { throw CameraError.unavailable }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        if session.outputs.contains(output) { session.removeOutput(output) }
        if !session.outputs.contains(movieOutput) {
            guard session.canAddOutput(movieOutput) else { throw CameraError.configuration }
            session.addOutput(movieOutput)
        }
        let resolutions = VideoResolution.allCases.filter { session.canSetSessionPreset($0.preset) }
        guard let resolution = requested?.resolution ?? (resolutions.contains(.hd1080) ? .hd1080 : resolutions.first),
              resolutions.contains(resolution) else { throw CameraError.invalidSettings }
        session.sessionPreset = resolution.preset
        let frameRates = VideoCapturePolicy.frameRates(in: device.activeFormat.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate })
        let codecs = VideoCodec.allCases.filter { movieOutput.availableVideoCodecTypes.contains($0.avCodec) }
        let changedPreset = entering || videoConfiguration?.resolution != resolution
        let fps = requested?.framesPerSecond ?? 30
        let codec = requested?.codec ?? .h264
        guard let actualFPS = frameRates.contains(fps) ? fps : (changedPreset ? (frameRates.contains(30) ? 30 : frameRates.first) : nil),
              let actualCodec = codecs.contains(codec) ? codec : (changedPreset ? codecs.first : nil),
              device.activeFormat.supportedColorSpaces.contains(.sRGB),
              let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90)
        else { throw CameraError.invalidSettings }
        try device.lockForConfiguration()
        // Select an SDR space BEFORE disabling HDR. HLG ignores isVideoHDREnabled=false.
        device.activeColorSpace = .sRGB
        device.automaticallyAdjustsVideoHDREnabled = false
        if device.activeFormat.isVideoHDRSupported { device.isVideoHDREnabled = false }
        resetAutomaticControls(device)
        let duration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
        connection.videoRotationAngle = 90
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false // Saved front video is unmirrored, like an original photo.
        }
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        movieOutput.setOutputSettings([AVVideoCodecKey: actualCodec.avCodec], for: connection)
        movieOutput.maxRecordedDuration = CMTime(seconds: 600, preferredTimescale: 600)
        movieOutput.maxRecordedFileSize = 2 * 1024 * 1024 * 1024
        movieOutput.minFreeDiskSpaceLimit = 32 * 1024 * 1024
        videoConfiguration = VideoConfiguration(resolution: resolution, framesPerSecond: actualFPS, codec: actualCodec)
        videoCapabilities = VideoCapabilities(resolutions: resolutions, frameRates: frameRates, codecs: codecs)
    }

    private func restorePhotoMode() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.outputs.contains(movieOutput) { session.removeOutput(movieOutput) }
        session.automaticallyConfiguresCaptureDeviceForWideColor = photoWideColor
        guard session.canSetSessionPreset(.photo) else { throw CameraError.configuration }
        session.sessionPreset = .photo
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { throw CameraError.configuration }
            session.addOutput(output)
        }
        if let device = input?.device {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = .invalid
            device.activeVideoMaxFrameDuration = .invalid
            device.automaticallyAdjustsVideoHDREnabled = photoAutoHDR
            resetAutomaticControls(device)
            device.unlockForConfiguration()
        }
        videoConfiguration = nil; videoCapabilities = nil
        configureRAW(); configureDimensions()
    }

    private func resetAutomaticControls(_ device: AVCaptureDevice) {
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
    }

    func recordVideo() async throws -> URL {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                do {
                    guard state == .running, session.isRunning, !session.isInterrupted else { throw CameraError.interrupted }
                    guard let configuration = videoConfiguration, let capabilities = videoCapabilities else { throw CameraError.invalidSettings }
                    guard movieCompletion == nil, !movieOutput.isRecording, !controls.isPending,
                          continuation == nil, longExposure == nil, livePreview == nil else { throw CameraError.busy }
                    try VideoCapturePolicy.validate(configuration, capabilities: capabilities)
                    guard input?.device.activeColorSpace == .sRGB, input?.device.isVideoHDREnabled == false,
                          let connection = movieOutput.connection(with: .video), connection.isActive, connection.isEnabled else { throw CameraError.configuration }
                    guard ProcessInfo.processInfo.thermalState != .critical else { throw CameraError.interrupted }
                    let url = try VideoStore.newRecordingURL()
                    try recording.begin(url)
                    movieCompletion = completion
                    scheduleMovieTimeout(url, seconds: 15)
                    movieOutput.startRecording(to: url, recordingDelegate: self)
                    publish()
                } catch { completion.resume(throwing: error) }
            }
        }
    }

    func stopVideo() { queue.async { [self] in stopVideoOnQueue(); publish() } }

    private func stopVideoOnQueue() {
        guard let url = recording.url else { return }
        if recording.requestStop() { movieOutput.stopRecording() }
        scheduleMovieTimeout(url, seconds: 15)
    }

    private func scheduleMovieTimeout(_ url: URL, seconds: Double) {
        movieTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.recording.url == url else { return }
            self.movieOutput.stopRecording()
            self.wantsRunning = false; self.state = .stopped; self.stopReadouts()
            if self.session.isRunning { self.session.stopRunning() }
            // A stuck delegate must not keep the UI/task alive forever. Pending bytes stay on disk.
            self.completeMovie(url, result: .failure(CameraError.videoTimedOut))
        }
        movieTimeout = timeout
        queue.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { [self] in
            guard recording.url == fileURL else { return }
            movieTimeout?.cancel(); movieTimeout = nil
            if recording.didStart(fileURL) { movieOutput.stopRecording(); scheduleMovieTimeout(fileURL, seconds: 15) }
            publish()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let saved = VideoCapturePolicy.finishedSuccessfully(hasError: error != nil, successfulFinishFlag: (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        let result: Result<URL, Error> = saved ? .success(outputFileURL) : .failure(error ?? CameraError.missingPhoto)
        queue.async { [self] in completeMovie(outputFileURL, result: result) }
    }

    private func completeMovie(_ url: URL, result: Result<URL, Error>) {
        guard recording.finish(url) else { return }
        movieTimeout?.cancel(); movieTimeout = nil
        let pending = movieCompletion; movieCompletion = nil
        publish()
        pending?.resume(with: result)
    }
}

enum PhotoCapturePolicy {
    // Apple's custom-exposure contract requires speed to honor ISO/duration.
    // This does not change JPEG compression or the requested photo dimensions.
    static func quality(for exposureMode: AVCaptureDevice.ExposureMode?) -> AVCapturePhotoOutput.QualityPrioritization {
        switch exposureMode {
        case .custom?, .locked?: return .speed
        default: return .quality
        }
    }
}
