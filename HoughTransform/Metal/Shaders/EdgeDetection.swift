import Metal

class EdgeDetectionShader: Shader {
  var inputTexture: MTLTexture?
  var outputTexture: MTLTexture?
  
  var gradientMagnitudeTexture: MTLTexture?
  var gradientDirectionTexture: MTLTexture?
  var tempEdgeTexture: MTLTexture?
  
  private let sobelPipeline: MTLComputePipelineState
  private let cannyNonMaxPipeline: MTLComputePipelineState
  private let cannyHysteresisPipeline: MTLComputePipelineState
  private let device: MTLDevice
  
  var parameters: HoughParameters?
  
  init(device: MTLDevice, library: MTLLibrary) throws {
    self.device = device
    self.sobelPipeline = try library.computePipeline(for: "sobelKernel")
    self.cannyNonMaxPipeline = try library.computePipeline(for: "cannyNonMaxSuppressionKernel")
    self.cannyHysteresisPipeline = try library.computePipeline(for: "cannyHysteresisKernel")
  }
  
  func perform(in commandBuffer: MTLCommandBuffer) throws {
    guard let input = inputTexture, let output = outputTexture,
          let parameters = parameters else { return }
    
    ensureIntermediateTextures(width: input.width, height: input.height)
    
    guard let magnitude = gradientMagnitudeTexture,
          let direction = gradientDirectionTexture,
          let tempEdge = tempEdgeTexture else { return }
    
    var edgeParams = EdgeDetectionParams(
      lowThreshold: parameters.lowThreshold,
      highThreshold: parameters.highThreshold,
      useCannyEdgeDetection: parameters.edgeAlgorithm == .canny ? 1 : 0
    )
    
    // 1. Sobel
    if let encoder = commandBuffer.makeComputeCommandEncoder() {
      encoder.label = "Sobel"
      encoder.setComputePipelineState(sobelPipeline)
      encoder.setTexture(input, index: 0)
      encoder.setTexture(magnitude, index: 1)
      encoder.setTexture(direction, index: 2)
      encoder.setBytes(&edgeParams, length: MemoryLayout<EdgeDetectionParams>.stride, index: 0)
      dispatch(encoder: encoder, pipeline: sobelPipeline, width: input.width, height: input.height)
      encoder.endEncoding()
    }
    
    if parameters.edgeAlgorithm == .canny {
      // 2. Non-Max Suppression
      if let encoder = commandBuffer.makeComputeCommandEncoder() {
        encoder.label = "Canny Non-Max"
        encoder.setComputePipelineState(cannyNonMaxPipeline)
        encoder.setTexture(magnitude, index: 0)
        encoder.setTexture(direction, index: 1)
        encoder.setTexture(tempEdge, index: 2)
        encoder.setBytes(&edgeParams, length: MemoryLayout<EdgeDetectionParams>.stride, index: 0)
        dispatch(encoder: encoder, pipeline: cannyNonMaxPipeline, width: input.width, height: input.height)
        encoder.endEncoding()
      }
      
      // 3. Hysteresis
      if let encoder = commandBuffer.makeComputeCommandEncoder() {
        encoder.label = "Canny Hysteresis"
        encoder.setComputePipelineState(cannyHysteresisPipeline)
        encoder.setTexture(tempEdge, index: 0)
        encoder.setTexture(output, index: 1)
        dispatch(encoder: encoder, pipeline: cannyHysteresisPipeline, width: input.width, height: input.height)
        encoder.endEncoding()
      }
    } else {
      // Just copy magnitude to output if not Canny
      if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
        blitEncoder.label = "Copy Sobel Magnitude"
        blitEncoder.copy(from: magnitude, to: output)
        blitEncoder.endEncoding()
      }
    }
  }
  
  private func ensureIntermediateTextures(width: Int, height: Int) {
    if gradientMagnitudeTexture?.width != width || gradientMagnitudeTexture?.height != height {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
      descriptor.usage = [.shaderRead, .shaderWrite]
      descriptor.storageMode = .private
      
      gradientMagnitudeTexture = device.makeTexture(descriptor: descriptor)
      gradientDirectionTexture = device.makeTexture(descriptor: descriptor)
      tempEdgeTexture = device.makeTexture(descriptor: descriptor)
    }
  }
  
  private func dispatch(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
    let w = pipeline.threadExecutionWidth
    let h = pipeline.maxTotalThreadsPerThreadgroup / w
    let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
    let threadgroups = MTLSize(
      width: (width + w - 1) / w,
      height: (height + h - 1) / h,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
  }
}
