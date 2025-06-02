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
    
    init(device: MTLDevice) {
        self.device = device
        
        // Create texture cache for converting CVPixelBuffer to MTLTexture
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache!
        
        super.init()
        setupCaptureSession()
        addOrientationObserver()
    }
    
    /// Configure the camera capture session
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            fatalError("Cannot access camera")
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        let queue = DispatchQueue(label: "CameraOutputQueue")
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // Set initial orientation
        updateVideoOrientation()
        
        captureSession.commitConfiguration()
    }
    
    /// Observe device orientation changes and update video orientation accordingly
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
    
    /// Update AVCaptureVideoOrientation based on current device orientation
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
            videoOrientation = .landscapeRight // camera perspective
        case .landscapeRight:
            videoOrientation = .landscapeLeft  // camera perspective
        default:
            return
        }

        connection.videoOrientation = videoOrientation
    }
    
    func startCapturing() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    func stopCapturing() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var cvTextureOut: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               textureCache,
                                                               pixelBuffer,
                                                               nil,
                                                               .bgra8Unorm,
                                                               width,
                                                               height,
                                                               0,
                                                               &cvTextureOut)

        if result == kCVReturnSuccess, let cvTexture = cvTextureOut,
           let texture = CVMetalTextureGetTexture(cvTexture) {
            DispatchQueue.main.async {
                self.onTextureReady?(texture)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
}
