import Metal
import MetalKit
import FactoryKit

#if os(iOS) || os(visionOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif


protocol TextureFactory {
  func loadTexture(from image: PlatformImage) -> MTLTexture?
  func loadTexture(from data: Data) -> MTLTexture?
}

final class TextureFactoryImpl: TextureFactory {
  private let device: MTLDevice
  private let textureLoader: MTKTextureLoader
  
  init() {
    self.device = Container.shared.metalDevice()
    self.textureLoader = MTKTextureLoader(device: device)
  }
  
  func loadTexture(from image: PlatformImage) -> MTLTexture? {
#if os(iOS) || os(visionOS)
    guard let cgImage = image.cgImage else { return nil }
#elseif os(macOS)
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
#endif
    
    let options: [MTKTextureLoader.Option: Any] = [
      .textureUsage: MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue,
      .textureStorageMode: MTLStorageMode.private.rawValue,
      .SRGB: false
    ]
    
    do {
      return try textureLoader.newTexture(cgImage: cgImage, options: options)
    } catch {
      print("Failed to load texture: \(error)")
      return nil
    }
  }
  
  func loadTexture(from data: Data) -> MTLTexture? {
    let options: [MTKTextureLoader.Option: Any] = [
      .textureUsage: MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue,
      .textureStorageMode: MTLStorageMode.private.rawValue,
      .SRGB: false
    ]
    
    do {
      return try textureLoader.newTexture(data: data, options: options)
    } catch {
      print("Failed to load texture from data: \(error)")
      return nil
    }
  }
}

