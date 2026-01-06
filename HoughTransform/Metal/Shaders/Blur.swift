import Metal

class BlurShader: Shader {
  var inputTexture: MTLTexture?
  var outputTexture: MTLTexture?
  var parameters: HoughParameters?
  
  private let pipelineState: MTLComputePipelineState
  
  init(library: MTLLibrary) throws {
    self.pipelineState = try library.computePipeline(for: "gaussianBlurKernel")
  }
  
  func perform(in commandBuffer: MTLCommandBuffer) throws {
    guard let input = inputTexture, let output = outputTexture,
          let parameters = parameters,
          let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.label = "Gaussian Blur"
    
    var blurParams = BlurParams(
      kernelSize: Int32(parameters.blurKernelSize),
      sigma: parameters.blurSigma
    )
    
    encoder.setComputePipelineState(pipelineState)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(output, index: 1)
    encoder.setBytes(&blurParams, length: MemoryLayout<BlurParams>.stride, index: 0)
    
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
