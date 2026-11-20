import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class AdvancedDepthTests: XCTestCase {
    func testSpatialPSFIsSharedAndBoundedAtEdges() {
        for profile in DepthLensProfile.allCases {
            let taps = DepthLensKernel.taps(profile: profile, aperture: 8)
            var edgeMoment = 0.0, centerMoment = 0.0
            for t in taps {
                let o = DepthLensKernel.offset(t, x: 0, y: 0, width: 101, height: 101, profile: profile)
                XCTAssertLessThanOrEqual(o.x * o.x + o.y * o.y, 1.000001)
                edgeMoment += (o.x * o.x + o.y * o.y) * t.weight
                centerMoment += (t.x * t.x + t.y * t.y) * t.weight
            }
            if profile.catEye > 0 { XCTAssertLessThan(edgeMoment, centerMoment) }
            else { XCTAssertEqual(edgeMoment, centerMoment, accuracy: 1e-10) }
        }
    }
    func testVirtualFocalLengthChangesCoCWithoutChangingFocusOrLimits() throws {
        for profile in DepthLensProfile.allCases {
            let r = try XCTUnwrap(SoftwareDepthPolicy.radius(inverse: 0.2, focus: 0.5, span: 1,
                absolute: true, aperture: 2.8, longEdge: 4032, focalLengthMM: profile.focalLengthMM))
            XCTAssertGreaterThan(r, 0); XCTAssertLessThanOrEqual(r, 48)
            XCTAssertEqual(SoftwareDepthPolicy.radius(inverse: 0.5, focus: 0.5, span: 1,
                absolute: true, aperture: 2.8, longEdge: 4032, focalLengthMM: profile.focalLengthMM), 0)
        }
        XCTAssertEqual(DepthLensProfile.legacy.map(\.rawValue), ["natural", "portrait", "classic"])
        XCTAssertEqual(DepthLensProfile.allCases.count, 9)
    }
    func testMatteColorLineImprovesKnownFractionalBoundaryAndKeepsSeeds() throws {
        let w = 17, h = 17, f = SIMD3<Float>(0.9, 0.15, 0.1), b = SIMD3<Float>(0.05, 0.4, 0.6)
        let truth: [Float] = (0..<(w*h)).map { i in min(1, max(0, Float(i % w - 6) / 4)) }
        let prior = truth.map { $0 > 0 && $0 < 1 ? $0 * 0.6 + 0.1 : $0 }
        let color = truth.map { f * $0 + b * (1 - $0) }
        let surface = try XCTUnwrap(DepthMatteCore.refine(alpha: prior, color: color, width: w, height: h))
        var before: Float = 0, after: Float = 0
        for i in truth.indices {
            if truth[i] == 0 || truth[i] == 1 { XCTAssertEqual(surface.alpha[i], truth[i]) }
            else { before += abs(prior[i] - truth[i]); after += abs(surface.alpha[i] - truth[i]) }
        }
        XCTAssertLessThan(after, before * 0.35, "Fractional RGB mixture ground truth, not a real-hair quality claim")
        print("SYNTHETIC matte boundary MAE before=\(before / Float(h*3)) after=\(after / Float(h*3))")
    }
    func testMatteDoesNotInventStructureWithoutContrastingSeeds() throws {
        let color = [SIMD3<Float>](repeating: SIMD3(repeating: 0.4), count: 81)
        let prior = [Float](repeating: 0.5, count: 81)
        let result = try XCTUnwrap(DepthMatteCore.refine(alpha: prior, color: color, width: 9, height: 9))
        XCTAssertEqual(result.alpha, prior)
    }

    func testRegisteredTemporalDepthReducesAlternatingNoiseAndRejectsCut() throws {
        let w = 16, h = 16, luma = [Float](repeating: 0.5, count: 256)
        let truth = (0..<256).map { Float($0 % w) / 20 + 0.2 }
        var state = DepthTemporalState(), before: Float = 0, after: Float = 0
        for frame in 0..<30 {
            let noisy = truth.enumerated().map { i, v in v + (i % 2 == frame % 2 ? 0.018 : -0.018) }
            let next = try XCTUnwrap(SoftwareDepthField(width: w, height: h, inverseDepth: noisy, units: .relativeInverse))
            if frame > 0 { XCTAssertTrue(state.alignHistory(backwardFlow: .init(repeating: .zero, count: 256), currentLuma: luma)) }
            let output = try XCTUnwrap(state.update(next, luma: luma, time: Double(frame)/30, generation: 1, requireRegistration: true))
            if frame > 3 { for i in truth.indices { before += abs(noisy[i]-truth[i]); after += abs(output.inverseDepth[i]-truth[i]) } }
        }
        XCTAssertLessThan(after, before * 0.8)
        print("SYNTHETIC temporal depth MAE ratio=\(after / before)")
        let cutLuma = [Float](repeating: 0.9, count: 256)
        XCTAssertFalse(state.alignHistory(backwardFlow: .init(repeating: .zero, count: 256), currentLuma: cutLuma))
        let cut = try XCTUnwrap(SoftwareDepthField(width: w, height: h, inverseDepth: truth, units: .relativeInverse))
        XCTAssertEqual(state.update(cut, luma: cutLuma, time: 1.1, generation: 1, requireRegistration: true)?.inverseDepth, truth)
    }
    func testRegistrationMustBeRenewedAndOcclusionIsNotAveraged() throws {
        let truth = (0..<100).map { Float($0) / 100 + 0.1 }
        let old = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: truth, units: .inverseMetres))
        let new = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: truth.map { $0 + 0.01 }, units: .inverseMetres))
        let luma = [Float](repeating: 0.5, count: 100)
        var state = DepthTemporalState()
        _ = state.update(old, luma: luma, time: 0, generation: 1, requireRegistration: true)
        XCTAssertEqual(state.update(new, luma: luma, time: 0.1, generation: 1, requireRegistration: true)?.inverseDepth, new.inverseDepth)
        XCTAssertTrue(state.alignHistory(backwardFlow: .init(repeating: .zero, count: 100), currentLuma: luma))
        var disocclusion = truth; disocclusion[45] = 3
        let next = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: disocclusion, units: .inverseMetres))
        let output = try XCTUnwrap(state.update(next, luma: luma, time: 0.2, generation: 1, requireRegistration: true))
        XCTAssertEqual(output.inverseDepth[45], 3)
        XCTAssertEqual(state.update(new, luma: luma, time: 0.3, generation: 1, requireRegistration: true)?.inverseDepth, new.inverseDepth)
    }

    func testCorrectionIsNonDestructiveBoundedAndUndoable() throws {
        let values = (0..<400).map { Float($0 % 20) / 20 + 0.1 }
        let field = try XCTUnwrap(SoftwareDepthField(width: 20, height: 20, inverseDepth: values, units: .relativeInverse))
        let stroke = DepthBrushStroke(points: [.init(x: 0.5,y: 0.5)], mode: .foreground, radius: 0.15, softness: 0.7)
        var history = DepthCorrectionHistory()
        XCTAssertTrue(history.append(stroke)); XCTAssertTrue(history.canUndo)
        let corrected = try XCTUnwrap(history.current.applying(to: field))
        XCTAssertEqual(field.inverseDepth, values)
        XCTAssertNil(history.current.applying(to: field,isCancelled: { true }),"Cancelled work cannot finish a partial correction")
        XCTAssertEqual(corrected.inverseDepth[0], values[0])
        XCTAssertGreaterThan(corrected.inverseDepth[10*20+10], values[10*20+10])
        XCTAssertEqual(corrected.bounds?.lower, field.bounds?.lower)
        XCTAssertEqual(corrected.bounds?.upper, field.bounds?.upper)
        XCTAssertTrue(corrected.inverseDepth.allSatisfy { $0 >= field.bounds!.lower && $0 <= max(field.bounds!.upper,values.max()!) })
        let saved = try JSONEncoder().encode(history.current)
        XCTAssertEqual(try JSONDecoder().decode(DepthCorrections.self,from: saved).applying(to: field)?.inverseDepth, corrected.inverseDepth)
        history.undo(); XCTAssertEqual(history.current.applying(to: field)?.inverseDepth, values)
        history.redo(); XCTAssertEqual(history.current.applying(to: field)?.inverseDepth, corrected.inverseDepth)
        var protected = stroke; protected.protectedRange = 0.1...1.1
        XCTAssertEqual(DepthCorrections(strokes: [protected]).applying(to: field)?.inverseDepth,values)
        var invalid = stroke; invalid.points = [.init(x: .nan,y: 0.5)]
        XCTAssertFalse(history.append(invalid)); XCTAssertFalse(DepthCorrections(strokes: [invalid]).valid)
    }
    func testBrushSoftEdgeAndInvalidDepthRequireExplicitStroke() throws {
        var values = (0..<400).map { Float($0 % 20)/20+0.1 }; values[210] = 0
        let field = try XCTUnwrap(SoftwareDepthField(width: 20,height: 20,inverseDepth: values,units: .relativeInverse))
        let edits = DepthCorrections(strokes: [.init(points: [.init(x: 0.525,y: 0.525)],mode: .foreground,radius: 0.15,softness: 1)])
        let output = try XCTUnwrap(edits.applying(to: field))
        XCTAssertEqual(output.inverseDepth[210], field.bounds!.upper,accuracy: 0.00001)
        XCTAssertEqual(output.inverseDepth[0], values[0])
        XCTAssertGreaterThan(output.inverseDepth[211],values[211]); XCTAssertLessThan(output.inverseDepth[211],field.bounds!.upper)
        XCTAssertFalse(DepthCorrections(strokes: Array(repeating: edits.strokes[0],count: 65)).valid)
    }

    func testVideoSmoothInterpolationIsOpticalAndLegacyRecipesHold() throws {
        let keys: [VideoDepthKeyframe] = [
            .init(time: 0,focus: CGPoint(x: 0.2,y: 0.4),aperture: 2,profile: .natural),
            .init(time: 2,focus: CGPoint(x: 0.8,y: 0.6),aperture: 8,profile: .natural)]
        var legacy = VideoDepthIntent(keyframes: keys); legacy.version = 1
        XCTAssertEqual(legacy.parameters(at: 1),keys[0])
        let old = try JSONDecoder().decode(VideoDepthIntent.self,from: JSONEncoder().encode(legacy))
        XCTAssertNil(old.interpolation); XCTAssertEqual(old.parameters(at: 1),keys[0]); XCTAssertTrue(old.valid)
        var invalidLegacy = old; invalidLegacy.interpolation = .smooth; XCTAssertFalse(invalidLegacy.valid)
        let animated = VideoDepthIntent(keyframes: keys,interpolation: .smooth)
        XCTAssertEqual(animated.version,2)
        let mid = try XCTUnwrap(animated.parameters(at: 1))
        XCTAssertEqual(mid.focus.x,0.5,accuracy: 1e-8); XCTAssertEqual(mid.aperture,3.2,accuracy: 1e-8)
        XCTAssertEqual(animated.parameters(at: 0)?.focus,keys[0].focus)
        XCTAssertEqual(animated.parameters(at: 2),keys[1])
        XCTAssertEqual(try JSONDecoder().decode(VideoDepthIntent.self,from: JSONEncoder().encode(animated)),animated)
        let values = (0..<256).map { Float($0 % 16 < 8 ? 2 : 1) }
        let field = try XCTUnwrap(SoftwareDepthField(width: 16,height: 16,inverseDepth: values,units: .inverseMetres))
        let plane = try XCTUnwrap(animated.focusTransition(at: 1)?.inverse(in: field))
        XCTAssertEqual(plane,1.5,accuracy: 1e-6)
        XCTAssertNotEqual(plane,field.focusValue(x: Double(mid.focus.x),y: Double(mid.focus.y)),"Actual focus plane must not step with the XY cursor")
        var last: Float = 2
        for step in 0...20 {
            let time = Double(step)/10
            let value = animated.focusTransition(at: time)?.inverse(in: field) ?? field.focusValue(x: 0.8,y: 0.6)!
            XCTAssertLessThanOrEqual(value,last+1e-6); last = value
        }
        var targetChange = keys
        targetChange[1].selection = .init(point: CGPoint(x: 0.8,y: 0.6),mode: .person)
        let safe = VideoDepthIntent(keyframes: targetChange,interpolation: .smooth)
        XCTAssertNil(safe.focusTransition(at: 1))
        XCTAssertEqual(safe.parameters(at: 1),keys[0],"New target must never be anticipated or interpolated")
    }

    func testSpatialPointEnergyStaysWithinDocumentedApproximation() throws {
        let w = 65
        var image = [SIMD3<Float>](repeating: .zero,count: w*w)
        image[16*w+16] = SIMD3(repeating: 8)
        var worst: Float = 0
        for profile in DepthLensProfile.allCases {
            let output = try XCTUnwrap(DepthLensKernel.reference(image,width: w,height: w,radius: 4,profile: profile,aperture: 8))
            let ratio = output.reduce(Float(0)) { $0+$1.x } / 8
            worst = max(worst,abs(ratio-1))
            XCTAssertEqual(ratio,1,accuracy: 0.03,"Spatial gather PSF is an energy-bounded approximation, not exact ray tracing: \(profile.rawValue)")
        }
        print("SYNTHETIC spatial point energy worst relative deviation=\(worst)")
    }

}
