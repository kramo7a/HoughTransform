import FactoryKit
import Metal
import QuartzCore

extension Container {
  var metalDevice: Factory<MTLDevice> {
    self {
      MTLCreateSystemDefaultDevice()!
    }
    .singleton
  }
  
  var houghPipeline: Factory<any Pipeline> {
    self { @MainActor in
      do {
        return try HoughPipeline()
      } catch {
        return self.passthroughPipeline()
      }
    }
    .singleton
  }
  
  var passthroughPipeline: Factory<any Pipeline> {
    self { @MainActor in PassthroughPipeline() }
      .singleton
  }
  
  @MainActor
  var textureFactory: Factory<TextureFactory> {
    self { @MainActor in
      TextureFactoryImpl()
    }
    .shared
  }
  
  @MainActor
  var cameraManager: Factory<CameraManager> {
    self { @MainActor in
      CameraManagerImpl()
    }
    .shared
  }
  
  @MainActor
  var inputTextureSource: Factory<InputTextureSource> {
    self { @MainActor in
      InputTextureSourceImpl()
    }
    .shared
  }
  
  @MainActor
  var houghParameters: Factory<HoughParameters> {
    self { @MainActor in
      HoughParameters()
    }
    .shared
  }
}

