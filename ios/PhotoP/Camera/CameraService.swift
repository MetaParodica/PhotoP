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

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

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
            guard continuation == nil else { publish(CameraError.busy.localizedDescription); return }
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
            manualWhiteBalance: d.isWhiteBalanceModeSupported(.locked)
        )
    }

    func apply(_ settings: CameraSettings) async throws {
        try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard continuation == nil, state == .running else { throw CameraError.busy }
                    try applyOnQueue(settings)
                    completion.resume()
                } catch { completion.resume(throwing: error) }
            }
        }
    }

    private func applyOnQueue(_ settings: CameraSettings) throws {
        guard let d = input?.device, let caps = capabilities() else { throw CameraError.unavailable }
        try CameraSettingsValidator.validate(settings, for: caps)
        try d.lockForConfiguration()
        defer { d.unlockForConfiguration() }
        if settings.exposure.manual {
            d.setExposureModeCustom(duration: CMTime(seconds: settings.exposure.shutterSeconds, preferredTimescale: 1_000_000_000),
                                    iso: Float(settings.exposure.iso), completionHandler: nil)
        } else if d.isExposureModeSupported(.continuousAutoExposure) {
            d.exposureMode = .continuousAutoExposure
            d.setExposureTargetBias(Float(settings.exposure.ev), completionHandler: nil)
        }
        if settings.focus.manual {
            d.setFocusModeLocked(lensPosition: Float(settings.focus.lensPosition), completionHandler: nil)
        } else if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
        if settings.whiteBalance.manual {
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: Float(settings.whiteBalance.kelvin), tint: Float(settings.whiteBalance.tint))
            var gains = d.deviceWhiteBalanceGains(for: values)
            gains.redGain = min(max(gains.redGain, 1), d.maxWhiteBalanceGain)
            gains.greenGain = min(max(gains.greenGain, 1), d.maxWhiteBalanceGain)
            gains.blueGain = min(max(gains.blueGain, 1), d.maxWhiteBalanceGain)
            d.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        } else if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            d.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { completion in
            queue.async { [self] in
                guard state == .running, session.isRunning, !session.isInterrupted else {
                    completion.resume(throwing: CameraError.interrupted); return
                }
                guard continuation == nil else { completion.resume(throwing: CameraError.busy); return }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.maxPhotoDimensions = output.maxPhotoDimensions
                settings.photoQualityPrioritization = .quality
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
            finishPhoto(.failure(CameraError.interrupted))
            publish(CameraError.interrupted.localizedDescription)
        } else if name == AVCaptureSession.interruptionEndedNotification || reset {
            if reset { finishPhoto(.failure(CameraError.interrupted)) }
            if wantsRunning { startAuthorized() }
        } else {
            state = .stopped
            finishPhoto(.failure(CameraError.interrupted))
            publish("카메라 오류가 발생했습니다. 다시 시작을 눌러 주세요.")
        }
    }

    private func publish(_ message: String? = nil) {
        onSnapshot(CameraSnapshot(lenses: devices.map { d in
            CameraLens(id: d.uniqueID, name: d.localizedName, isFront: d.position == .front)
        }, selectedLens: input?.device.uniqueID, capabilities: capabilities(), state: state, message: message))
    }
}
