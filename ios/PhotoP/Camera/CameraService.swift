@preconcurrency import AVFoundation
import Foundation

// All session/device mutations and delegate state live on queue. Only the preview
// layer binds to the immutable session reference on the main thread.
final class CameraService: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.photop.capture", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
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
    private var continuation: CheckedContinuation<Data, Error>?
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
            if state == .running { startReadouts() }
            publish(session.isRunning ? nil : "카메라를 시작하지 못했습니다.")
        } catch { state = .stopped; publish(error.localizedDescription) }
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
            manualWhiteBalance: d.isWhiteBalanceModeSupported(.locked) && d.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        )
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
        guard settings.exposure.manual || d.isExposureModeSupported(.continuousAutoExposure)
        else { throw CameraError.invalidSettings }
        try d.lockForConfiguration()
        defer { d.unlockForConfiguration() }

        var steps: Set<CameraControlApplication.Step> = [.exposure]
        if settings.focus.manual { steps.insert(.focus) }
        if settings.whiteBalance.manual { steps.insert(.whiteBalance) }
        let id = try controls.begin(steps: steps)
        settingsCompletion = completion

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.controls.id == id else { return }
            self.wantsRunning = false
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

        if settings.exposure.manual {
            d.setExposureModeCustom(
                duration: CMTime(seconds: settings.exposure.shutterSeconds, preferredTimescale: 1_000_000_000),
                iso: Float(settings.exposure.iso),
                completionHandler: controlCompletion(.exposure, id: id))
        } else {
            d.exposureMode = .continuousAutoExposure
            d.setExposureTargetBias(Float(settings.exposure.ev),
                                    completionHandler: controlCompletion(.exposure, id: id))
        }
        if settings.focus.manual {
            d.setFocusModeLocked(lensPosition: Float(settings.focus.lensPosition),
                                completionHandler: controlCompletion(.focus, id: id))
        } else if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
        if settings.whiteBalance.manual {
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
                guard self.controls.acknowledge(step, id: id) else { return }
                if let readout = self.currentReadout() { self.finishApplying(.success(readout)) }
                else { self.finishApplying(.failure(CameraError.configuration)) }
            }
        }
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
                             isAdjusting: d.isAdjustingExposure || d.isAdjustingFocus || d.isAdjustingWhiteBalance)
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

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                guard state == .running, session.isRunning, !session.isInterrupted else {
                    completion.resume(throwing: CameraError.interrupted); return
                }
                guard continuation == nil, !controls.isPending else { completion.resume(throwing: CameraError.busy); return }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
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
            else if let photoData { finishPhoto(.success(photoData)) }
            else { finishPhoto(.failure(CameraError.missingPhoto)) }
        }
    }

    private func finishPhoto(_ result: Result<Data, Error>) {
        let pending = continuation
        continuation = nil; photoID = nil; photoData = nil
        pending?.resume(with: result)
    }

    private func handleNotification(_ name: Notification.Name, reset: Bool) {
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
