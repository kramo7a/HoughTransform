import SwiftUI
import Combine

enum EdgeDetectionAlgorithm: String, CaseIterable, Identifiable {
  case sobel = "Sobel"
  case canny = "Canny"
  
  var id: String { rawValue }
}

enum HoughAlgorithm: String, CaseIterable, Identifiable {
  case standard = "Standard"
  case probabilistic = "Probabilistic"
  
  var id: String { rawValue }
}

enum DisplayStage: String, CaseIterable, Identifiable {
  case input = "Input"
  case downsampled = "Downsample"
  case grayscale = "Grayscale"
  case blurred = "Filter"
  case edges = "Edges"
  case houghAccumulator = "Accum."
  
  var id: String { rawValue }
}

final class HoughParameters: ObservableObject {
  
  @Published var fps: Int = 60
  
  @Published var downsampleFactor: Int = 2
  
  // Blur parameters
  @Published var blurKernelSize: Int = 5
  @Published var blurSigma: Float = 1.4
  
  @Published var edgeAlgorithm: EdgeDetectionAlgorithm = .canny
  @Published var lowThreshold: Float = 0.1
  @Published var highThreshold: Float = 0.3
  
  @Published var houghAlgorithm: HoughAlgorithm = .standard
  @Published var rhoResolution: Float = 1.0
  @Published var thetaResolution: Float = 1.0
  @Published var accumulatorThreshold: Int = 100
  @Published var maxLines: Int = 50
  
  @Published var lineColor: Color = .red
  @Published var lineThickness: Float = 2.0
  @Published var overlayOpacity: Float = 0.8
  
  @Published var showEdges: Bool = false
  @Published var showAccumulator: Bool = false
  @Published var displayStage: DisplayStage = .input
  @Published var showLinesOverlay: Bool = true
  
  var lineColorSIMD: SIMD4<Float> {
    let resolved = lineColor.resolve(in: EnvironmentValues())
    return SIMD4<Float>(resolved.red, resolved.green, resolved.blue, resolved.opacity)
  }
  
  var thetaResolutionRadians: Float {
    thetaResolution * .pi / 180.0
  }
}

