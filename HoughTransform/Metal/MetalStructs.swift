import simd

struct Vertex {
  var position: SIMD2<Float>
  var texCoord: SIMD2<Float>
}

struct EdgeDetectionParams {
  var lowThreshold: Float
  var highThreshold: Float
  var useCannyEdgeDetection: Int32
}

struct HoughParams {
  var rhoResolution: Float
  var thetaResolution: Float
  var accumulatorThreshold: Int32
  var maxLines: Int32
  var useProbabilistic: Int32
  var imageWidth: Int32
  var imageHeight: Int32
  var accumulatorWidth: Int32
  var accumulatorHeight: Int32
  var maxRho: Float
}

struct LineParams {
  var lineColor: SIMD4<Float>
  var lineThickness: Float
  var overlayOpacity: Float
}

struct DetectedLine {
  var rho: Float
  var theta: Float
  var votes: Int32
  var point1: SIMD2<Float>
  var point2: SIMD2<Float>
}

struct BlurParams {
  var kernelSize: Int32
  var sigma: Float
}

struct RenderParams {
  var aspectScale: SIMD2<Float>
}
