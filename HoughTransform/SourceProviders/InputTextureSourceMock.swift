#if DEBUG
import SwiftUI
import PhotosUI
import Metal
import FactoryKit

@Observable
@MainActor
final class InputTextureSourceMock: InputTextureSource {
  @ObservationIgnored @Injected(\.textureFactory) private var textureFactory: TextureFactory
  
  var currentTexture: MTLTexture?
  var inputSource: InputSource = .image
  var cameraPermissionDenied: Bool = false
  
  let url: URL?
  
  init(url: URL? = Bundle.main.url(forResource: "guitar", withExtension: "jpg")) {
    self.url = url
  }
  
  func start() async {
    loadPreviewImage()
  }
  
  func switchSource(to source: InputSource) {
    inputSource = source
  }
  
  func loadImage(from item: PhotosPickerItem?) async {
    // No-op for mock
  }
  
  private func loadPreviewImage() {
    guard let url,
          let data = try? Data(contentsOf: url) else {
      return
    }
    currentTexture = textureFactory.loadTexture(from: data)
  }
}
#endif
