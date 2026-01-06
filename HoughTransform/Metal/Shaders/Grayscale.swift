import Metal

class GrayscaleShader: Shader {
  var inputTexture: MTLTexture?
  var outputTexture: MTLTexture?
  
  private let pipelineState: MTLComputePipelineState
  
  init(library: MTLLibrary) throws {
    self.pipelineState = try library.computePipeline(for: "grayscaleKernel")
  }
  
  func perform(in commandBuffer: MTLCommandBuffer) throws {
    guard let input = inputTexture, let output = outputTexture,
          let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.label = "Grayscale"
    
    encoder.setComputePipelineState(pipelineState)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(output, index: 1)
    
    let w = pipelineState.threadExecutionWidth
    let h = pipelineState.maxTotalThreadsPerThreadgroup / w
    let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
    let threadgroups = MTLSize(
      width: (output.width + w - 1) / w,
      height: (output.height + h - 1) / h,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
}
