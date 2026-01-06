#if os(iOS)
import SwiftUI
import UIKit

struct SheetScrollHandler {
  var onOverscroll: (CGFloat) -> Void = { _ in }
  var onOverscrollEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
}

private struct SheetScrollHandlerKey: EnvironmentKey {
  static let defaultValue = SheetScrollHandler()
}

extension EnvironmentValues {
  var sheetScrollHandler: SheetScrollHandler {
    get { self[SheetScrollHandlerKey.self] }
    set { self[SheetScrollHandlerKey.self] = newValue }
  }
}

struct SheetScrollView<Content: View>: UIViewControllerRepresentable {
  @Environment(\.sheetScrollHandler) private var scrollHandler
  @ViewBuilder let content: () -> Content
  
  func makeUIViewController(context: Context) -> SheetScrollViewController<Content> {
    let controller = SheetScrollViewController(
      rootView: content(),
      scrollHandler: scrollHandler
    )
    return controller
  }
  
  func updateUIViewController(_ uiViewController: SheetScrollViewController<Content>, context: Context) {
    uiViewController.scrollHandler = scrollHandler
    uiViewController.updateContent(content())
  }
}

class SheetScrollViewController<Content: View>: UIViewController, UIScrollViewDelegate {
  private let scrollView = UIScrollView()
  private var hostingController: UIHostingController<Content>
  var scrollHandler: SheetScrollHandler
  
  private var isOverscrolling = false
  private var dragStartY: CGFloat = 0
  
  init(rootView: Content, scrollHandler: SheetScrollHandler) {
    self.hostingController = UIHostingController(rootView: rootView)
    self.scrollHandler = scrollHandler
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    scrollView.delegate = self
    scrollView.alwaysBounceVertical = true
    scrollView.showsVerticalScrollIndicator = true
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)
    
    addChild(hostingController)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    hostingController.view.backgroundColor = .clear
    scrollView.addSubview(hostingController.view)
    hostingController.didMove(toParent: self)
    
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      
      hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
    ])
    
    scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
  }
  
  func updateContent(_ content: Content) {
    hostingController.rootView = content
  }
  
  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: view)
    let velocity = gesture.velocity(in: view)
    
    switch gesture.state {
    case .began:
      dragStartY = scrollView.contentOffset.y
      isOverscrolling = false
      
    case .changed:
      let isAtTop = dragStartY <= 0
      let isPullingDown = translation.y > 0
      
      if isAtTop && isPullingDown {
        if !isOverscrolling {
          isOverscrolling = true
        }
        scrollView.contentOffset = .zero
        scrollHandler.onOverscroll(translation.y)
      }
      
    case .ended, .cancelled:
      if isOverscrolling {
        scrollHandler.onOverscrollEnded(translation.y, velocity.y)
      }
      isOverscrolling = false
      
    default:
      break
    }
  }
  
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    dragStartY = scrollView.contentOffset.y
  }
}
#endif
