import Foundation
import Metal

// Immutable pipeline states may be shared. Buffers/textures remain renderer-owned.
final class MetalPipelineCache: @unchecked Sendable {
    static let shared = MetalPipelineCache()
    private let lock = NSLock()
    private var states: [String: MTLComputePipelineState] = [:]
    func compute(_ name: String, device: MTLDevice) throws -> MTLComputePipelineState {
        try lock.withLock {
            let key = "\(device.registryID):\(name)"
            if let state = states[key] { return state }
            guard let function = device.makeDefaultLibrary()?.makeFunction(name: name) else { throw MetalLUTError.unavailable }
            let state = try device.makeComputePipelineState(function: function)
            states[key] = state
            return state
        }
    }
}
