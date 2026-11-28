@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import CoreVideo
import ImageIO
import Foundation

struct NativePhotoDepth {
    let field: SoftwareDepthField
    let geometry: DepthGeometry
    let disparity: CIImage // oriented, numeric data, for independent reference
}

enum NativePhotoDepthReader {
    static func read(_ url: URL, colorWidth: Int, colorHeight: Int) throws -> NativePhotoDepth? {
        let trace = ProcessingTrace.begin("Native photo depth decode")
        defer { ProcessingTrace.end("Native photo depth decode", trace) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw CameraError.invalidPhotoData }
        guard let dictionary = (CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth)
            ?? CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDisparity)) as? [AnyHashable: Any] else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let orientation = CGImagePropertyOrientation(rawValue: (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1) else {
            throw CameraError.invalidPhotoData
        }
        let attachment = try AVDepthData(fromDictionaryRepresentation: dictionary)
        let geometry = DepthGeometry(colorWidth: width, colorHeight: height,
            depthWidth: CVPixelBufferGetWidth(attachment.depthDataMap),
            depthHeight: CVPixelBufferGetHeight(attachment.depthDataMap), orientation: orientation.rawValue)
        guard geometry.matchesOrientedColor(width: colorWidth, height: colorHeight) else {
            throw ImageEditingError.invalid("사진과 깊이의 방향·좌표 크기가 일치하지 않습니다. 원본은 보존됩니다.")
        }
        let oriented = attachment.applyingExifOrientation(orientation)
        let data = oriented.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let buffer = data.depthDataMap, w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w == geometry.orientedDepthWidth, h == geometry.orientedDepthHeight,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { throw CameraError.invalidPhotoData }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer) >= w*4 else {
            throw CameraError.invalidPhotoData
        }
        var values = [Float](repeating: 0, count: w*h)
        for y in 0..<h {
            try Task.checkCancellation()
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float.self)
            for x in 0..<w { let z = row[x]; values[y*w+x] = z.isFinite && z > 0 ? 1/z : 0 }
        }
        let quality: NativeDepthMetadata.Quality
        switch data.depthDataQuality {
        case .low: quality = .low
        case .high: quality = .high
        @unknown default: quality = .unknown
        }
        var metadata = NativeDepthMetadata(mapWidth: w, mapHeight: h, quality: quality,
            filtered: data.isDepthDataFiltered, absoluteAccuracy: data.depthDataAccuracy == .absolute,
            originalPixelFormat: attachment.depthDataType, appliedEXIFOrientation: orientation.rawValue,
            hasCameraCalibration: attachment.cameraCalibrationData != nil)
        metadata.geometry = geometry
        if let calibration = attachment.cameraCalibrationData {
            let matrix = calibration.intrinsicMatrix
            metadata.intrinsicMatrix = (0..<3).flatMap { c in (0..<3).map { r in matrix[c][r] } }
            metadata.intrinsicReferenceWidth = Double(calibration.intrinsicMatrixReferenceDimensions.width)
            metadata.intrinsicReferenceHeight = Double(calibration.intrinsicMatrixReferenceDimensions.height)
        }
        guard let field = SoftwareDepthField(width: w, height: h, inverseDepth: values,
            units: metadata.absoluteAccuracy ? .inverseMetres : .relativeInverse, nativeMetadata: metadata) else {
            throw ImageEditingError.invalid("사진 깊이 값 또는 보정 정보가 유효하지 않습니다. 원본은 보존됩니다.")
        }
        let disparity = CIImage(cvPixelBuffer: oriented.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32).depthDataMap,
            options: [.colorSpace: NSNull()])
        return .init(field: field, geometry: geometry, disparity: disparity)
    }
}
