import UIKit
import MetalKit

class ViewController: UIViewController {
    var mtkView: MTKView!
    var renderer: MetalRenderer!
    var cameraManager: CameraManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.clearColor = MTLClearColorMake(0.2, 0.2, 0.25, 1.0) // dark blue background
        view.addSubview(mtkView)

        renderer = MetalRenderer(mtkView: mtkView)
        mtkView.delegate = renderer

        cameraManager = CameraManager(device: device)
        cameraManager.onTextureReady = { [weak self] texture in
            self?.renderer.currentTexture = texture
        }

        cameraManager.startCapturing()
    }
}
