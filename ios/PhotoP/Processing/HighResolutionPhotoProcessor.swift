import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Darwin

struct HighResolutionResult: Sendable {
    let width: Int
    let height: Int
    let focusDepth: Float?
    let absoluteDepth: Bool
}

// File-backed full-size RGBA, with bounded CPU/GPU tile buffers. ImageIO may
// still allocate decoder/encoder memory; device peak usage needs measurement.
private final class DiskBackedPhotoRaster {
    let pointer: UnsafeMutableRawPointer
    let plan: HighResolutionPlan
    private let file: FileHandle
    private let url: URL
    init(plan: HighResolutionPlan, folder: URL) throws {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: folder.path)
        guard let free = attributes[.systemFreeSize] as? NSNumber, free.int64Value >= plan.minimumFreeBytes else {
            throw ImageEditingError.invalid("고해상도 처리용 임시 저장 공간이 부족합니다. 원본은 보존됩니다.")
        }
        let url = folder.appendingPathComponent(".raster-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw CameraError.invalidPhotoData }
        do {
            let handle = try FileHandle(forUpdating: url)
            do {
                // Reserve real file space before exposing a writable mapping.
                // A sparse truncate alone can turn low-disk writes into SIGBUS.
                var allocation = fstore_t()
                allocation.fst_flags = UInt32(F_ALLOCATEALL)
                allocation.fst_posmode = Int32(F_PEOFPOSMODE)
                allocation.fst_length = off_t(plan.byteCount)
                let reserved = withUnsafeMutablePointer(to: &allocation) { Darwin.fcntl(handle.fileDescriptor, F_PREALLOCATE, $0) }
                guard reserved == 0 else { throw ImageEditingError.invalid("고해상도 임시 파일 공간을 예약하지 못했습니다. 원본은 보존됩니다.") }
                try handle.truncate(atOffset: UInt64(plan.byteCount))
                let mapped = mmap(nil, plan.byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, handle.fileDescriptor, 0)
                guard mapped != MAP_FAILED, let mapped else { throw ImageEditingError.invalid("고해상도 작업 파일을 매핑하지 못했습니다.") }
                self.plan = plan; self.url = url; self.file = handle; self.pointer = mapped
            } catch { try? handle.close(); throw error }
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
    deinit { munmap(pointer, plan.byteCount); try? file.close(); try? FileManager.default.removeItem(at: url) }
    func discardBackingFile() {
        // Unlink before the pending bundle is moved. An ImageIO provider may
        // retain us briefly; its mapping/open fd stay valid after unlinking.
        try? FileManager.default.removeItem(at: url)
    }
    func write(_ data: Data, tile: HighResolutionPlan.Tile) throws {
        guard data.count == tile.input.width * tile.input.height * 4 else { throw CameraError.invalidPhotoData }
        data.withUnsafeBytes { bytes in
            for y in 0..<tile.output.height {
                let source = ((tile.output.y - tile.input.y + y) * tile.input.width + tile.output.x - tile.input.x) * 4
                let destination = ((tile.output.y + y) * plan.width + tile.output.x) * 4
                pointer.advanced(by: destination).copyMemory(from: bytes.baseAddress!.advanced(by: source), byteCount: tile.output.width * 4)
            }
        }
    }
    func cgImage() throws -> CGImage {
        let info = Unmanaged.passRetained(self).toOpaque()
        guard let provider = CGDataProvider(dataInfo: info, data: UnsafeRawPointer(pointer), size: plan.byteCount,
            releaseData: { info, _, _ in if let info { Unmanaged<DiskBackedPhotoRaster>.fromOpaque(info).release() } }) else {
            Unmanaged<DiskBackedPhotoRaster>.fromOpaque(info).release(); throw CameraError.invalidPhotoData
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: plan.width, height: plan.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: plan.width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: SDRImage.bitmapInfo),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric) else { throw CameraError.invalidPhotoData }
        return image
    }
}

actor HighResolutionPhotoProcessor {
    static let shared = HighResolutionPhotoProcessor()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var rendering = false
    func renderJPEG(original: URL, destination: URL, lut: CubeLUT?, settings: ProcessingLookSettings,
                    aperture: Double? = nil, focus: CGPoint = CGPoint(x: 0.5, y: 0.5), credit: String? = nil) async throws -> HighResolutionResult {
        guard !rendering else { throw CameraError.busy }
        rendering = true; defer { rendering = false; context.clearCaches() }
        try Task.checkCancellation(); try settings.validate()
        guard !FileManager.default.fileExists(atPath: destination.path),
              original.pathExtension.lowercased() != "dng",
              let source = CGImageSourceCreateWithURL(original as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? != "com.adobe.raw-image",
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = metadata[kCGImagePropertyPixelWidth] as? Int,
              let rawHeight = metadata[kCGImagePropertyPixelHeight] as? Int,
              HighResolutionPlan(width: rawWidth, height: rawHeight) != nil else {
            throw ImageEditingError.invalid("고해상도 SDR 처리는 최대 64MP·긴 변 16384px입니다. RAW 현상은 지원하지 않으며 원본은 보존됩니다.")
        }
        guard var color = CIImage(contentsOf: original, options: [.applyOrientationProperty: true]),
              color.extent.width.isFinite, color.extent.height.isFinite,
              color.extent.width > 0, color.extent.height > 0,
              color.extent.width <= CGFloat(HighResolutionPlan.maximumDimension),
              color.extent.height <= CGFloat(HighResolutionPlan.maximumDimension) else { throw CameraError.invalidPhotoData }
        color = color.transformed(by: CGAffineTransform(translationX: -color.extent.minX, y: -color.extent.minY))
        let width = Int(color.extent.width), height = Int(color.extent.height)
        let effects = settings.finish
        guard lut != nil || (settings.grain.amount == 0 && !effects.enabled) else {
            throw ImageEditingError.invalid("입자·마감 효과에는 LUT 또는 항등 LUT가 필요합니다.")
        }
        guard let halo = HighResolutionPlan.halo(longEdge: max(width, height),
                neighbours: effects.bloom > 0 || effects.halation > 0 || effects.softFocus > 0,
                chromaticAberration: effects.chromaticAberration, streak: effects.streak > 0),
              let plan = HighResolutionPlan(width: width, height: height, halo: halo),
              (width == rawWidth && height == rawHeight) || (width == rawHeight && height == rawWidth) else { throw CameraError.invalidPhotoData }
        var distance: Float?, absolute = false
        if let aperture {
            let depth = try MeasuredDepthEffect.make(original: original, color: color, width: width, height: height, aperture: aperture, focus: focus)
            color = depth.image; distance = depth.focus; absolute = depth.absolute
        }
        let renderer: MetalLUTRenderer?
        if let lut { renderer = try MetalLUTRenderer(lut: lut) } else { renderer = nil }
        let raster = try DiskBackedPhotoRaster(plan: plan, folder: destination.deletingLastPathComponent())
        defer { raster.discardBackingFile() }
        for tile in plan.tiles {
            try Task.checkCancellation()
            // CI bounds are bottom-left; CGImage/SDRImage memory is top-left.
            let pixels: SDRImage = try autoreleasepool {
                let rect = CGRect(x: tile.input.x, y: height - tile.input.maxY, width: tile.input.width, height: tile.input.height)
                guard let cg = context.createCGImage(color, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
                return try SDRImage.rasterize(cg)
            }
            let data: Data
            if let renderer {
                data = try await renderer.render(pixels.rgba, width: pixels.width, height: pixels.height,
                    intensity: settings.intensity, grain: settings.grain, effects: effects,
                    frame: SIMD4(UInt32(tile.input.x), UInt32(tile.input.y), UInt32(width), UInt32(height)))
            } else { data = pixels.rgba }
            try raster.write(data, tile: tile)
        }
        try Task.checkCancellation()
        do {
            try autoreleasepool {
                guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw CameraError.invalidPhotoData }
                var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95, kCGImagePropertyOrientation: 1]
                if let credit { properties[kCGImagePropertyIPTCDictionary] = [kCGImagePropertyIPTCCaptionAbstract: credit] }
                CGImageDestinationAddImage(output, try raster.cgImage(), properties as CFDictionary)
                guard CGImageDestinationFinalize(output) else { throw ImageEditingError.invalid("고해상도 JPEG 저장이 실패했습니다.") }
            }
            try Task.checkCancellation()
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
        return HighResolutionResult(width: width, height: height, focusDepth: distance, absoluteDepth: absolute)
    }
}
