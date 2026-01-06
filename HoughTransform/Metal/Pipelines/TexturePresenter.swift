import Metal
import MetalKit
import simd

final class TexturePresenter {
  private let renderPipeline: MTLRenderPipelineState
  private let device: MTLDevice
  private var vertexBuffer: MTLBuffer?
  
  init(device: MTLDevice) throws {
    self.device = device
    
    guard let library = device.makeDefaultLibrary() else {
      throw PipelineError.libraryNotFound
    }
    
    self.renderPipeline = try library.renderPipeline()
    setupVertexBuffer()
  }
  
  private func setupVertexBuffer() {
    let vertices: [Vertex] = [
      Vertex(position: SIMD2<Float>(-1, -1), texCoord: SIMD2<Float>(0, 1)),
      Vertex(position: SIMD2<Float>(1, -1), texCoord: SIMD2<Float>(1, 1)),
      Vertex(position: SIMD2<Float>(-1, 1), texCoord: SIMD2<Float>(0, 0)),
      Vertex(position: SIMD2<Float>(1, -1), texCoord: SIMD2<Float>(1, 1)),
      Vertex(position: SIMD2<Float>(1, 1), texCoord: SIMD2<Float>(1, 0)),
      Vertex(position: SIMD2<Float>(-1, 1), texCoord: SIMD2<Float>(0, 0))
    ]
    
    vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count)
  }
  
  func draw(texture: MTLTexture, in drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].storeAction = .store
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
          let vertexBuffer = vertexBuffer else { return }
    
    // Calculate aspect ratio scale for fill (crop to fill screen)
    let textureAspect = Float(texture.width) / Float(texture.height)
    let viewAspect = Float(drawable.texture.width) / Float(drawable.texture.height)
    
    var renderParams: RenderParams
    if textureAspect > viewAspect {
      // Texture is wider than view - scale X up to fill (crop sides)
      renderParams = RenderParams(aspectScale: SIMD2<Float>(textureAspect / viewAspect, 1.0))
    } else {
      // Texture is taller than view - scale Y up to fill (crop top/bottom)
      renderParams = RenderParams(aspectScale: SIMD2<Float>(1.0, viewAspect / textureAspect))
    }
    
    encoder.setRenderPipelineState(renderPipeline)
    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    encoder.setVertexBytes(&renderParams, length: MemoryLayout<RenderParams>.stride, index: 1)
    encoder.setFragmentTexture(texture, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
  }
}
