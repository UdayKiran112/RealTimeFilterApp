import UIKit
import MetalKit

class ViewController: UIViewController, MTKViewDelegate {
    var mtkView: MTKView!
    var cameraManager: CameraManager!   // Your custom camera capture manager
    var filterRenderer: FilterRenderer! // Your filter rendering class

    private var filterButton: UIButton!
    private var selectedFilter: String = "None"
    private var currentCameraTexture: MTLTexture? = nil

    // Sync filters with FilterRenderer supported filters
    private let filters = [
        "None",
        "Gaussian Blur",
        "Edge Detection"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup Metal device and MTKView
        let device = MTLCreateSystemDefaultDevice()!
        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.delegate = self
        view.addSubview(mtkView)

        // Initialize FilterRenderer and CameraManager with Metal device and MTKView
        filterRenderer = FilterRenderer(device: device, mtkView: mtkView)
        cameraManager = CameraManager(device: device)

        // Setup callback when camera frame texture is ready
        cameraManager.onTextureReady = { [weak self] texture in
            guard let self = self else { return }
            // Store the latest camera texture and trigger view redraw on main thread
            DispatchQueue.main.async {
                self.currentCameraTexture = texture
                self.mtkView.setNeedsDisplay()
            }
        }

        cameraManager.startCapturing()

        setupFilterButton()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopCapturing()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateFilterButtonFrame()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFilterButtonFrame()
    }

    private func setupFilterButton() {
        filterButton = UIButton(type: .system)
        filterButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        filterButton.setTitle("Filter: \(selectedFilter)", for: .normal)
        filterButton.setTitleColor(.white, for: .normal)
        filterButton.layer.cornerRadius = 8
        filterButton.addTarget(self, action: #selector(showFilterDropdown), for: .touchUpInside)

        view.addSubview(filterButton)
        updateFilterButtonFrame()
    }

    private func updateFilterButtonFrame() {
        let buttonWidth: CGFloat = 180
        let buttonHeight: CGFloat = 44
        let bottomPadding: CGFloat = 20
        let safeAreaBottom = view.safeAreaInsets.bottom

        filterButton.frame = CGRect(
            x: 20,
            y: view.bounds.height - buttonHeight - bottomPadding - safeAreaBottom,
            width: buttonWidth,
            height: buttonHeight
        )
    }

    @objc private func showFilterDropdown() {
        let alert = UIAlertController(title: "Select Filter", message: nil, preferredStyle: .actionSheet)

        for filter in filters {
            let action = UIAlertAction(title: filter, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.selectedFilter = filter
                self.filterButton.setTitle("Filter: \(filter)", for: .normal)

                // Update filter on FilterRenderer for next draw
                self.filterRenderer.setFilter(name: filter)

                // Trigger redraw to reflect filter change immediately
                self.mtkView.setNeedsDisplay()
            }
            alert.addAction(action)
        }

        // Add cancel button
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // For iPad support, present as popover from button
        if let popover = alert.popoverPresentationController {
            popover.sourceView = filterButton
            popover.sourceRect = filterButton.bounds
        }

        present(alert, animated: true)
    }

    // MARK: - MTKViewDelegate Methods

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size or orientation changes here if needed
    }

    func draw(in view: MTKView) {
        guard let texture = currentCameraTexture,
              let drawable = view.currentDrawable else { return }

        // Render current camera texture with the selected filter
        guard let drawable = view.currentDrawable else { return }
        filterRenderer.render(inputTexture: texture, drawable: drawable)
        // Present drawable handled inside filterRenderer or here if needed
    }
}
