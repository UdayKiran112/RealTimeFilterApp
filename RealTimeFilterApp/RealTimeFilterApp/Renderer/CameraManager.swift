import AVFoundation
import Metal
import UIKit

/// Manages camera capture and provides Metal textures for real-time processing.
class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let device: MTLDevice
    var onTextureReady: ((MTLTexture) -> Void)?
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let textureCache: CVMetalTextureCache
    private var isSessionRunning = false
    
    // MARK: - Init
    
    init?(device: MTLDevice) {
        self.device = device
        
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let createdCache = cache else {
            print("Failed to create CVMetalTextureCache")
            return nil
        }
        self.textureCache = createdCache
        
        super.init()
        
        checkPermissionAndSetup()
        addOrientationObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    // MARK: - Permission & Setup
    
    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCaptureSession()
                    }
                } else {
                    print("Camera permission denied")
                }
            }
        case .denied, .restricted:
            print("Camera access denied or restricted")
        @unknown default:
            print("Unknown authorization status")
        }
    }
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        
        // Configure session preset (optional, choose based on performance/quality needs)
        captureSession.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("Error: No video camera available")
            captureSession.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                print("Cannot add camera input to capture session")
                captureSession.commitConfiguration()
                return
            }
            
            // Limit frame rate to 30 FPS for performance (optional)
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            camera.unlockForConfiguration()
            
        } catch {
            print("Error setting up camera input: \(error.localizedDescription)")
            captureSession.commitConfiguration()
            return
        }
        
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        let queue = DispatchQueue(label: "CameraOutputQueue")
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("Cannot add video output")
            captureSession.commitConfiguration()
            return
        }
        
        updateVideoOrientation()
        
        captureSession.commitConfiguration()
    }
    
    // MARK: - Orientation
    
    private func addOrientationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
    
    @objc private func deviceOrientationDidChange() {
        updateVideoOrientation()
    }
    
    private func updateVideoOrientation() {
        guard let connection = videoOutput.connection(with: .video),
              connection.isVideoOrientationSupported else {
            return
        }
        
        let deviceOrientation = UIDevice.current.orientation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch deviceOrientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeRight  // compensates for camera rotation
        case .landscapeRight:
            videoOrientation = .landscapeLeft   // compensates for camera rotation
        default:
            return
        }
        
        connection.videoOrientation = videoOrientation
    }
    
    // MARK: - Capture Control
    
    func startCapturing() {
        guard !isSessionRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            self?.isSessionRunning = true
        }
    }
    
    func stopCapturing() {
        guard isSessionRunning else { return }
        captureSession.stopRunning()
        isSessionRunning = false
    }
    
    // MARK: - Delegate: Capture Output
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTextureOut: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTextureOut)
        
        if result == kCVReturnSuccess,
           let cvTexture = cvTextureOut,
           let texture = CVMetalTextureGetTexture(cvTexture) {
            DispatchQueue.main.async { [weak self] in
                self?.onTextureReady?(texture)
            }
        }
    }
}
