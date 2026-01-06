import Metal
import MetalKit
import simd
import FactoryKit

protocol Pipeline {
  
  associatedtype Parameter
  
  var parameters: Parameter { get }
  
  var device: MTLDevice { get }
  var commandQueue: MTLCommandQueue { get }
  func process(inputTexture: MTLTexture, drawable: CAMetalDrawable)
  func ensureTextures(width: Int, height: Int)
}

enum PipelineError: Error {
  case functionNotFound(String)
  case pipelineCreationFailed
  case commandQueueCreationFailed
  case libraryNotFound
}

final class PassthroughPipeline: Pipeline {
  
  var parameters: Void { }
  
  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  
  private let presenter: TexturePresenter
  
  init() {
    self.device = Container.shared.metalDevice()
    self.commandQueue = device.makeCommandQueue()!
    
    do {
      self.presenter = try TexturePresenter(device: device)
    } catch {
      fatalError("Failed to create texture presenter: \(error)")
    }
  }
  
  func process(inputTexture: MTLTexture, drawable: CAMetalDrawable) {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
    
    presenter.draw(texture: inputTexture, in: drawable, commandBuffer: commandBuffer)
    
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
  func ensureTextures(width: Int, height: Int) {
    // No intermediate textures needed
  }
}
