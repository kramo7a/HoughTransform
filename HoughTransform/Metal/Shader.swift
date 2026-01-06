import Metal

protocol Shader: AnyObject {
  var inputTexture: MTLTexture? { get set }
  var outputTexture: MTLTexture? { get set }
  
  func perform(in commandBuffer: MTLCommandBuffer) throws
}
