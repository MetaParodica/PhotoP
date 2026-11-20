import XCTest
import CoreML
import CoreImage
import Metal
import ImageIO
import UniformTypeIdentifiers
import Vision
import CoreVideo
@testable import PhotoP

final class NaturalDepthTests: XCTestCase {
    func testDistantFocusBlursThinNearForegroundAndSpillsOverSharpBackground() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let extent = CGRect(x: 0, y: 0, width: 1024, height: 256)
        let background = CIImage(color: CIColor(red: 0.1, green: 0.7, blue: 0.1)).cropped(to: extent)
        let checker = try XCTUnwrap(CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor(red: 0.9, green: 0.1, blue: 0.1),
            "inputColor1": CIColor(red: 0.1, green: 0.1, blue: 0.9), "inputWidth": 2.0
        ])?.outputImage).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 256))
        let color = checker.composited(over: background)
        let values: [Float] = (0..<(128 * 32)).map { $0 % 128 < 2 ? 1 : 0.05 }
        let field = try XCTUnwrap(SoftwareDepthField(width: 128, height: 32, inverseDepth: values, units: .inverseMetres))
        let rendered = try NaturalDepthEngine().renderField(color: color, field: field, aperture: 1.4,
            focus: CGPoint(x: 0.7, y: 0.5))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        func raster(_ image: CIImage) throws -> SDRImage {
            try SDRImage.rasterize(XCTUnwrap(context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: space)))
        }
        let before = try raster(color), after = try raster(rendered.image)
        func redRange(_ image: SDRImage) -> Int {
            let samples = (110..<130).map { Int(image.rgba[($0 * 1024 + 6) * 4]) }
            return (samples.max() ?? 0) - (samples.min() ?? 0)
        }
        XCTAssertLessThan(redRange(after), redRange(before) / 2)
        let far = (128 * 1024 + 700) * 4
        for channel in 0..<3 { XCTAssertEqual(Double(after.rgba[far + channel]), Double(before.rgba[far + channel]), accuracy: 2) }
        let spill = (128 * 1024 + 20) * 4
        XCTAssertGreaterThan(Int(after.rgba[spill]) + Int(after.rgba[spill + 2]), Int(before.rgba[spill]) + Int(before.rgba[spill + 2]) + 5)
    }
    private func fixture() throws -> (root: URL, photo: URL, field: SoftwareDepthField) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var pixels = [UInt8](repeating: 255, count: 256 * 192 * 4)
        for y in 0..<192 { for x in 0..<256 {
            let i = (y * 256 + x) * 4
            pixels[i] = x < 128 ? 180 : 20; pixels[i + 1] = 30
            pixels[i + 2] = x < 128 ? 30 : ((x + y) % 2 == 0 ? 30 : 240)
        } }
        let image = try SDRImage(rgba: Data(pixels), width: 256, height: 192).cgImage()
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let url = root.appendingPathComponent("original.png"); try (data as Data).write(to: url)
        let values = (0..<(16 * 12)).map { Float($0 % 16 < 8 ? 2 : 1) }
        return (root, url, try XCTUnwrap(SoftwareDepthField(width: 16, height: 12, inverseDepth: values, units: .relativeInverse)))
    }
    func testPinnedCompiledModelContractAndInference() throws {
        let input = try fixture()
        let image = try XCTUnwrap(CIImage(contentsOf: input.photo))
        let result = try ExternalDepthEstimator().estimate(image)
        let geometry = try XCTUnwrap(DepthModelGeometry(sourceWidth: 256, sourceHeight: 192))
        XCTAssertEqual(result.width, geometry.width); XCTAssertEqual(result.height, geometry.height)
        XCTAssertEqual(result.units, .relativeInverse)
        XCTAssertTrue(result.inverseDepth.contains(where: { $0 > 0 && $0.isFinite }))
    }
    func testNaturalRendererStoresDepthAndChangesBackgroundNotOriginal() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let input = try fixture(), before = try Data(contentsOf: input.photo)
        let result = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 1.4,
            focus: CGPoint(x: 0.25, y: 0.5), documents: input.root, depthOverride: input.field)
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
        let folder = result.deletingLastPathComponent()
        let recipe = try JSONDecoder().decode(CaptureResultRecipe.self, from: Data(contentsOf: folder.appendingPathComponent("recipe.json")))
        XCTAssertEqual(recipe.version, 3); XCTAssertEqual(recipe.depthUnits, "relativeInverse")
        XCTAssertNil(recipe.focusDistanceMetres)
        let map = try Data(contentsOf: folder.appendingPathComponent("depth.f32"))
        XCTAssertEqual(map.count, 16 * 12 * 4); XCTAssertEqual(recipe.depthMapSHA256, LUTPhotoEditor.hash(map))
        let output = try SDRImage.decode(result)
        XCTAssertEqual(Double(output.rgba[(96 * 256 + 32) * 4]), 180, accuracy: 5)
        XCTAssertGreaterThan(Int(output.rgba[(96 * 256 + 200) * 4 + 2]), 70)
        let second = try await CaptureResultProcessor.shared.reprocess(result: result, original: input.photo, aperture: 8, documents: input.root)
        XCTAssertNotEqual(result, second); XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
    }
    func testChangedDepthOrOriginalIsRejectedByReprocessor() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let input = try fixture()
        let result = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 2.8,
            focus: CGPoint(x: 0.25, y: 0.5), documents: input.root, depthOverride: input.field)
        let map = result.deletingLastPathComponent().appendingPathComponent("depth.f32")
        let beforeMap = try Data(contentsOf: map)
        var changed = beforeMap; changed[0] ^= 1; try changed.write(to: map)
        do {
            _ = try await CaptureResultProcessor.shared.reprocess(result: result, original: input.photo, aperture: 4, documents: input.root)
            XCTFail("Tampered depth must fail closed")
        } catch { }
        try beforeMap.write(to: map)
        var original = try Data(contentsOf: input.photo); original[0] ^= 1; try original.write(to: input.photo)
        do {
            _ = try await CaptureResultProcessor.shared.reprocess(result: result, original: input.photo, aperture: 4, documents: input.root)
            XCTFail("Changed original must fail closed")
        } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    func testUniformDepthFailsWithoutInventingBlur() throws {
        let input = try fixture(), image = try XCTUnwrap(CIImage(contentsOf: input.photo))
        let field = try XCTUnwrap(SoftwareDepthField(width: 3, height: 3, inverseDepth: Array(repeating: 1, count: 9), units: .relativeInverse))
        XCTAssertThrowsError(try NaturalDepthEngine().render(original: input.photo, color: image, width: 256, height: 192,
            aperture: 2.8, focus: CGPoint(x: 0.5, y: 0.5), source: .ai, override: field))
    }
    func testSavedSessionReopensAndRefocusProducesNewRecipeWithoutAI() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let input = try fixture(), before = try Data(contentsOf: input.photo)
        let originals = input.root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let original = originals.appendingPathComponent(input.photo.lastPathComponent)
        try FileManager.default.copyItem(at: input.photo, to: original)
        let result = try await CaptureResultProcessor.shared.render(original: original, look: nil, aperture: 2.8,
            focus: CGPoint(x: 0.25, y: 0.5), documents: input.root, depthOverride: input.field)
        let entries = try await CaptureResultProcessor.shared.list(documents: input.root)
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries.first?.original, original)
        let session = try await CaptureResultProcessor.shared.loadSession(result: result, original: original, documents: input.root)
        XCTAssertEqual(session.field.inverseDepth, input.field.inverseDepth)
        let edited = try await CaptureResultProcessor.shared.reprocess(result: result, original: original, aperture: 8,
            documents: input.root, focus: CGPoint(x: 0.75, y: 0.5), profile: .classic)
        let reopened = try await CaptureResultProcessor.shared.loadSession(result: edited, original: original, documents: input.root)
        XCTAssertEqual(reopened.recipe.focusX, 0.75); XCTAssertEqual(reopened.recipe.lensProfile, .classic)
        XCTAssertEqual(reopened.recipe.aperture, 8); XCTAssertEqual(reopened.field.inverseDepth, input.field.inverseDepth)
        XCTAssertEqual(try Data(contentsOf: original), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    func testInterruptedTransactionRecoveryKeepsRecentAndUnknownFolders() async throws {
        let input = try fixture(), root = input.root.appendingPathComponent("CaptureResults")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent(".pending-" + UUID().uuidString)
        let recent = root.appendingPathComponent(".pending-" + UUID().uuidString)
        let unknown = root.appendingPathComponent(".pending-user-files")
        for url in [old, recent, unknown] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        for url in [old, unknown] { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-172800)], ofItemAtPath: url.path) }
        _ = try await CaptureResultProcessor.shared.list(documents: input.root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }
    func testAllLensKernelsExecuteAndKeepConstantColor() throws {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let extent = CGRect(x: 0, y: 0, width: 24, height: 24)
        let input = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7)).cropped(to: extent)
        let filter = DepthLensFilter()
        let expectedCG = try XCTUnwrap(context.createCGImage(input, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        let expected = try SDRImage.rasterize(expectedCG)
        for profile in DepthLensProfile.allCases {
            for aperture in [1.4, 8.0, 16.0] {
                let output = try filter.blur(input, radius: 4, profile: profile, aperture: aperture)
                let cg = try XCTUnwrap(context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
                let pixels = try SDRImage.rasterize(cg)
                for c in 0..<4 { XCTAssertEqual(Double(pixels.rgba[c]), Double(expected.rgba[c]), accuracy: 1) }
            }
        }
    }
    func testDepthLayerROIsMatchFullFrameAcrossTileBoundary() throws {
        let extent = CGRect(x: 0, y: 0, width: 2112, height: 192)
        let color = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.5)).cropped(to: extent)
        let foreground = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 1040, height: 192)).composited(over: color)
        let values: [Float] = (0..<(66 * 6)).map { $0 % 66 < 32 ? 2 : 1 }
        let field = try XCTUnwrap(SoftwareDepthField(width: 66, height: 6, inverseDepth: values, units: .relativeInverse))
        let graph = try NaturalDepthEngine().renderField(color: foreground, field: field, aperture: 1.4,
            focus: CGPoint(x: 0.25, y: 0.5), profile: .classic, qualityPairs: 8).image
        let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let full = try SDRImage.rasterize(XCTUnwrap(context.createCGImage(graph, from: extent, format: .RGBA8, colorSpace: space)))
        let halo = try XCTUnwrap(SoftwareDepthPolicy.halo(width: 2112, height: 192, fieldWidth: 66, fieldHeight: 6))
        let plan = try XCTUnwrap(HighResolutionPlan(width: 2112, height: 192, halo: halo))
        var maximumError = 0, firstMismatch = ""
        for region in plan.tiles {
            let rect = CGRect(x: region.input.x, y: plan.height - region.input.maxY, width: region.input.width, height: region.input.height)
            let tile = try SDRImage.rasterize(XCTUnwrap(context.createCGImage(graph, from: rect, format: .RGBA8, colorSpace: space)))
            for y in 0..<region.output.height { for x in 0..<region.output.width { for c in 0..<4 {
                let source = ((y + region.output.y - region.input.y) * tile.width + x + region.output.x - region.input.x) * 4 + c
                let destination = ((y + region.output.y) * full.width + x + region.output.x) * 4 + c
                let error = abs(Int(tile.rgba[source]) - Int(full.rgba[destination]))
                if error > 2 && firstMismatch.isEmpty { firstMismatch = "x=\(x + region.output.x),y=\(y + region.output.y),channel=\(c)" }
                maximumError = max(maximumError, error)
            } } }
        }
        XCTAssertLessThanOrEqual(maximumError, 2, "Depth halo/core crop must match full render. First mismatch: \(firstMismatch)")
    }
    func testRefocusOutsideStoredInstanceDoesNotKeepOldSubjectMask() throws {
        let input = try fixture(), image = try XCTUnwrap(CIImage(contentsOf: input.photo))
        let alpha: [Float] = (0..<81).map { $0 % 9 < 4 ? 1 : 0 }
        let colors = [SIMD3<Float>](repeating: SIMD3(0.2, 0.3, 0.4), count: 81)
        let matte = DepthMatteSurface(width: 9, height: 9, alpha: alpha, foreground: colors, background: colors)
        let engine = NaturalDepthEngine()
        let first = try engine.renderField(color: image, field: input.field, aperture: 2.8, focus: CGPoint(x: 0.25, y: 0.5), matte: matte)
        let second = try engine.renderField(color: image, field: input.field, aperture: 2.8, focus: CGPoint(x: 0.75, y: 0.5), matte: matte)
        XCTAssertTrue(first.matteUsed); XCTAssertFalse(second.matteUsed)
        XCTAssertEqual(second.matte?.alpha, alpha, "Keep the immutable original matte for a future focus change back")
    }
    func testLargeCoCHighlightHasContinuousCoverageAndBoundedEnergy() throws {
        let extent = CGRect(x: 0, y: 0, width: 65, height: 65)
        let black = CIImage(color: .black).cropped(to: extent)
        let point = CIImage(color: .white).cropped(to: CGRect(x: 32, y: 32, width: 1, height: 1)).composited(over: black)
        let output = try DepthLensFilter().blur(point, radius: 20, profile: .natural, aperture: 2.8)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        var pixels = [Float](repeating: 0, count: 65 * 65 * 4)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(output, toBitmap: bytes.baseAddress!, rowBytes: 65 * 16, bounds: extent, format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        }
        let red = stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
        XCTAssertGreaterThan(red.filter { $0 > 0.00001 }.count, 250, "Large highlights must fill the aperture rather than expose isolated PSF taps")
        XCTAssertEqual(red.reduce(0, +), 1, accuracy: 0.3)
    }
    func testVisionBackwardFlowDirectionOnAsymmetricTranslatedRGB() throws {
        let w = 128, h = 96
        var previous = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4, px = Double(x), py = Double(y)
            previous[i] = UInt8(127 + 50 * sin(px * 0.15) + 30 * cos(py * 0.19))
            previous[i + 1] = UInt8(127 + 60 * sin((px + py) * 0.12))
            previous[i + 2] = UInt8(127 + 45 * cos(px * 0.37 - py * 0.13))
        } }
        var current = [UInt8](repeating: 128, count: previous.count)
        for y in 0..<h { for x in 0..<w {
            current[(y * w + x) * 4 + 3] = 255
            if x >= 3, y >= 2 {
                for c in 0..<3 { current[(y * w + x) * 4 + c] = previous[((y - 2) * w + x - 3) * 4 + c] }
            }
        } }
        let a = try SDRImage(rgba: Data(previous), width: w, height: h).cgImage()
        let b = try SDRImage(rgba: Data(current), width: w, height: h).cgImage()
        let flow: [SIMD2<Float>]
        do { flow = try DepthMotionEstimator().backwardFlow(current: b, previous: a) }
        catch let error as NSError {
            #if targetEnvironment(simulator)
            guard DepthMotionEstimator.isUnavailableSimulatorBackend(error, simulator: true) else { throw error }
            throw XCTSkip("Vision optical-flow runtime unavailable: \(error.localizedDescription); production uses motion-gated fallback")
            #else
            throw error
            #endif
        }
        var xValues: [Float] = [], yValues: [Float] = []
        for y in 24..<72 { for x in 32..<96 { xValues.append(flow[y * w + x].x); yValues.append(flow[y * w + x].y) } }
        xValues.sort(); yValues.sort()
        XCTAssertEqual(xValues[xValues.count / 2], -3, accuracy: 1)
        XCTAssertEqual(yValues[yValues.count / 2], -2, accuracy: 1)
    }
    func testOnlyKnownSimulatorFlowBackendFailureCanSkipDirectionValidation() {
        let unavailable = NSError(domain: VNErrorDomain, code: VNErrorCode.internalError.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create motion flow estimator"])
        XCTAssertTrue(DepthMotionEstimator.isUnavailableSimulatorBackend(unavailable, simulator: true))
        XCTAssertFalse(DepthMotionEstimator.isUnavailableSimulatorBackend(unavailable, simulator: false))
        let differentFailure = NSError(domain: VNErrorDomain, code: VNErrorCode.operationFailed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create motion flow estimator"])
        XCTAssertFalse(DepthMotionEstimator.isUnavailableSimulatorBackend(differentFailure, simulator: true))
        let malformed = NSError(domain: VNErrorDomain, code: VNErrorCode.invalidFormat.rawValue, userInfo: [:])
        XCTAssertFalse(DepthMotionEstimator.isUnavailableSimulatorBackend(malformed, simulator: true))
    }
    func testMatteInstanceSelectionHandlesPaddedRowsAndLabelsBeyondEight() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 7, 5, kCVPixelFormatType_OneComponent8,
            [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary, &buffer), kCVReturnSuccess)
        let mask = try XCTUnwrap(buffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(mask, []), kCVReturnSuccess)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(mask))
        let stride = CVPixelBufferGetBytesPerRow(mask)
        base.initializeMemory(as: UInt8.self, repeating: 0, count: stride * 5)
        base.advanced(by: 3 * stride + 5).storeBytes(of: UInt8(12), as: UInt8.self)
        base.advanced(by: 5).storeBytes(of: UInt8(3), as: UInt8.self)
        base.advanced(by: 4 * stride + 6).storeBytes(of: UInt8(20), as: UInt8.self)
        CVPixelBufferUnlockBaseAddress(mask, [])
        XCTAssertEqual(DepthMatteRefiner.instance(at: CGPoint(x: 0.8, y: 0.7), mask: mask), 12)
        XCTAssertEqual(DepthMatteRefiner.instance(at: CGPoint(x: 1, y: 1), mask: mask), 20)
        XCTAssertNil(DepthMatteRefiner.instance(at: .zero, mask: mask))
        XCTAssertNil(DepthMatteRefiner.instance(at: CGPoint(x: CGFloat.nan, y: 0), mask: mask))
    }
    @MainActor func testOfflineManualAndExposureLocksAreNotChangedByAFOn() async {
        let model = CameraModel(); model.settings.focus.manual = true; model.settings.exposure.locked = true
        let before = model.settings
        await model.autofocusOn()
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.focusPhase, .manual)
    }
    func testCorrectionRecipePreservesBaseMapAcrossReopenAndClearing() async throws {
        let input = try fixture(), before = try Data(contentsOf: input.photo)
        let edits = DepthCorrections(strokes: [.init(points: [.init(x: 0.75,y: 0.5)],mode: .foreground,radius: 0.1,softness: 0.6)])
        let result = try await CaptureResultProcessor.shared.render(original: input.photo,look: nil,aperture: 2.8,
            focus: CGPoint(x: 0.25,y: 0.5),documents: input.root,depthOverride: input.field,corrections: edits)
        let session = try await CaptureResultProcessor.shared.loadSession(result: result,original: input.photo,documents: input.root)
        XCTAssertEqual(session.recipe.version,4); XCTAssertEqual(session.corrections,edits)
        XCTAssertEqual(session.field.inverseDepth,input.field.inverseDepth,"Saved depth is immutable base, never a twice-corrected map")
        let next = try await CaptureResultProcessor.shared.reprocess(result: result,original: input.photo,aperture: 4,documents: input.root)
        let reopened = try await CaptureResultProcessor.shared.loadSession(result: next,original: input.photo,documents: input.root)
        XCTAssertEqual(reopened.corrections,edits); XCTAssertEqual(reopened.recipe.depthMapSHA256,session.recipe.depthMapSHA256)
        let clear = try await CaptureResultProcessor.shared.reprocess(result: next,original: input.photo,aperture: 4,documents: input.root,corrections: .init())
        let cleared = try await CaptureResultProcessor.shared.loadSession(result: clear,original: input.photo,documents: input.root)
        XCTAssertEqual(cleared.recipe.version,3); XCTAssertTrue(cleared.corrections.strokes.isEmpty)
        XCTAssertEqual(cleared.field.inverseDepth,input.field.inverseDepth)
        XCTAssertEqual(try Data(contentsOf: input.photo),before)
        var corrupt = reopened.recipe; corrupt.depthMapRole = nil
        try JSONEncoder().encode(corrupt).write(to: next.deletingLastPathComponent().appendingPathComponent("recipe.json"))
        do { _ = try await CaptureResultProcessor.shared.loadSession(result: next,original: input.photo,documents: input.root); XCTFail("v4 missing base-map contract accepted") } catch { }
    }

}
