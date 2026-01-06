import Metal
import CoreVideo
import FactoryKit

protocol CameraManagerDelegate: AnyObject {
  func cameraManager(_ manager: CameraManager, didOutputTexture texture: MTLTexture)
}

protocol CameraManager: AnyObject {
  var delegate: CameraManagerDelegate? { get set }
  var isRunning: Bool { get }
  
  init()
  
  func setupCamera()
  func startCapture()
  func stopCapture()
}

#if os(iOS) || os(macOS)
import AVFoundation

final class CameraManagerImpl: NSObject, CameraManager, AVCaptureVideoDataOutputSampleBufferDelegate {
  weak var delegate: CameraManagerDelegate?
  
  @Injected(\.metalDevice) private var device: MTLDevice
  @Injected(\.houghParameters) private var houghParameters
  private var textureCache: CVMetalTextureCache?
  private let captureSession = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "camera.session.queue")
  private let videoOutput = AVCaptureVideoDataOutput()
  private let videoOutputQueue = DispatchQueue(label: "camera.video.queue", qos: .userInteractive)
  
  var isRunning: Bool { captureSession.isRunning }
  
  override init() {
    super.init()
    
    var cache: CVMetalTextureCache?
    CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    self.textureCache = cache
  }
  
  func setupCamera() {
    sessionQueue.async { [weak self] in
      self?.configureSession()
    }
  }
  
  private func configureSession() {
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .high

    guard let videoDevice = AVCaptureDevice.default(for: .video) else {
      captureSession.commitConfiguration()
      return
    }
    
    do {
      let videoInput = try AVCaptureDeviceInput(device: videoDevice)
      
      if captureSession.canAddInput(videoInput) {
        captureSession.addInput(videoInput)
      }
      
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
      videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
      
      if captureSession.canAddOutput(videoOutput) {
        captureSession.addOutput(videoOutput)
        
        if let connection = videoOutput.connection(with: .video) {
          #if os(iOS)
          connection.videoOrientation = .portrait
          #elseif os(macOS)
          if #available(macOS 14.0, *) {
            connection.videoRotationAngle = 0
          } else {
            connection.videoOrientation = .portrait
          }
          #endif
        }
      }
      
      try configureFrameRate(device: videoDevice)
      
    } catch {
      print("Camera setup error: \(error)")
    }
    
    captureSession.commitConfiguration()
  }
  
  private func configureFrameRate(device: AVCaptureDevice) throws {
    let allRanges = device.formats.flatMap { format in
      format.videoSupportedFrameRateRanges.map { (format, $0) }
    }
    
    guard let (bestFormat, bestRange) = allRanges.max(by: { $0.1.maxFrameRate < $1.1.maxFrameRate }) else { return }
    
    try device.lockForConfiguration()
    device.activeFormat = bestFormat
    
    let targetFrameRate = min(Float64(houghParameters.fps), bestRange.maxFrameRate)
    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
    
    device.unlockForConfiguration()
  }
  
  func startCapture() {
    sessionQueue.async { [weak self] in
      guard let self, !self.captureSession.isRunning else { return }
      self.captureSession.startRunning()
    }
  }
  
  func stopCapture() {
    sessionQueue.async { [weak self] in
      guard let self, self.captureSession.isRunning else { return }
      self.captureSession.stopRunning()
    }
  }
  
  private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
    guard let cache = textureCache else { return nil }
    
    var cvTexture: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      nil, cache, pixelBuffer, nil, .bgra8Unorm,
      CVPixelBufferGetWidth(pixelBuffer),
      CVPixelBufferGetHeight(pixelBuffer),
      0, &cvTexture
    )
    
    guard status == kCVReturnSuccess, let cvTex = cvTexture else { return nil }
    return CVMetalTextureGetTexture(cvTex)
  }
  
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
          let texture = createTexture(from: pixelBuffer) else { return }
    
    delegate?.cameraManager(self, didOutputTexture: texture)
  }
}

#endif
