import Metal
import MetalKit
import simd

// Must exactly match the `Uniforms` struct in your shaders.metal
struct Uniforms {
    var time: Float
    var resolution: SIMD2<Float>
    var mouse: SIMD2<Float>
    var center: SIMD2<Float>
    var radius: Float
    var aspectRatio: Float
    var brightness: Float
    var contrast: Float
    var vignetteStrength: Float
    var filterIndex: Int32
    var warpIndex: Int32
}

class FilterRenderer {
    private let device: MTLDevice
    private let mtkView: MTKView
    private let commandQueue: MTLCommandQueue

    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var samplerState: MTLSamplerState!
    
    // Compute pipeline states for filters that need them
    private var gaussianBlurHorizontalState: MTLComputePipelineState?
    private var gaussianBlurVerticalState: MTLComputePipelineState?
    private var sobelEdgeDetectionState: MTLComputePipelineState?
    
    // Temporary textures for multi-pass effects
    private var tempTexture1: MTLTexture?
    private var tempTexture2: MTLTexture?

    // Vertex data for a full-screen quad: position (float4) + texCoord (float2)
    private let vertices: [Float] = [
        -1,  1, 0, 1,   0, 0,
        -1, -1, 0, 1,   0, 1,
         1, -1, 0, 1,   1, 1,
        -1,  1, 0, 1,   0, 0,
         1, -1, 0, 1,   1, 1,
         1,  1, 0, 1,   1, 0,
    ]

    // Runtime-controlled filter/wave modes and filter parameters
    private var filterIndex: Int32 = 0
    private var warpMode: Int32 = 0
    private var brightness: Float = 1.0
    private var contrast: Float = 1.0
    private var vignetteStrength: Float = 0.6

    // Magnify warp settings
    private var magnifyCenter = SIMD2<Float>(0.5, 0.5)
    private var magnifyRadius: Float = 0.2
    private var magnifyStrength: Float = 0.2

    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.mtkView = mtkView

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue

        buildPipeline()
        buildComputePipelines()
        buildVertexBuffer()
        buildSampler()
    }

    // MARK: - Public Setters

    func setFilter(index: Int32) {
        filterIndex = index
    }

    func setWarpMode(_ mode: Int32) {
        warpMode = mode
    }

    func setBrightness(_ value: Float) {
        brightness = value
    }

    func setContrast(_ value: Float) {
        contrast = value
    }

    func setVignetteStrength(_ value: Float) {
        vignetteStrength = value
    }

    func setMagnifyCenter(_ center: SIMD2<Float>) {
        magnifyCenter = center
    }

    func setMagnifyRadius(_ radius: Float) {
        magnifyRadius = radius
    }

    func setMagnifyStrength(_ strength: Float) {
        magnifyStrength = strength
    }

    // MARK: - Drawing

    func draw(in view: MTKView, inputTexture: MTLTexture) {
        print("Filter index:", filterIndex)
        print("Warp mode:", warpMode)
        print("Brightness:", brightness, "Contrast:", contrast, "Vignette:", vignetteStrength)

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        var finalTexture = inputTexture
        
        // Handle compute shader filters first
        if filterIndex == 10 { // Gaussian Blur
            finalTexture = applyGaussianBlur(to: inputTexture) ?? inputTexture
        } else if filterIndex == 11 { // Edge Detection
            finalTexture = applyEdgeDetection(to: inputTexture) ?? inputTexture
        }

        // Now render with the regular pipeline
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Prepare uniforms to match the shader's struct layout
        let resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let aspectRatio = resolution.x / resolution.y
        let time = Float(CACurrentMediaTime())
        let mouse = SIMD2<Float>(0, 0) // Update with touch input if available

        var uniforms = Uniforms(
            time: time,
            resolution: resolution,
            mouse: mouse,
            center: magnifyCenter,
            radius: magnifyRadius,
            aspectRatio: aspectRatio,
            brightness: brightness,
            contrast: contrast,
            vignetteStrength: vignetteStrength,
            filterIndex: filterIndex,
            warpIndex: warpMode
        )

        // Set pipeline and buffers
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Set uniform struct for both vertex and fragment shaders at buffer index 1
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Set input texture and sampler for fragment shader
        renderEncoder.setFragmentTexture(finalTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Draw full-screen quad
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Compute Shader Methods
    
    private func createTempTexturesIfNeeded(width: Int, height: Int) {
        if tempTexture1 == nil || tempTexture1!.width != width || tempTexture1!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            tempTexture1 = device.makeTexture(descriptor: descriptor)
            tempTexture2 = device.makeTexture(descriptor: descriptor)
        }
    }
    
    private func applyGaussianBlur(to texture: MTLTexture) -> MTLTexture? {
        guard let horizontalState = gaussianBlurHorizontalState,
              let verticalState = gaussianBlurVerticalState else { return nil }
        
        createTempTexturesIfNeeded(width: texture.width, height: texture.height)
        guard let temp1 = tempTexture1, let temp2 = tempTexture2 else { return nil }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        
        // Horizontal pass
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(horizontalState)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(temp1, index: 1)
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let numGroups = MTLSize(
                width: (texture.width + 15) / 16,
                height: (texture.height + 15) / 16,
                depth: 1
            )
            encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
        
        // Vertical pass
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(verticalState)
            encoder.setTexture(temp1, index: 0)
            encoder.setTexture(temp2, index: 1)
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let numGroups = MTLSize(
                width: (texture.width + 15) / 16,
                height: (texture.height + 15) / 16,
                depth: 1
            )
            encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return temp2
    }
    
    private func applyEdgeDetection(to texture: MTLTexture) -> MTLTexture? {
        guard let edgeDetectionState = sobelEdgeDetectionState else { return nil }
        
        createTempTexturesIfNeeded(width: texture.width, height: texture.height)
        guard let temp1 = tempTexture1 else { return nil }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(edgeDetectionState)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(temp1, index: 1)
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let numGroups = MTLSize(
                width: (texture.width + 15) / 16,
                height: (texture.height + 15) / 16,
                depth: 1
            )
            encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return temp1
    }

    // MARK: - Setup helpers

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load default Metal library")
        }

        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            fatalError("Failed to load shader functions")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        let vertexDescriptor = MTLVertexDescriptor()
        // Position attribute (float4)
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Texture coordinate attribute (float2)
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 4
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Layout stride = 6 floats (4 pos + 2 uv)
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 6

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
    
    private func buildComputePipelines() {
        guard let library = device.makeDefaultLibrary() else { return }
        
        do {
            if let function = library.makeFunction(name: "gaussianBlurHorizontal") {
                gaussianBlurHorizontalState = try device.makeComputePipelineState(function: function)
            }
            if let function = library.makeFunction(name: "gaussianBlurVertical") {
                gaussianBlurVerticalState = try device.makeComputePipelineState(function: function)
            }
            if let function = library.makeFunction(name: "sobelEdgeDetection") {
                sobelEdgeDetectionState = try device.makeComputePipelineState(function: function)
            }
        } catch {
            print("Failed to create compute pipeline states: \(error)")
        }
    }

    private func buildVertexBuffer() {
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: [])
    }

    private func buildSampler() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
}
