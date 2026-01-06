import Foundation

enum InputSource: String, CaseIterable, Identifiable {
  case camera = "Camera"
  case image = "Image"
  
  var id: String { rawValue }
}
