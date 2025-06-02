import MetalKit

class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    
    // The texture to draw, can be nil for just clear screen
    var currentTexture: MTLTexture? = nil
    
    init(mtkView: MTKView) {
        guard let device = mtkView.device else {
            fatalError("MTKView has no Metal device assigned")
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        
        super.init()
        
        buildPipeline(mtkView: mtkView)
    }
    
    func buildPipeline(mtkView: MTKView) {
        let library = device.makeDefaultLibrary()!
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            fatalError("Failed to find shader functions in the default library")
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle drawable size change here if needed (e.g., update viewport or textures)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        // Create command buffer and encoder
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Bind texture if available
        if let texture = currentTexture {
            renderEncoder.setFragmentTexture(texture, index: 0)
        }
        
        // Draw fullscreen quad with 4 vertices (triangle strip)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
