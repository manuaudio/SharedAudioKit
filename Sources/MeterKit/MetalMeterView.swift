//
//  MetalMeterView.swift
//  MeterKit
//
//  GPU-accelerated K-System meter using Metal.
//  Triple-buffered rendering, zero allocations per frame.
//

#if os(macOS)
import SwiftUI
import MetalKit

// MARK: - Uniforms (must match MeterShaders.metal)

public struct MeterUniforms {
    public let level: Float
    public let peak: Float
    public let peakHold: Float
    public let meterHeight: Float
    public let kScale: Float
}

// MARK: - Metal Renderer

public final class MetalMeterRenderer: NSObject, MTKViewDelegate {

    public private(set) var device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let uniformBuffers: [MTLBuffer]
    private let inflightSemaphore = DispatchSemaphore(value: 3)
    private var bufferIndex = 0

    public var kScale: Float = 14.0

    /// The meter store to read data from during draw.
    public weak var meterStore: MeterStore?
    public var channelIndex: Int = 0
    private var peakHold: Float = 0.0

    public init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }

        self.device = device
        self.commandQueue = queue
        view.device = device

        let verts: [Float] = [
            -1, 1, 0, 1,   -1, -1, 0, 0,   1, 1, 1, 1,   1, -1, 1, 0
        ]
        guard let vb = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.stride, options: .storageModeShared) else { return nil }
        self.vertexBuffer = vb

        var ubs: [MTLBuffer] = []
        for _ in 0..<3 {
            guard let b = device.makeBuffer(length: MemoryLayout<MeterUniforms>.stride, options: .storageModeShared) else { return nil }
            ubs.append(b)
        }
        self.uniformBuffers = ubs

        view.colorPixelFormat = .bgra8Unorm

        // Load shader from package bundle
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module),
              let vtx = library.makeFunction(name: "meter_vertex"),
              let frag = library.makeFunction(name: "meter_fragment") else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vtx
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float2
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float2
        vd.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vd.attributes[1].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<Float>.stride * 4
        desc.vertexDescriptor = vd

        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let ps = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipelineState = ps

        super.init()

        view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)
        view.delegate = self
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        _ = inflightSemaphore.wait(timeout: .now() + .milliseconds(16))
        let idx = bufferIndex
        bufferIndex = (bufferIndex + 1) % 3

        // Read meter data directly during draw — no separate timer needed
        let norm = { (db: Float) -> Float in max(0, min(1, (db + 60) / 60)) }
        var level: Float = 0.0
        var peak: Float = 0.0
        if let store = meterStore {
            let data = store.getMeterData(channel: channelIndex)
            level = norm(data.rms)
            peak = norm(data.peak)
            let currentPeak = norm(data.peak)
            if currentPeak >= peakHold {
                peakHold = currentPeak
            } else {
                peakHold = max(0, peakHold - 1.0 / 45.0)
            }
        }

        let ub = uniformBuffers[idx]
        ub.contents().bindMemory(to: MeterUniforms.self, capacity: 1).pointee = MeterUniforms(
            level: level, peak: peak, peakHold: peakHold,
            meterHeight: Float(view.bounds.height), kScale: kScale
        )

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        cb.addCompletedHandler { [weak self] _ in self?.inflightSemaphore.signal() }

        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else {
            inflightSemaphore.signal()
            return
        }
        enc.setRenderPipelineState(pipelineState)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setFragmentBuffer(ub, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cb.present(drawable)
        cb.commit()
    }
}

// MARK: - SwiftUI Wrapper

public struct MetalMeterView: NSViewRepresentable {
    public let meterStore: MeterStore
    public let channelIndex: Int
    public let kScale: Float

    public init(meterStore: MeterStore, channelIndex: Int, kScale: Float = 14.0) {
        self.meterStore = meterStore
        self.channelIndex = channelIndex
        self.kScale = kScale
    }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        let renderer = MetalMeterRenderer(view: view)
        renderer?.meterStore = meterStore
        renderer?.channelIndex = channelIndex
        context.coordinator.renderer = renderer

        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.kScale = kScale
        context.coordinator.renderer?.channelIndex = channelIndex
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var renderer: MetalMeterRenderer?
    }
}
#endif
