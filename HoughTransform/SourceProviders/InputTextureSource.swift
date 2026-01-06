import SwiftUI
import PhotosUI
import Metal
import FactoryKit

#if os(iOS) || os(macOS)
import AVFoundation
#endif

@MainActor
protocol InputTextureSource: AnyObject {
  var currentTexture: MTLTexture? { get set }
  var inputSource: InputSource { get set }
  var cameraPermissionDenied: Bool { get }
  
  func start() async
  func switchSource(to source: InputSource)
  func loadImage(from item: PhotosPickerItem?) async
}

@Observable
@MainActor
final class InputTextureSourceImpl: InputTextureSource, CameraManagerDelegate {
  
  @ObservationIgnored @Injected(\.cameraManager) private var cameraManager: CameraManager
  @ObservationIgnored @Injected(\.textureFactory) private var textureFactory: TextureFactory
  
  var currentTexture: MTLTexture?
  var inputSource: InputSource = .camera
  var cameraPermissionDenied = false
  
  func start() async {
    cameraManager.delegate = self
    await requestCameraPermission()
    if !cameraPermissionDenied {
      startCamera()
    }
  }
  
  func switchSource(to source: InputSource) {
    inputSource = source
    
    switch source {
    case .camera:
      cameraManager.startCapture()
    case .image:
      cameraManager.stopCapture()
    }
  }
  
  func loadImage(from item: PhotosPickerItem?) async {
    guard let item,
          let data = try? await item.loadTransferable(type: Data.self),
          let texture = textureFactory.loadTexture(from: data) else { return }
    
    currentTexture = texture
  }
  
  // MARK: - Camera Management
  
  private func requestCameraPermission() async {
#if os(iOS) || os(macOS)
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    
    switch status {
    case .authorized:
      startCamera()
    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: .video)
      if !granted {
        cameraPermissionDenied = true
      }
    case .denied, .restricted:
      cameraPermissionDenied = true
    @unknown default:
      break
    }
#elseif os(visionOS)
    startCamera()
#endif
  }
  
  private func startCamera() {
    cameraManager.setupCamera()
    if inputSource == .camera {
      cameraManager.startCapture()
    }
  }
  
  // MARK: - CameraManagerDelegate
  
  nonisolated func cameraManager(_ manager: CameraManager, didOutputTexture texture: MTLTexture) {
    Task { @MainActor in
      self.currentTexture = texture
    }
  }
}
