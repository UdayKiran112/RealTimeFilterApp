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
        captureSession.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            fatalError("Cannot access back camera")
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        let queue = DispatchQueue(label: "CameraOutputQueue")
        videoOutput.setSampleBufferDelegate(self, queue: queue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

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
            videoOrientation = .landscapeRight
        case .landscapeRight:
            videoOrientation = .landscapeLeft
        default:
            // Default to portrait if unknown orientation
            videoOrientation = .portrait
        }

        connection.videoOrientation = videoOrientation
    }

    /// Start capturing camera frames
    func startCapturing() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    /// Stop capturing camera frames
    func stopCapturing() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    /// Toggle torch (flashlight) on or off
    func toggleTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used: \(error)")
        }
    }

    /// Capture output delegate method to convert CMSampleBuffer to Metal texture and pass it back
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

        if result == kCVReturnSuccess,
           let cvTexture = cvTextureOut,
           let texture = CVMetalTextureGetTexture(cvTexture) {
            // Pass raw texture to caller, no filter applied here
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
