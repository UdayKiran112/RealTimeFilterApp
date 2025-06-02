import UIKit
import MetalKit

class ViewController: UIViewController {
    var mtkView: MTKView!
    var cameraManager: CameraManager! // Your custom camera capture manager
    var filterRenderer: FilterRenderer!

    private var filterToggleButton: UIButton!
    private var isFilterOn = false

    override func viewDidLoad() {
        super.viewDidLoad()

        let device = MTLCreateSystemDefaultDevice()!
        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        view.addSubview(mtkView)

        filterRenderer = FilterRenderer(device: device, mtkView: mtkView)
        cameraManager = CameraManager(device: device)

        cameraManager.onTextureReady = { [weak self] texture in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.filterRenderer.filterEnabled = self.isFilterOn
                self.filterRenderer.draw(texture: texture, in: self.mtkView)
            }
        }

        cameraManager.startCapturing()
        setupFilterToggleButton()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopCapturing()
    }

    private func setupFilterToggleButton() {
        filterToggleButton = UIButton(type: .system)
        filterToggleButton.frame = CGRect(x: 20, y: view.safeAreaInsets.top + 20, width: 140, height: 44)
        filterToggleButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        filterToggleButton.setTitle("Filter: Off", for: .normal)
        filterToggleButton.setTitleColor(.white, for: .normal)
        filterToggleButton.layer.cornerRadius = 8
        filterToggleButton.addTarget(self, action: #selector(toggleFilter), for: .touchUpInside)
        view.addSubview(filterToggleButton)
    }

    @objc private func toggleFilter() {
        isFilterOn.toggle()
        filterToggleButton.setTitle(isFilterOn ? "Filter: On" : "Filter: Off", for: .normal)
    }
}
