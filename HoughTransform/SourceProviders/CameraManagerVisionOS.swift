// TODO: Enterprise entitlements
// Not tested yet
#if os(visionOS)
import Foundation
import ARKit
import FactoryKit

final class CameraManagerImpl: CameraManager {
  weak var delegate: CameraManagerDelegate?
  
  @Injected(\.metalDevice) private var device: MTLDevice
  private var arSession: ARKitSession?
  private var cameraFrameProvider: CameraFrameProvider?
  private var selectedFormat: CameraVideoFormat?
  
  var isRunning = false
  
  init() {
  }
  
  func setupCamera() {
    Task { await configureSession() }
  }
  
  private func configureSession() async {
    guard CameraFrameProvider.isSupported else {
      print("CameraFrameProvider not supported - requires Enterprise API entitlement")
      return
    }
    
    let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left])
    guard let format = formats.first else {
      print("No camera formats available")
      return
    }
    selectedFormat = format
    
    cameraFrameProvider = CameraFrameProvider()
    arSession = ARKitSession()
    
    guard let session = arSession, let provider = cameraFrameProvider else { return }
    
    do {
      try await session.run([provider])
      isRunning = true
      Task { await processFrames() }
    } catch {
      print("Failed to start ARKit session: \(error)")
    }
  }
  
  private func processFrames() async {
    guard let provider = cameraFrameProvider,
          let format = selectedFormat,
          let updates = provider.cameraFrameUpdates(for: format) else { return }
    
    for await update in updates {
      guard let sample = update.sample(for: .left),
            let texture = createTexture(from: sample.pixelBuffer) else { continue }
      
      await MainActor.run {
        delegate?.cameraManager(self, didOutputTexture: texture)
      }
    }
  }
  
  private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    
    texture.replace(
      region: MTLRegionMake2D(0, 0, width, height),
      mipmapLevel: 0,
      withBytes: baseAddress,
      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
    )
    
    return texture
  }
  
  func startCapture() {
    setupCamera()
  }
  
  func stopCapture() {
    arSession?.stop()
    isRunning = false
  }
}


#endif
