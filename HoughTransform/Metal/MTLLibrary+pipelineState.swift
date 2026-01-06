import Metal

extension MTLLibrary {
  func computePipeline(for functionName: String) throws -> MTLComputePipelineState {
    guard let function = makeFunction(name: functionName) else {
      throw PipelineError.functionNotFound(functionName)
    }
    return try self.device.makeComputePipelineState(function: function)
  }
  
  func renderPipeline() throws -> MTLRenderPipelineState {
    guard
      let vertexFunction = makeFunction(name: "vertexShader"),
      let fragmentFunction = makeFunction(name: "fragmentShader")
    else { throw PipelineError.functionNotFound("render shaders") }
    
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    
    return try device.makeRenderPipelineState(descriptor: descriptor)
  }
}
