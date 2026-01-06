import SwiftUI
import PhotosUI

struct ParameterControlsView: View {
  
  private let titleSpacing: CGFloat = 16
  
  @ObservedObject var parameters: HoughParameters
  @Binding var inputSource: InputSource
  @Binding var selectedPhotoItem: PhotosPickerItem?
  
  var body: some View {
    sheetScrollView {
      VStack(spacing: 16) {
        inputSourceSection
        visualizationSection
        stageVisualizationSection
        downsampleSection
        blurSection
        edgeDetectionSection
        houghTransformSection
      }
      .padding()
    }
  }
  
  @ViewBuilder
  private func sheetScrollView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
#if os(iOS)
    SheetScrollView {
      content()
    }
#else
    ScrollView {
      content()
    }
#endif
  }
  
  private var inputSourceSection: some View {
    VStack(alignment: .leading, spacing: titleSpacing) {
      TitleWithToggle(
        title: "Source Type",
        selection: $inputSource
      ) {
        ForEach(InputSource.allCases) { source in
          Text(source.rawValue).tag(source)
        }
      }
      
      if inputSource == .image {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
          HStack {
            Image(systemName: "photo.on.rectangle")
            Text("Select Image")
            Spacer()
          }
          .padding(.vertical, 8)
          .padding(.horizontal, 12)
          .background(Color(.secondarySystemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
      }
    }
    .sectionCard()
  }
  
  private var stageVisualizationSection: some View {
    VStack(alignment: .leading, spacing: titleSpacing) {
      SectionTitle("Display Stage")
    
      Picker("", selection: $parameters.displayStage) {
        
        ForEach(DisplayStage.allCases) { stage in
          Text(stage.rawValue).tag(stage)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .sectionCard()
  }
  
  private var downsampleSection: some View {
    TitleWithToggle(
      title: "Downsample",
      selection: $parameters.downsampleFactor
    ) {
      Text("1x").tag(1)
      Text("2x").tag(2)
      Text("4x").tag(4)
      Text("8x").tag(8)
    }
    .sectionCard()
  }
  
  private var blurSection: some View {
    VStack(alignment: .leading, spacing: titleSpacing) {
      TitleWithToggle(
        title: "Gaussian",
        selection: $parameters.blurKernelSize
      ) {
        Text("3×3").tag(3)
        Text("5×5").tag(5)
        Text("7×7").tag(7)
        Text("9×9").tag(9)
      }
      
      ParameterSlider(
        title: "Sigma (Intensity)",
        value: $parameters.blurSigma,
        range: 0.1...5.0,
        format: "%.2f"
      )
    }
    .sectionCard()
  }
  
  private var edgeDetectionSection: some View {
    VStack(alignment: .leading, spacing: titleSpacing) {
      TitleWithToggle(
        title: "Edge detection",
        selection: $parameters.edgeAlgorithm
      ) {
        ForEach(EdgeDetectionAlgorithm.allCases) { algorithm in
          Text(algorithm.rawValue).tag(algorithm)
        }
      }
      
      ParameterSlider(
        title: "Low Threshold",
        value: $parameters.lowThreshold,
        range: 0.01...0.5,
        format: "%.2f"
      )
      
      ParameterSlider(
        title: "High Threshold",
        value: $parameters.highThreshold,
        range: 0.1...1.0,
        format: "%.2f"
      )
    }
    .sectionCard()
  }
  
  private var houghTransformSection: some View {
    VStack(alignment: .leading, spacing: titleSpacing) {
      TitleWithToggle(
        title: "Hough Transform",
        selection: $parameters.houghAlgorithm
      ) {
        ForEach(HoughAlgorithm.allCases) { algorithm in
          Text(algorithm.rawValue).tag(algorithm)
        }
      }
      
      ParameterSlider(
        title: "Rho Resolution (px)",
        value: $parameters.rhoResolution,
        range: 0.5...10.0,
        format: "%.1f"
      )
      
      ParameterSlider(
        title: "Theta Resolution (°)",
        value: $parameters.thetaResolution,
        range: 0.5...5.0,
        format: "%.1f"
      )
      
      ParameterSlider(
        title: "Accumulator Threshold",
        value: Binding(
          get: { Float(parameters.accumulatorThreshold) },
          set: { parameters.accumulatorThreshold = Int($0) }
        ),
        range: 10...500,
        format: "%.0f"
      )
      
      ParameterSlider(
        title: "Max Lines",
        value: Binding(
          get: { Float(parameters.maxLines) },
          set: { parameters.maxLines = Int($0) }
        ),
        range: 1...200,
        format: "%.0f"
      )
    }
    .sectionCard()
  }
  
  private var visualizationSection: some View {
    VStack(alignment: .leading, spacing: titleSpacing) {
      TitleWithToggle(
        title: "Lines overlay",
        selection: $parameters.showLinesOverlay
      ) {
        Text("Off").tag(false)
        Text("On").tag(true)
      }
      
      if parameters.showLinesOverlay {
        ColorPicker("Line Color", selection: $parameters.lineColor)
        
        ParameterSlider(
          title: "Line Thickness",
          value: $parameters.lineThickness,
          range: 1.0...10.0,
          format: "%.1f"
        )
        
        ParameterSlider(
          title: "Overlay Opacity",
          value: $parameters.overlayOpacity,
          range: 0.1...1.0,
          format: "%.2f"
        )
      }
    }
    .sectionCard()
  }
}

// MARK: - Reusable Components

struct SectionCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(16)
      .background(Color(.tertiarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

extension View {
  func sectionCard() -> some View {
    modifier(SectionCardModifier())
  }
}

struct SectionTitle: View {
  let title: String
  
  init(_ title: String) {
    self.title = title
  }
  
  var body: some View {
    Text(title)
      .font(.headline)
      .fontWeight(.semibold)
      .foregroundStyle(.primary)
  }
}

struct TitleWithToggle<Selection: Hashable, Content: View>: View {
  let title: String
  @Binding var selection: Selection
  let content: Content
  
  init(
    title: String,
    selection: Binding<Selection>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self._selection = selection
    self.content = content()
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      SectionTitle(title)
      Spacer()
      Picker("", selection: $selection) {
        content
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  }
}

struct ParameterSlider: View {
  let title: String
  @Binding var value: Float
  let range: ClosedRange<Float>
  let format: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
          .font(.subheadline)
        Spacer()
        Text(String(format: format, value))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      
      Slider(value: $value, in: range)
    }
  }
}

#if os(macOS)
extension Color {
  init(_ name: SystemColorName) {
    switch name {
    case .systemGroupedBackground:
      self = Color(nsColor: .windowBackgroundColor)
    case .secondarySystemBackground:
      self = Color(nsColor: .controlBackgroundColor)
    case .tertiarySystemBackground:
      self = Color(nsColor: .textBackgroundColor)
    }
  }
}

enum SystemColorName {
  case systemGroupedBackground
  case secondarySystemBackground
  case tertiarySystemBackground
}
#endif

#if os(iOS) || os(visionOS)
extension Color {
  init(_ name: SystemColorName) {
    switch name {
    case .systemGroupedBackground:
      self = Color(uiColor: .systemGroupedBackground)
    case .secondarySystemBackground:
      self = Color(uiColor: .secondarySystemBackground)
    case .tertiarySystemBackground:
      self = Color(uiColor: .tertiarySystemBackground)
    }
  }
}

enum SystemColorName {
  case systemGroupedBackground
  case secondarySystemBackground
  case tertiarySystemBackground
}
#endif

