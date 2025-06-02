import MetalKit

class FilterRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue
    private let vertexBuffer: MTLBuffer
    private let samplerState: MTLSamplerState

    // This bool controls whether to apply the filter or not
    var filterEnabled: Bool = false

    // Buffer to send the filterEnabled flag to the shader
    private var filterEnabledBuffer: MTLBuffer

    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        // Quad vertices: position.xy, texCoord.xy
        let vertices: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0,
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: [])!

        // Create sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)!

        // Buffer for filter flag
        var filterFlag = false
        filterEnabledBuffer = device.makeBuffer(bytes: &filterFlag, length: MemoryLayout<Bool>.size, options: [])!

        // Load shader functions
        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "vertex_passthrough")!
        let fragmentFunc = library.makeFunction(name: "fragment_filter")!

        // Setup vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        // Pipeline setup
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    func draw(texture: MTLTexture, in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Update filter flag buffer
        var enabled = filterEnabled
        memcpy(filterEnabledBuffer.contents(), &enabled, MemoryLayout<Bool>.size)
        encoder.setFragmentBuffer(filterEnabledBuffer, offset: 0, index: 0)

        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
