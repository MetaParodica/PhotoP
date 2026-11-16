@preconcurrency import AVFoundation
import Foundation

// SDK symbols are isolated as well as runtime availability. An old SDK cannot
// type-check a new API merely because it is behind #available.
enum CameraPlatformFeatures {
    static func autoISOSupported(_ device: AVCaptureDevice, duration: CMTime? = nil) -> Bool {
        #if PHOTOP_CAMERA_SDK27
        if #available(iOS 27.0, *) {
            return device.activeFormat.supportsExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture,
                duration: duration ?? device.exposureDuration, iso: AVCaptureDevice.autoISO)
        }
        #endif
        return false
    }
    static func requestedISO(_ iso: Float, automatic: Bool, device: AVCaptureDevice, duration: CMTime) throws -> Float {
        guard automatic else { return iso }
        #if PHOTOP_CAMERA_SDK27
        if #available(iOS 27.0, *), autoISOSupported(device, duration: duration) { return AVCaptureDevice.autoISO }
        #endif
        throw CameraError.invalidSettings
    }
    static func autoISOActive(_ device: AVCaptureDevice) -> Bool {
        #if PHOTOP_CAMERA_SDK27
        if #available(iOS 27.0, *) { return device.automaticallyAdjustsISO }
        #endif
        return false
    }
    static func focusRectangleSupported(_ device: AVCaptureDevice) -> Bool {
        #if PHOTOP_CAMERA_SDK26
        if #available(iOS 26.0, *) { return device.isFocusRectOfInterestSupported }
        #endif
        return false
    }
    static func setFocusArea(_ area: FocusArea, point: CGPoint, device: AVCaptureDevice) throws {
        #if PHOTOP_CAMERA_SDK26
        if #available(iOS 26.0, *), device.isFocusRectOfInterestSupported, area != .point {
            let size = device.minFocusRectOfInterestSize
            guard let rect = area.rect(x: Double(point.x), y: Double(point.y), minimumWidth: Double(size.width), minimumHeight: Double(size.height)) else { throw CameraError.invalidSettings }
            device.focusRectOfInterest = rect
            return
        }
        #endif
        guard area == .point else { throw CameraError.invalidSettings }
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
    }
    static func nativeTrackingSupported(_ device: AVCaptureDevice) -> Bool {
        #if PHOTOP_CAMERA_SDK27
        if #available(iOS 27.0, *) { return device.activeFormat.isContinuousAutoFocusTrackingSupported }
        #endif
        return false
    }
    static func setTracking(_ enabled: Bool, device: AVCaptureDevice) throws {
        #if PHOTOP_CAMERA_SDK27
        if #available(iOS 27.0, *) {
            guard !enabled || device.activeFormat.isContinuousAutoFocusTrackingSupported else { throw CameraError.invalidSettings }
            // Caller owns configuration lock and subscribes focusTrackedObject.
            if device.activeFormat.isContinuousAutoFocusTrackingSupported { device.isContinuousAutoFocusTrackingEnabled = enabled }
            return
        }
        #endif
        if enabled { throw CameraError.invalidSettings }
    }
    static func isTracking(_ device: AVCaptureDevice) -> Bool {
        #if PHOTOP_CAMERA_SDK27
        if #available(iOS 27.0, *), device.activeFormat.isContinuousAutoFocusTrackingSupported {
            return device.isContinuousAutoFocusTrackingSubjectAcquired
        }
        #endif
        return false
    }
    static func prepareTrackingMetadata(_ output: AVCaptureMetadataOutput, session: AVCaptureSession,
        delegate: AVCaptureMetadataOutputObjectsDelegate, queue: DispatchQueue) throws {
        #if PHOTOP_CAMERA_SDK27
        if #available(iOS 27.0, *) {
            if !session.outputs.contains(output) {
                guard session.canAddOutput(output) else { throw CameraError.configuration }
                session.beginConfiguration(); session.addOutput(output); session.commitConfiguration()
            }
            guard output.availableMetadataObjectTypes.contains(.focusTrackedObject) else { throw CameraError.invalidSettings }
            output.setMetadataObjectsDelegate(delegate, queue: queue)
            output.metadataObjectTypes = [.focusTrackedObject]
            return
        }
        #endif
        throw CameraError.invalidSettings
    }
}
