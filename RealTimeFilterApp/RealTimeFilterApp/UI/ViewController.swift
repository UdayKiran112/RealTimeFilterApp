import UIKit
import MetalKit

class ViewController: UIViewController, MTKViewDelegate {

    var mtkView: MTKView!
    var cameraManager: CameraManager!
    var filterRenderer: FilterRenderer!

    private var filterButton: UIButton!
    private var warpSegmentedControl: UISegmentedControl!
    private var brightnessSlider: UISlider!
    private var contrastSlider: UISlider!
    private var vignetteSlider: UISlider!
    private var magnifySlider: UISlider!

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

        setupUI()

        // Apply default filter and warp mode
        filterRenderer.setFilter(index: selectedFilterIndex)
        filterRenderer.setWarpMode(selectedWarpIndex)
        
        // Set initial values for all parameters
        filterRenderer.setBrightness(1.0)
        filterRenderer.setContrast(1.0)
        filterRenderer.setVignetteStrength(0.6)
        filterRenderer.setMagnifyStrength(0.2)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopCapturing()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        setupFilterButton()
        setupWarpSegmentedControl()
        setupSliders()
        setupTapGesture()
    }

    private func setupFilterButton() {
        filterButton = UIButton(type: .system)
        filterButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        filterButton.setTitle("Filter: \(filters[Int(selectedFilterIndex)])", for: .normal)
        filterButton.setTitleColor(.white, for: .normal)
        filterButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        filterButton.layer.cornerRadius = 8
        filterButton.addTarget(self, action: #selector(showFilterDropdown), for: .touchUpInside)
        filterButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(filterButton)
    }

    private func setupWarpSegmentedControl() {
        warpSegmentedControl = UISegmentedControl(items: warpModes)
        warpSegmentedControl.selectedSegmentIndex = Int(selectedWarpIndex)
        warpSegmentedControl.addTarget(self, action: #selector(warpModeChanged), for: .valueChanged)
        warpSegmentedControl.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        warpSegmentedControl.selectedSegmentTintColor = UIColor.white
        warpSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        warpSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        warpSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(warpSegmentedControl)
    }

    private func setupSliders() {
        // Brightness Slider
        let brightnessLabel = createLabel(text: "Brightness")
        brightnessSlider = createSlider(minValue: 0.1, maxValue: 3.0, initialValue: 1.0)
        brightnessSlider.addTarget(self, action: #selector(brightnessChanged), for: .valueChanged)

        // Contrast Slider
        let contrastLabel = createLabel(text: "Contrast")
        contrastSlider = createSlider(minValue: 0.1, maxValue: 3.0, initialValue: 1.0)
        contrastSlider.addTarget(self, action: #selector(contrastChanged), for: .valueChanged)

        // Vignette Slider
        let vignetteLabel = createLabel(text: "Vignette")
        vignetteSlider = createSlider(minValue: 0.0, maxValue: 1.0, initialValue: 0.6)
        vignetteSlider.addTarget(self, action: #selector(vignetteChanged), for: .valueChanged)

        // Magnify Slider
        let magnifyLabel = createLabel(text: "Magnify Strength")
        magnifySlider = createSlider(minValue: 0.0, maxValue: 1.0, initialValue: 0.2)
        magnifySlider.addTarget(self, action: #selector(magnifyChanged), for: .valueChanged)

        // Add sliders and labels to view
        let stackView = UIStackView(arrangedSubviews: [
            brightnessLabel, brightnessSlider,
            contrastLabel, contrastSlider,
            vignetteLabel, vignetteSlider,
            magnifyLabel, magnifySlider
        ])
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)

        // Store reference for layout
        stackView.tag = 100
    }

    private func createLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        return label
    }

    private func createSlider(minValue: Float, maxValue: Float, initialValue: Float) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = minValue
        slider.maximumValue = maxValue
        slider.value = initialValue
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .gray
        slider.thumbTintColor = .white
        return slider
    }

    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        mtkView.addGestureRecognizer(tapGesture)
    }

    private func layoutUI() {
        let safeArea = view.safeAreaLayoutGuide
        
        // Filter button constraints
        NSLayoutConstraint.activate([
            filterButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20),
            filterButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            filterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            filterButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Warp control constraints
        NSLayoutConstraint.activate([
            warpSegmentedControl.topAnchor.constraint(equalTo: filterButton.bottomAnchor, constant: 10),
            warpSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            warpSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            warpSegmentedControl.heightAnchor.constraint(equalToConstant: 32)
        ])

        // Slider stack view constraints
        if let stackView = view.viewWithTag(100) {
            NSLayoutConstraint.activate([
                stackView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -20),
                stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
            ])
        }
    }

    // MARK: - Actions

    @objc private func showFilterDropdown() {
        let alertController = UIAlertController(title: "Select Filter", message: nil, preferredStyle: .actionSheet)

        for (index, filterName) in filters.enumerated() {
            let action = UIAlertAction(title: filterName, style: .default) { [weak self] _ in
                self?.applyFilter(index: Int32(index))
            }
            // Mark current selection
            if index == selectedFilterIndex {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alertController.addAction(cancelAction)

        // For iPad support
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = filterButton
            popover.sourceRect = filterButton.bounds
        }

        present(alertController, animated: true)
    }

    @objc private func warpModeChanged() {
        selectedWarpIndex = Int32(warpSegmentedControl.selectedSegmentIndex)
        filterRenderer.setWarpMode(selectedWarpIndex)
    }

    @objc private func brightnessChanged() {
        print("Brightness changed to: \(brightnessSlider.value)")
        filterRenderer.setBrightness(brightnessSlider.value)
    }

    @objc private func contrastChanged() {
        print("Contrast changed to: \(contrastSlider.value)")
        filterRenderer.setContrast(contrastSlider.value)
    }

    @objc private func vignetteChanged() {
        print("Vignette changed to: \(vignetteSlider.value)")
        filterRenderer.setVignetteStrength(vignetteSlider.value)
    }

    @objc private func magnifyChanged() {
        print("Magnify strength changed to: \(magnifySlider.value)")
        filterRenderer.setMagnifyStrength(magnifySlider.value)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Handle tap for magnify effect center
        if selectedWarpIndex == 2 { // Magnify mode
            let location = gesture.location(in: mtkView)
            let normalizedX = Float(location.x / mtkView.bounds.width)
            let normalizedY = Float(1.0 - (location.y / mtkView.bounds.height)) // Flip Y
            
            print("Setting magnify center to: \(normalizedX), \(normalizedY)")
            filterRenderer.setMagnifyCenter(SIMD2<Float>(normalizedX, normalizedY))
        }
    }

    private func applyFilter(index: Int32) {
        selectedFilterIndex = index
        print("Applying filter index: \(index)")
        filterRenderer.setFilter(index: index)
        filterButton.setTitle("Filter: \(filters[Int(index)])", for: .normal)
        
        // Reset sliders to their current values to ensure they work with the new filter
        filterRenderer.setBrightness(brightnessSlider.value)
        filterRenderer.setContrast(contrastSlider.value)
        filterRenderer.setVignetteStrength(vignetteSlider.value)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle drawable size changes if needed
    }

    func draw(in view: MTKView) {
        guard let texture = currentCameraTexture else { return }
        filterRenderer.draw(in: view, inputTexture: texture)
    }
}
