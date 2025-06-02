import Metal
import MetalKit
import simd

class FilterRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    let vertexDescriptor: MTLVertexDescriptor

    private(set) var pipelineState: MTLRenderPipelineState!
    private(set) var computePipelineBlurH: MTLComputePipelineState!
    private(set) var computePipelineBlurV: MTLComputePipelineState!
    private(set) var computePipelineSobel: MTLComputePipelineState!

    private var time: Float = 0

    private var intermediateTexture: MTLTexture!
    private var outputTexture: MTLTexture!

    private var viewportSize: vector_uint2 = [0, 0]

    enum FilterType {
        case none
        case gaussianBlur
        case edgeDetection
        case vertexWarp      // mesh warp + sine displacement in vertex shader
        case colorEffects    // chromatic aberration, tone mapping, grain, vignette in fragment shader
    }

    private var currentFilter: FilterType = .none

    private var quadVertexBuffer: MTLBuffer!
    private let samplerState: MTLSamplerState

    private let quadVertices: [Float] = [
        -1, -1,  0, 1,
         1, -1,  1, 1,
        -1,  1,  0, 0,
         1,  1,  1, 0,
    ]

    var filterEnabled: Bool {
        get { currentFilter != .none }
        set {
            if !newValue { currentFilter = .none }
        }
    }

    init?(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        self.viewportSize = vector_uint2(UInt32(mtkView.drawableSize.width), UInt32(mtkView.drawableSize.height))

        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let bufferSize = quadVertices.count * MemoryLayout<Float>.size
        quadVertexBuffer = device.makeBuffer(bytes: quadVertices, length: bufferSize, options: [])

        samplerState = FilterRenderer.makeDefaultSampler(device: device)

        buildPipeline(mtkView: mtkView)
        createIntermediateTextures(size: mtkView.drawableSize)
    }

    func buildPipeline(mtkView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }

        // Your vertex and fragment functions (vertexWarp + fragmentEffects)
        guard let vertexFunc = library.makeFunction(name: "vertexWarp"),
              let fragmentFunc = library.makeFunction(name: "fragmentEffects") else {
            fatalError("Failed to find vertexWarp or fragmentEffects function")
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDesc.vertexDescriptor = vertexDescriptor

        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDesc)

        computePipelineBlurH = try! device.makeComputePipelineState(function: library.makeFunction(name: "gaussianBlurHorizontal")!)
        computePipelineBlurV = try! device.makeComputePipelineState(function: library.makeFunction(name: "gaussianBlurVertical")!)
        computePipelineSobel = try! device.makeComputePipelineState(function: library.makeFunction(name: "sobelEdgeDetection")!)
    }

    func createIntermediateTextures(size: CGSize) {
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                               width: Int(size.width),
                                                               height: Int(size.height),
                                                               mipmapped: false)
        texDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]

        intermediateTexture = device.makeTexture(descriptor: texDesc)
        outputTexture = device.makeTexture(descriptor: texDesc)
    }

    func resize(size: CGSize) {
        viewportSize = vector_uint2(UInt32(size.width), UInt32(size.height))
        createIntermediateTextures(size: size)
    }

    func setFilter(name: String) {
        switch name.lowercased() {
            case "none":
                currentFilter = .none
            case "gaussian blur", "blur", "gaussian":
                currentFilter = .gaussianBlur
            case "edge detection", "sobel", "edges":
                currentFilter = .edgeDetection
            case "vertexwarp", "vertex warp":
                currentFilter = .vertexWarp
            case "color effects", "coloreffects", "color effect":
                currentFilter = .colorEffects
            default:
                currentFilter = .none
        }
    }

    func applyComputeFilters(inputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        func makeThreadgroupSizes(for pipeline: MTLComputePipelineState, texture: MTLTexture) -> (MTLSize, MTLSize) {
            let w = pipeline.threadExecutionWidth
            let h = max(pipeline.maxTotalThreadsPerThreadgroup / w, 1)
            let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
            let threadsPerGrid = MTLSizeMake(texture.width, texture.height, 1)
            return (threadsPerGrid, threadsPerThreadgroup)
        }

        switch currentFilter {
        case .gaussianBlur:
            // Horizontal blur pass
            if let encoderH = commandBuffer.makeComputeCommandEncoder() {
                encoderH.setComputePipelineState(computePipelineBlurH)
                encoderH.setTexture(inputTexture, index: 0)
                encoderH.setTexture(intermediateTexture, index: 1)

                let (threadsPerGrid, threadsPerThreadgroup) = makeThreadgroupSizes(for: computePipelineBlurH, texture: intermediateTexture)
                encoderH.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                encoderH.endEncoding()
            }

            // Vertical blur pass
            if let encoderV = commandBuffer.makeComputeCommandEncoder() {
                encoderV.setComputePipelineState(computePipelineBlurV)
                encoderV.setTexture(intermediateTexture, index: 0)
                encoderV.setTexture(outputTexture, index: 1)

                let (threadsPerGrid, threadsPerThreadgroup) = makeThreadgroupSizes(for: computePipelineBlurV, texture: outputTexture)
                encoderV.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                encoderV.endEncoding()
            }

            return outputTexture

        case .edgeDetection:
            // Gaussian blur first for smoothing
            if let encoderH = commandBuffer.makeComputeCommandEncoder() {
                encoderH.setComputePipelineState(computePipelineBlurH)
                encoderH.setTexture(inputTexture, index: 0)
                encoderH.setTexture(intermediateTexture, index: 1)

                let (threadsPerGrid, threadsPerThreadgroup) = makeThreadgroupSizes(for: computePipelineBlurH, texture: intermediateTexture)
                encoderH.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                encoderH.endEncoding()
            }
            if let encoderV = commandBuffer.makeComputeCommandEncoder() {
                encoderV.setComputePipelineState(computePipelineBlurV)
                encoderV.setTexture(intermediateTexture, index: 0)
                encoderV.setTexture(outputTexture, index: 1)

                let (threadsPerGrid, threadsPerThreadgroup) = makeThreadgroupSizes(for: computePipelineBlurV, texture: outputTexture)
                encoderV.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                encoderV.endEncoding()
            }

            // Edge detection pass
            if let encoderSobel = commandBuffer.makeComputeCommandEncoder() {
                encoderSobel.setComputePipelineState(computePipelineSobel)
                encoderSobel.setTexture(outputTexture, index: 0)
                encoderSobel.setTexture(intermediateTexture, index: 1)

                let (threadsPerGrid, threadsPerThreadgroup) = makeThreadgroupSizes(for: computePipelineSobel, texture: intermediateTexture)
                encoderSobel.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                encoderSobel.endEncoding()
            }

            return intermediateTexture

        case .vertexWarp, .colorEffects:
            // For these filters, no compute pass needed —
            // We'll render with vertex + fragment shaders directly later.
            return inputTexture

        case .none:
            return inputTexture
        }
    }

    func render(inputTexture: MTLTexture, drawable: CAMetalDrawable) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        time += 0.016 // approx 60 FPS

        // First, apply compute filters if any
        let filteredTexture = applyComputeFilters(inputTexture: inputTexture, commandBuffer: commandBuffer)

        // For vertexWarp and colorEffects, we render with vertex + fragment shaders using pipelineState
        if currentFilter == .vertexWarp || currentFilter == .colorEffects {
            let renderPassDesc = MTLRenderPassDescriptor()
            renderPassDesc.colorAttachments[0].texture = drawable.texture
            renderPassDesc.colorAttachments[0].loadAction = .clear
            renderPassDesc.colorAttachments[0].storeAction = .store
            renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            // <<< Fix: Pass time uniform to vertex shader at buffer index 2
            var currentTime = time
            renderEncoder.setVertexBytes(&currentTime, length: MemoryLayout<Float>.size, index: 2)

            renderEncoder.setFragmentTexture(filteredTexture, index: 0)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)

            // Pass time as fragment shader uniform as well (for colorEffects)
            renderEncoder.setFragmentBytes(&currentTime, length: MemoryLayout<Float>.size, index: 0)

            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            renderEncoder.endEncoding()
        } else {
            // For other filters or none, just copy filteredTexture to drawable directly with a blit or simple render pass

            // We'll do a simple render pass with a basic pipeline (not shown here for brevity)
            // For now, just copy via blit command encoder
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(from: filteredTexture,
                                 sourceSlice: 0,
                                 sourceLevel: 0,
                                 sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                                 sourceSize: MTLSize(width: filteredTexture.width,
                                                     height: filteredTexture.height,
                                                     depth: 1),
                                 to: drawable.texture,
                                 destinationSlice: 0,
                                 destinationLevel: 0,
                                 destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blitEncoder.endEncoding()
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    static func makeDefaultSampler(device: MTLDevice) -> MTLSamplerState {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .notMipmapped
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: desc)!
    }
}
