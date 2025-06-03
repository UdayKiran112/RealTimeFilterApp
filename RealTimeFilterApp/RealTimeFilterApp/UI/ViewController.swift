import UIKit
import MetalKit

class ViewController: UIViewController, MTKViewDelegate {

    var mtkView: MTKView!
    var cameraManager: CameraManager!
    var filterRenderer: FilterRenderer!

    private var filterButton: UIButton!
    private var warpSegmentedControl: UISegmentedControl!

    private var selectedFilterIndex: Int32 = 0
    private var selectedWarpIndex: Int32 = 0
    private var currentCameraTexture: MTLTexture? = nil

    private let filters = [
        "None", "Grayscale", "Invert", "Sepia",
        "Brightness", "Contrast", "Tone Mapping",
        "Chromatic Aberration", "Film Grain", "Vignette",
        "Gaussian Blur", "Edge Detection"
    ]

    private let warpModes = ["None", "Sine Wave", "Magnify"]

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        // Setup MetalKit View
        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.delegate = self
        view.addSubview(mtkView)

        // Initialize Renderer & Camera
        filterRenderer = FilterRenderer(device: device, mtkView: mtkView)
        cameraManager = CameraManager(device: device)

        // Pass texture from camera to MTKView
        cameraManager.onTextureReady = { [weak self] texture in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.currentCameraTexture = texture
                self.mtkView.setNeedsDisplay()
            }
        }

        cameraManager.startCapturing()

        setupFilterButton()
        setupWarpSegmentedControl()

        // Apply default filter and warp mode
        filterRenderer.setFilter(index: selectedFilterIndex)
        filterRenderer.setWarpMode(selectedWarpIndex)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopCapturing()
    }

    // MARK: - UI Setup

    private func setupFilterButton() {
        filterButton = UIButton(type: .system)
        filterButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        filterButton.setTitle("Filter: \(filters[Int(selectedFilterIndex)])", for: .normal)
        filterButton.setTitleColor(.white, for: .normal)
        filterButton.layer.cornerRadius = 8
        filterButton.addTarget(self, action: #selector(showFilterDropdown), for: .touchUpInside)

        view.addSubview(filterButton)
        updateFilterButtonFrame()
    }

    private func setupWarpSegmentedControl() {
        warpSegmentedControl = UISegmentedControl(items: warpModes)
        warpSegmentedControl.selectedSegmentIndex = Int(selectedWarpIndex)
        warpSegmentedControl.addTarget(self, action: #selector(warpModeChanged), for: .valueChanged)
        warpSegmentedControl.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        warpSegmentedControl.tintColor = .white

        view.addSubview(warpSegmentedControl)
        updateWarpSegmentedControlFrame()
    }

    // MARK: - Layout Adjustments

    private func updateFilterButtonFrame() {
        let buttonWidth: CGFloat = 200
        let buttonHeight: CGFloat = 40
        let margin: CGFloat = 16
        let safeInsets = view.safeAreaInsets

        filterButton.frame = CGRect(
            x: view.bounds.width - buttonWidth - margin,
            y: view.bounds.height - buttonHeight - margin - safeInsets.bottom,
            width: buttonWidth,
            height: buttonHeight
        )
    }

    private func updateWarpSegmentedControlFrame() {
        let width: CGFloat = 280
        let height: CGFloat = 30
        let margin: CGFloat = 16
        let safeInsets = view.safeAreaInsets

        warpSegmentedControl.frame = CGRect(
            x: view.bounds.width - width - margin,
            y: view.bounds.height - height - margin - safeInsets.bottom - 50,
            width: width,
            height: height
        )
    }

    // MARK: - UI Actions

    @objc private func warpModeChanged() {
        selectedWarpIndex = Int32(warpSegmentedControl.selectedSegmentIndex)
        filterRenderer.setWarpMode(selectedWarpIndex)
        mtkView.setNeedsDisplay()
    }

    @objc private func showFilterDropdown() {
        let alert = UIAlertController(title: "Choose Filter", message: nil, preferredStyle: .actionSheet)

        for (index, filterName) in filters.enumerated() {
            alert.addAction(UIAlertAction(title: filterName, style: .default, handler: { _ in
                self.selectedFilterIndex = Int32(index)
                self.filterButton.setTitle("Filter: \(filterName)", for: .normal)
                self.filterRenderer.setFilter(index: self.selectedFilterIndex)
                self.mtkView.setNeedsDisplay()
            }))
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        // iPad-safe
        if let popover = alert.popoverPresentationController {
            popover.sourceView = filterButton
            popover.sourceRect = filterButton.bounds
        }

        present(alert, animated: true, completion: nil)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//        filterRenderer.resize(size: size)
        updateFilterButtonFrame()
        updateWarpSegmentedControlFrame()
    }

    func draw(in view: MTKView) {
        guard let texture = currentCameraTexture else { return }
        filterRenderer.draw(in: view, inputTexture: texture)
    }
}
