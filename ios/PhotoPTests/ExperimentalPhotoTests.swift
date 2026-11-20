import XCTest
import CoreImage
import ImageIO
@testable import PhotoP

final class ExperimentalPhotoTests: XCTestCase {
    private func fixture() throws -> (root: URL, photo: URL, runtime: ExperimentalDepthRuntime, field: SoftwareDepthField) {
        let suite = "photop.tests.photo-experiment." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "experimental-astronaut", withExtension: "png"))
        let photo = folder.appendingPathComponent("reference.png")
        try FileManager.default.copyItem(at: source, to: photo)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let field = try XCTUnwrap(SoftwareDepthField(width: 16, height: 16,
            inverseDepth: (0..<256).map { $0 % 16 < 8 ? 2 : 1 }, units: .relativeInverse))
        return (root, photo, ExperimentalDepthRuntime(defaults: defaults), field)
    }
    func testBundledPhotoModelsRunActualSelectedMaskAndProduceFiniteMatte() throws {
        XCTAssertTrue(ExperimentalPhotoSubjectSelector.isBundled)
        let input = try fixture(); input.runtime.setPhotoSelection(true)
        let request = try XCTUnwrap(input.runtime.request(for: .photo))
        let selected = try ExperimentalPhotoSubjectSelector(diagnostics: { print("PhotoP photo-model diagnostic: " + $0) }).refine(original: input.photo,
            focus: CGPoint(x: 0.45, y: 0.6), request: request)
        XCTAssertEqual(selected.1.outcome, .applied); XCTAssertTrue(selected.1.valid)
        XCTAssertEqual(selected.0.width, 512); XCTAssertEqual(selected.0.height, 512)
        XCTAssertTrue(selected.0.alpha.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertGreaterThan(selected.0.alpha[307 * 512 + 230], 0.5)
        XCTAssertTrue(selected.0.alpha.contains { $0 < 0.1 })
    }
    func testSavedSelectionReopensAndReprocessesAfterExperimentIsDisabled() async throws {
        let input = try fixture(), original = try Data(contentsOf: input.photo)
        input.runtime.setPhotoSelection(true)
        let request = try XCTUnwrap(input.runtime.request(for: .photo))
        let result = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 2.8,
            focus: CGPoint(x: 0.45, y: 0.6), documents: input.root, depthOverride: input.field, experimentalRequest: request)
        let session = try await CaptureResultProcessor.shared.loadSession(result: result, original: input.photo, documents: input.root)
        XCTAssertEqual(session.recipe.experimentalDepth?.outcome, .applied)
        XCTAssertTrue(session.recipe.experimentalDepth?.valid == true)
        XCTAssertNotNil(session.matte); XCTAssertTrue(session.recipe.portraitMatteUsed == true)
        input.runtime.setPhotoSelection(false)
        let reopened = try await CaptureResultProcessor.shared.reprocess(result: result, original: input.photo, aperture: 5.6, documents: input.root)
        let restored = try await CaptureResultProcessor.shared.loadSession(result: reopened, original: input.photo, documents: input.root)
        XCTAssertEqual(restored.recipe.experimentalDepth, session.recipe.experimentalDepth)
        XCTAssertEqual(restored.recipe.matteSHA256, session.recipe.matteSHA256)
        XCTAssertEqual(restored.recipe.depthMapSHA256, session.recipe.depthMapSHA256)
        XCTAssertEqual(try Data(contentsOf: input.photo), original)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let iptc = try XCTUnwrap(properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any])
        XCTAssertTrue((iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String)?.contains("PhotoP AI photo selection") == true)
    }
    func testDisabledPhotoLeaseFallsBackToBaselineAndPreservesDepthEditing() async throws {
        let input = try fixture(); input.runtime.setPhotoSelection(true)
        let old = try XCTUnwrap(input.runtime.request(for: .photo)); input.runtime.setPhotoSelection(false)
        let output = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 2.8,
            focus: CGPoint(x: 0.45, y: 0.6), documents: input.root, depthOverride: input.field, experimentalRequest: old)
        let baseline = try await CaptureResultProcessor.shared.loadSession(result: output, original: input.photo, documents: input.root)
        XCTAssertEqual(baseline.recipe.experimentalDepth?.outcome, .fallback)
        XCTAssertEqual(baseline.recipe.experimentalDepth?.failure, .disabled)
        XCTAssertEqual(baseline.field.inverseDepth, input.field.inverseDepth)
        XCTAssertNotNil(baseline.recipe.aperture)
        let normal = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 2.8,
            focus: CGPoint(x: 0.45, y: 0.6), documents: input.root, depthOverride: input.field)
        let saved = try await CaptureResultProcessor.shared.loadSession(result: normal, original: input.photo, documents: input.root)
        XCTAssertNil(saved.recipe.experimentalDepth)
        XCTAssertEqual(saved.recipe.depthMapSHA256, baseline.recipe.depthMapSHA256)
    }
    func testPhotoOnlyPortraitNeuralMatteIsSavedAndRestoredWithExperimentsOff() async throws {
        XCTAssertTrue(ExperimentalPortraitMatte.isBundled)
        let input = try fixture(), original = try Data(contentsOf: input.photo)
        input.runtime.setPortraitMatte(true)
        let request = try XCTUnwrap(input.runtime.request(for: .photo))
        XCTAssertFalse(request.preferences.photoSubjectSelection)
        let output = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 2.8,
            focus: CGPoint(x: 0.45, y: 0.6), documents: input.root, depthOverride: input.field, experimentalRequest: request)
        let session = try await CaptureResultProcessor.shared.loadSession(result: output, original: input.photo, documents: input.root)
        XCTAssertNil(session.recipe.experimentalDepth)
        let record = try XCTUnwrap(session.recipe.experimentalPortrait)
        XCTAssertEqual(record.outcome, .applied, record.failure?.title ?? "")
        XCTAssertTrue(record.valid); XCTAssertEqual(record.warmupPredictions, 10)
        let matte = try XCTUnwrap(session.matte)
        XCTAssertTrue(matte.alpha.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertTrue(matte.alpha.contains { $0 > 0.01 && $0 < 0.99 }, "Neural alpha must retain fractional boundary values")
        input.runtime.setPortraitMatte(false)
        let reprocessed = try await CaptureResultProcessor.shared.reprocess(result: output, original: input.photo, aperture: 5.6, documents: input.root)
        let restored = try await CaptureResultProcessor.shared.loadSession(result: reprocessed, original: input.photo, documents: input.root)
        XCTAssertEqual(restored.recipe.experimentalPortrait, session.recipe.experimentalPortrait)
        XCTAssertEqual(restored.recipe.matteSHA256, session.recipe.matteSHA256)
        XCTAssertEqual(try Data(contentsOf: input.photo), original)
    }
}
