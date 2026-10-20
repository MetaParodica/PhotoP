@preconcurrency import AVFoundation
import Foundation
import CoreVideo

// All session/device mutations and delegate state live on queue. Only the preview
// layer binds to the immutable session reference on the main thread.
final class CameraService: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.photop.capture", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
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
    private var photoID: Int64?
    private var photoData: Data?
    private var photoFormat: PhotoFileFormat?
    private var continuation: CheckedContinuation<CapturedPhoto, Error>?
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
        configureDimensions()
    }

    func selectLens(_ id: String) {
        queue.async { [self] in
            guard continuation == nil, !controls.isPending else { publish(CameraError.busy.localizedDescription); return }
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
        output.maxPhotoDimensions = largest
    }

    private func capabilities() -> CameraCapabilities? {
        guard let d = input?.device else { return nil }
        let format = d.activeFormat
        return CameraCapabilities(
            lensID: d.uniqueID, iso: Double(format.minISO)...Double(format.maxISO),
            shutterSeconds: format.minExposureDuration.seconds...format.maxExposureDuration.seconds,
            exposureBias: Double(d.minExposureTargetBias)...Double(d.maxExposureTargetBias),
            manualExposure: d.isExposureModeSupported(.custom),
            manualFocus: d.isLockingFocusWithCustomLensPositionSupported,
            manualWhiteBalance: d.isWhiteBalanceModeSupported(.locked) && d.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            exposureLock: d.isExposureModeSupported(.locked),
            focusLock: d.isFocusModeSupported(.locked),
            whiteBalanceLock: d.isWhiteBalanceModeSupported(.locked),
            photoFormats: PhotoFileFormat.supported(by: output.availablePhotoCodecTypes)
        )
    }

    func setLivePreview(_ preview: LiveLUTPreview) async throws {
        try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard state == .running, session.isRunning, !session.isInterrupted, input != nil else { throw CameraError.interrupted }
                    guard continuation == nil, !controls.isPending, livePreview == nil else { throw CameraError.busy }
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
                    guard continuation == nil, !controls.isPending else { throw CameraError.busy }
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
                    guard continuation == nil, !controls.isPending else { throw CameraError.busy }
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

    func capturePhoto(format: PhotoFileFormat) async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                guard state == .running, session.isRunning, !session.isInterrupted else {
                    completion.resume(throwing: CameraError.interrupted); return
                }
                guard continuation == nil, !controls.isPending else { completion.resume(throwing: CameraError.busy); return }
                guard output.availablePhotoCodecTypes.contains(format.codec) else {
                    completion.resume(throwing: CameraError.invalidSettings); return
                }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: format.codec])
                settings.maxPhotoDimensions = output.maxPhotoDimensions
                settings.photoQualityPrioritization = PhotoCapturePolicy.quality(for: input?.device.exposureMode)
                // Initial release is portrait-only. Front preview is mirrored; saved photo is not.
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                }
                continuation = completion
                photoFormat = format
                photoID = settings.uniqueID
                photoData = nil
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let data = photo.fileDataRepresentation()
        queue.async { [self] in
            guard photoID == id else { return }
            if let error { finishPhoto(.failure(error)) }
            else { photoData = data }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let id = resolvedSettings.uniqueID
        queue.async { [self] in
            guard photoID == id else { return }
            if let error { finishPhoto(.failure(error)) }
            else if let photoData, let photoFormat {
                do { finishPhoto(.success(try CapturedPhoto(data: photoData, expectedFormat: photoFormat))) }
                catch { finishPhoto(.failure(error)) }
            }
            else { finishPhoto(.failure(CameraError.missingPhoto)) }
        }
    }

    private func finishPhoto(_ result: Result<CapturedPhoto, Error>) {
        let pending = continuation
        continuation = nil; photoID = nil; photoData = nil; photoFormat = nil
        pending?.resume(with: result)
        removeLivePreviewIfRequested()
    }

    private func handleNotification(_ name: Notification.Name, reset: Bool) {
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
           revision: snapshotRevision, readout: currentReadout(), isApplyingSettings: controls.isPending))
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
