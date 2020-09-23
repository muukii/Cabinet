//
// Rideau
//
// Copyright © 2019 Hiroshi Kimura
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#if canImport(UIKit)
import UIKit

import TransitionPatch

protocol RideauInternalViewDelegate : class {
  
  @available(iOS 11, *)
  func rideauView(_ rideauInternalView: RideauInternalView, animatorsAlongsideMovingIn range: ResolvedSnapPointRange) -> [UIViewPropertyAnimator]
  
  func rideauView(_ rideauInternalView: RideauInternalView, willMoveTo snapPoint: RideauSnapPoint)
  
  func rideauView(_ rideauInternalView: RideauInternalView, didMoveTo snapPoint: RideauSnapPoint)
  
}

final class RideauInternalView : RideauTouchThroughView {
  
  // MARK: - Nested types
  
  private struct CachedValueSet : Equatable {
    
    var sizeThatLastUpdated: CGSize
    var offsetThatLastUpdated: CGFloat
    var usingConfiguration: RideauView.Configuration
  }
  
  // MARK: - Properties
  
  weak var delegate: RideauInternalViewDelegate?
  
  // Needs for internal usage
  internal var willChangeSnapPoint: (RideauSnapPoint) -> Void = { _ in }
  
  internal var didChangeSnapPoint: (RideauSnapPoint) -> Void = { _ in }
  
  internal let backdropView = RideauTouchThroughView()
  
  internal var trackingScrollViewOption: RideauView.TrackingScrollViewOption = .automatic
  
  private var actualTopMargin: CGFloat {
    switch configuration.topMarginOption {
    case .fromTop(let value):
      return value
    case .fromSafeArea(let value):
      let offset: CGFloat
      if #available(iOS 11.0, *) {
        offset = safeAreaInsets.top + value
      } else {
        offset = 20 + value
      }
      return offset
    }
  }
  
  private var heightConstraint: NSLayoutConstraint!
  
  private var bottomConstraint: NSLayoutConstraint!
  
  public let containerView = RideauContainerView()
  
  private(set) public var configuration: RideauView.Configuration
  
  private var resolvedConfiguration: ResolvedConfiguration?
  
  private var containerDraggingAnimator: UIViewPropertyAnimator?
  
  private var animatorStore: AnimatorStore = .init()
  
  private var currentSnapPoint: ResolvedSnapPoint?
  
  private var maximumContainerViewHeight: CGFloat?
  
  private var isInteracting: Bool = false
  
  private var shouldUpdate: Bool = false
  
  private var oldValueSet: CachedValueSet?
  
  private let scrollController: ScrollController = .init()
  
  // To tracking pan gesture
private var lastOffset: CGPoint = .zero
  private var shouldKillDecelerate: Bool = false
  private var initialLocation: ResolvedConfiguration.Location?
  private var hasReachedMostTop: Bool = false
  private var initialShowsVerticalScrollIndicator: Bool = false
  private var hasTakenAlongsideAnimators: Bool = false
  
  private let panGesture = RideauViewDragGestureRecognizer()
  
  // MARK: - Initializers
  
  init(
    frame: CGRect,
    configuration: RideauView.Configuration
    ) {
    
    self.configuration = configuration
    super.init(frame: .zero)
    
  }
  
  // MARK: - Functions
  
  func setup() {
    
    callback: do {
      
      containerView.didChangeContent = { [weak self] in
        guard let self = self else { return }
        guard self.isInteracting == false else { return }
        // It needs to update update ResolvedConfiguration
        self.shouldUpdate = true
        self.setNeedsLayout()
        self.layoutIfNeeded()
      }
    }
    
    view: do {
      
      containerView.translatesAutoresizingMaskIntoConstraints = false
      
      addSubview(backdropView)
      backdropView.frame = bounds
      backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      
      addSubview(containerView)
      containerView.set(owner: self)
      
      heightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)
      heightConstraint.priority = .defaultHigh
      
      bottomConstraint = containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
      
      NSLayoutConstraint.activate([
        bottomConstraint,
        heightConstraint,
        containerView.rightAnchor.constraint(equalTo: rightAnchor, constant: 0),
        containerView.leftAnchor.constraint(equalTo: leftAnchor, constant: 0),
        ])
      
    }
    
    gesture: do {
      
      panGesture.addTarget(self, action: #selector(handlePan))
      panGesture.delegate = self
      containerView.addGestureRecognizer(panGesture)
    }
    
  }
  
  @available(*, unavailable)
  required init?(coder aDecoder: NSCoder) {
    fatalError()
  }
  
  deinit {
    
    animatorStore
      .allAnimators()
      .forEach {
        $0.stopAnimation(true)
    }
  }
  
  // MARK: - Functions
  
  func update(configuration: RideauView.Configuration) {
    self.configuration = configuration
    setNeedsLayout()
    layoutIfNeeded()
  }
  
  func register(other panGesture: UIPanGestureRecognizer) {
    panGesture.addTarget(self, action: #selector(handlePan))
    panGesture.delegate = self
  }
  
  private func resolve(configuration: RideauView.Configuration) -> ResolvedConfiguration {
    
    let maxHeight = self.bounds.height - actualTopMargin
    heightConstraint.constant = maxHeight
    self.maximumContainerViewHeight = maxHeight
    
    let points = configuration.snapPoints.map { snapPoint -> ResolvedSnapPoint in
      switch snapPoint {
      case .fraction(let fraction):
        return .init(round(maxHeight - maxHeight * fraction), source: snapPoint)
      case .pointsFromTop(let points):
        return .init(points, source: snapPoint)
      case .pointsFromBottom(let points):
        return .init(round(maxHeight - points), source: snapPoint)
      case .autoPointsFromBottom:
        
        guard let view = containerView.currentBodyView else {
          return .init(0, source: snapPoint)
        }
        
        let targetSize = CGSize(
          width: bounds.width,
          height: UIView.layoutFittingCompressedSize.height
        )
        
        let horizontalPriority: UILayoutPriority = .required
        let verticalPriority: UILayoutPriority = .fittingSizeLevel
        
        let size = view.systemLayoutSizeFitting(
          targetSize,
          withHorizontalFittingPriority: horizontalPriority,
          verticalFittingPriority: verticalPriority
        )
        
        return .init(min(maxHeight, max(0, maxHeight - size.height)), source: snapPoint)
      }
    }
    
    return ResolvedConfiguration(snapPoints: points)
  }
  
  override func layoutSubviews() {
    
    super.layoutSubviews()
    
    let valueSet = CachedValueSet(
      sizeThatLastUpdated: bounds.size,
      offsetThatLastUpdated: actualTopMargin,
      usingConfiguration: configuration
    )
    
    guard oldValueSet != nil else {
      
      // First time layout
      
      oldValueSet = valueSet
      
      shouldUpdate = false
      
      let configuration = resolve(configuration: self.configuration)
      resolvedConfiguration = configuration
      
      if let initial = configuration.resolvedSnapPoints.last {
        updateLayout(target: initial)
      }
      
      return
    }
    
    guard shouldUpdate || oldValueSet != valueSet, let currentSnapPoint = currentSnapPoint else {
      // No needs to update layout
      return
    }
    
    oldValueSet = valueSet
    shouldUpdate = false
    
    let newResolvedConfiguration = resolve(configuration: configuration)
    
    guard resolvedConfiguration != newResolvedConfiguration else {
      // It had to update layout, but configuration for layot does not have changes.
      return
    }
    resolvedConfiguration = newResolvedConfiguration
    
    guard
      let snapPoint = newResolvedConfiguration.resolvedSnapPoint(by: currentSnapPoint.source) ?? newResolvedConfiguration.resolvedSnapPoints.first
      else { return }
    
    updateLayout(target: snapPoint)
    
  }
  
  func move(to snapPoint: RideauSnapPoint, animated: Bool, completion: @escaping () -> Void) {
    
    preventCurrentAnimations: do {
      
      if #available(iOS 11, *) {
        prepareAlongsideAnimators()
      }
      
      animatorStore.allAnimators()
        .forEach {
          $0.pauseAnimation()
      }
      
      containerDraggingAnimator?.stopAnimation(true)
    }
    
    guard let target = resolvedConfiguration!.resolvedSnapPoints.first(where: { $0.source == snapPoint }) else {
      assertionFailure("No such snap point")
      return
    }
    
    if animated {
      continueInteractiveTransition(target: target, velocity: .zero, completion: completion)
    } else {
      UIView.performWithoutAnimation {
        continueInteractiveTransition(target: target, velocity: .zero, completion: completion)
      }
    }
    
  }
  
  func isReachedMostTop(location: ResolvedConfiguration.Location) -> Bool {
    let result: Bool
    switch location {
    case .between:
      result = false
    case .exact(let point),
         .outOfEnd(let point),
         .outOfStart(let point):
      result = resolvedConfiguration!.isReachedMostTop(point)
    }
    return result
  }
  
  @available(iOS 11, *)
  private func prepareAlongsideAnimators() {
    
    if !hasTakenAlongsideAnimators {
      
      hasTakenAlongsideAnimators = true
      
      resolvedConfiguration?
        .ranges()
        .forEach { range in
          delegate?.rideauView(self, animatorsAlongsideMovingIn: range).forEach { animator in
            animator.pausesOnCompletion = true
            animator.pauseAnimation()
            animatorStore.set(animator: animator, for: range)
          }
      }
    }
    
  }
  
  private func currentHidingOffset(translation: CGPoint) -> CGFloat {
    
    let offset = actualTopMargin
    
    var nextValue: CGFloat
    if let v = containerView.layer.presentation().map({ $0.frame.origin.y }) {
      nextValue = v
    } else {
      nextValue = containerView.frame.origin.y
    }
    
    nextValue -= offset
    nextValue += translation.y
    
    return nextValue
  }
  
  @objc private dynamic func handlePan(gesture: UIPanGestureRecognizer) {
    
    let targetScrollView: UIScrollView? = {
      
      guard let gesture = gesture as? RideauViewDragGestureRecognizer else {
        return nil
      }
      
      switch trackingScrollViewOption {
      case .noTracking: return nil
      case .automatic: return gesture.trackingScrollView
      case .specific(let scrollView): return scrollView
      }
    }()
    
    let translation = gesture.translation(in: gesture.view!)
    
    defer {
      gesture.setTranslation(.zero, in: gesture.view!)
    }
    
    let nextOffset = currentHidingOffset(translation: translation)
    let currentOffset = currentHidingOffset(translation: .zero)
    let nextLocation = resolvedConfiguration!.currentLocation(from: nextOffset)
    let currentLocation = resolvedConfiguration!.currentLocation(from: currentOffset)
    
    switch gesture.state {
    case .began:
      
      initialLocation = currentLocation
      shouldKillDecelerate = false
      isInteracting = true
      hasReachedMostTop = false
      
      containerDraggingAnimator?.pauseAnimation()
      containerDraggingAnimator?.stopAnimation(true)
      
      if #available(iOS 11, *) {
        prepareAlongsideAnimators()
      }
      
      if let scrollView = targetScrollView {
        scrollController.startTracking(scrollView: scrollView)
        lastOffset = scrollView.contentOffset
        initialShowsVerticalScrollIndicator = scrollView.showsVerticalScrollIndicator
      }
      
      fallthrough
    case .changed:
      
      let isCurrentReachedMostTop = isReachedMostTop(location: currentLocation)
      
      hasReachedMostTop = hasReachedMostTop ? hasReachedMostTop : isCurrentReachedMostTop

      var skipsDragging = false
      
      if let scrollView = targetScrollView {
        
        let isInitialReachedMostTop = isReachedMostTop(location: initialLocation!)
        
        let isScrollingDown = gesture.velocity(in: gesture.view).y > 0
        let isScrollViewOnTop = scrollView.contentOffset.y <= -_getActualContentInset(from: scrollView).top

        skipsDragging = !isScrollViewOnTop
        
        if isScrollingDown {
          
          switch (isScrollViewOnTop, isInitialReachedMostTop, isCurrentReachedMostTop, hasReachedMostTop) {
          case (false, false, false, true):
            scrollController.resume()
            shouldKillDecelerate = true
            lastOffset = scrollView.contentOffset
            return
          case (false, false, false, false):
            scrollController.resume()
            shouldKillDecelerate = true
            scrollView.contentOffset = lastOffset
            skipsDragging = false
          case (true, true, false, _):
            shouldKillDecelerate = true
            scrollController.suspend()
            lastOffset = scrollView.contentOffset
          case (false, true, true, _):
            scrollController.resume()
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
            return
          case (false, true, false, _):
            scrollController.resume()
            shouldKillDecelerate = true
            lastOffset = scrollView.contentOffset
            return
          case (true, false, false, _):
            shouldKillDecelerate = true
            scrollController.suspend()
            lastOffset = scrollView.contentOffset
          case (false, false, true, _):
            scrollController.resume()
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
            return
          default:
            scrollController.resume()
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
            break
          }
          
        } else {
          
          if isCurrentReachedMostTop {
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
            scrollController.resume()
          } else {
            skipsDragging = false
            scrollView.contentOffset = lastOffset
            scrollController.suspend()
            shouldKillDecelerate = true
          }
        }
        
        if initialShowsVerticalScrollIndicator {
          scrollView.showsVerticalScrollIndicator = !shouldKillDecelerate
        }
        
      }

      guard !skipsDragging else {

        break
      }
      
      switch nextLocation {
      case .exact:
        
        bottomConstraint.constant = nextOffset
        heightConstraint.constant = self.maximumContainerViewHeight!
        
      case .between(let range):
        
        if #available(iOS 11, *) {
          
          let fractionCompleteInRange = ValuePatch.init(nextOffset)
            .progress(
              start: range.start.hidingOffset,
              end: range.end.hidingOffset
            )
            .clip(min: 0, max: 1)
            .reverse()
            .fractionCompleted
          
          animatorStore[range]?.forEach {
            $0.isReversed = false
            $0.pauseAnimation()
            $0.fractionComplete = fractionCompleteInRange
          }
          
          animatorStore
            .filter { $0.start > range.start }
            .forEach {
              $0.isReversed = false
              $0.pauseAnimation()
              $0.fractionComplete = 1
          }
          
          animatorStore
            .filter { $0.end < range.start }
            .forEach {
              $0.isReversed = false
              $0.pauseAnimation()
              $0.fractionComplete = 0
          }
          
        }
        
        bottomConstraint.constant = nextOffset
        heightConstraint.constant = self.maximumContainerViewHeight!
        
      case .outOfStart(let point):
        bottomConstraint.constant = point.hidingOffset
        let offset = translation.y * 0.1
        heightConstraint.constant -= offset
      case .outOfEnd(let point):
        bottomConstraint.constant = point.hidingOffset
        if targetScrollView == nil {
          let offset = translation.y * 0.1
          heightConstraint.constant -= offset
        }
      }

      if let lastOffset = targetScrollView?.contentOffset {
        self.lastOffset = lastOffset
        }
    case .ended
    , .cancelled, .failed:
      
      scrollController.endTracking()
      
      if let scrollView = targetScrollView, shouldKillDecelerate {
        // To perform task next event loop.
        DispatchQueue.main.async {
          
          var targetOffset = self.lastOffset
          let insetTop = _getActualContentInset(from: scrollView).top
          if targetOffset.y < -insetTop {
            // Workaround: sometimes, scrolling-lock may be failed. ContentOffset has a little bit negative offset.
            targetOffset.y = -insetTop
          }
          scrollView.setContentOffset(targetOffset, animated: false)
          scrollView.showsVerticalScrollIndicator = self.initialShowsVerticalScrollIndicator
        }
      }
      
      let vy = gesture.velocity(in: gesture.view!).y
      
      let target: ResolvedSnapPoint = {
        switch nextLocation {
        case .between(let range):
          
          guard let pointCloser = range.pointCloser(by: nextOffset) else {
            fatalError()
          }

          let threshold: CGFloat = 400

          debugLog("Velocity-Y: \(vy)")
          
          switch vy {
          case -threshold...threshold:
            return pointCloser
          case ...(-threshold):
            return range.start
          case threshold...:
            return range.end
          default:
            fatalError()
          }
          
        case .exact(let point),
             .outOfEnd(let point),
             .outOfStart(let point):
          return point
        }
      }()
      
      let targetTranslateY = target.hidingOffset
      
      let velocity: CGVector = {

        var initialVelocity = CGVector(
          dx: 0,
          dy: abs(abs(vy) / (targetTranslateY - nextOffset))
        )
        
        if initialVelocity.dy.isInfinite || initialVelocity.dy.isNaN {
          initialVelocity.dy = 0
        }
        
        if case .outOfStart = nextLocation {
          return .zero
        }
        
        if case .outOfEnd = nextLocation {
          return .zero
        }

        debugLog("Velocity", initialVelocity)
        return initialVelocity
      }()
      
      continueInteractiveTransition(
        target: target,
        velocity: velocity,
        completion: {
          
      })
      
      isInteracting = false
    default:
      break
    }
    
  }

  /// Update the current layout with updating the constant value of constraints.
  /// - Parameter target:
  private func updateLayout(target: ResolvedSnapPoint) {
    
    currentSnapPoint = target
    
    self.bottomConstraint.constant = target.hidingOffset
    self.heightConstraint.constant = self.maximumContainerViewHeight!
    
  }
  
  private func continueInteractiveTransition(
    target: ResolvedSnapPoint,
    velocity: CGVector,
    completion: @escaping () -> Void
    ) {
    
    willChangeSnapPoint(target.source)
    
    delegate?.rideauView(self, willMoveTo: target.source)
    
    guard let oldSnapPoint = currentSnapPoint else {
      assertionFailure()
      return
    }

    let damping = ValuePatch(velocity.dy)
      .progress(start: 0, end: 20)
      .clip(min: 0, max: 1)
      .transition(start: 1, end: 0.5)
      .value

    let topAnimator = UIViewPropertyAnimator(
      duration: 0,
      timingParameters: UISpringTimingParameters(
        damping: damping,  // Workaround : Can't use initialVelocity, initialVelocity cause strange animation that will shrink and expand subviews"
        response: 0.3,
        initialVelocity: .zero
      )
    )

    // flush pending updates
    
    layoutIfNeeded()
    
    if #available(iOS 11, *) {
      
      animatorStore
        .filter { range in
          range.start >= target
        }
        .forEach {
          $0.isReversed = false
          $0.pauseAnimation()
          if $0.fractionComplete < 1 {
            $0.continueAnimation(withTimingParameters: nil, durationFactor: 1)
          }
      }
      
      animatorStore
        .filter { range in
          range.end <= target
        }
        .forEach {
          $0.isReversed = true
          $0.pauseAnimation()
          if $0.fractionComplete < 1 {
            $0.continueAnimation(withTimingParameters: nil, durationFactor: 1)
          }
      }
      
    }
    
    topAnimator
      .addAnimations {
        self.updateLayout(target: target)
        self.layoutIfNeeded()
    }
    
    topAnimator.addCompletion { _ in
      
      self.delegate?.rideauView(self, didMoveTo: target.source)
      
      #warning("If topAnimator is stopped as force, this completion block will not be called.")
      
      completion()
      if oldSnapPoint.source != target.source {
        self.didChangeSnapPoint(target.source)
      }
    }

    topAnimator.startAnimation()
    
    containerDraggingAnimator = topAnimator
    
  }
  
}

extension RideauInternalView {
  
  private struct AnimatorStore {
    
    private var backingStore: [ResolvedSnapPointRange : [UIViewPropertyAnimator]] = [:]
    
    subscript (_ range: ResolvedSnapPointRange) -> [UIViewPropertyAnimator]? {
      get {
        return backingStore[range]
      }
      set {
        backingStore[range] = newValue
      }
    }
    
    mutating func set(animator: UIViewPropertyAnimator, for key: ResolvedSnapPointRange) {
      
      var array = self[key]
      
      if array != nil {
        array?.append(animator)
        self[key] = array
      } else {
        let array = [animator]
        self[key] = array
      }
      
    }
    
    func filter(_ condition: (ResolvedSnapPointRange) -> Bool) -> [UIViewPropertyAnimator] {
      return
        backingStore
          .filter { condition($0.key) }
          .reduce(into: [UIViewPropertyAnimator]()) { (result, args) in
            result += args.value
      }
    }
    
    func allAnimators() -> [UIViewPropertyAnimator] {
      
      return
        backingStore.reduce(into: [UIViewPropertyAnimator]()) { (result, args) in
          result += args.value
      }
      
    }
    
    mutating func removeAllAnimations() {
      backingStore.removeAll()
    }
    
  }
  
  struct ResolvedConfiguration : Equatable {
    
    // MARK: - Nested types
    
    enum Location {
      case between(ResolvedSnapPointRange)
      case exact(ResolvedSnapPoint)
      case outOfEnd(ResolvedSnapPoint)
      case outOfStart(ResolvedSnapPoint)
    }
    
    // MARK: - Properties
    
    let resolvedSnapPoints: [ResolvedSnapPoint]
    
    // MARK: - Initializers
    
    init<T : Collection>(snapPoints: T) where T.Element == ResolvedSnapPoint {
      self.resolvedSnapPoints = Set(snapPoints).sorted(by: <)
    }
    
    // MARK: - Functions
    
    func ranges() -> [ResolvedSnapPointRange] {
      
      guard resolvedSnapPoints.count >= 2 else {
        assertionFailure("")
        return []
      }
      
      var ranges: [ResolvedSnapPointRange] = []
      var before: ResolvedSnapPoint = resolvedSnapPoints.first!
      for point in resolvedSnapPoints.dropFirst() {
        let range = ResolvedSnapPointRange(before, point)
        ranges.append(range)
        before = point
      }
      
      return ranges
      
    }
    
    func isReachedMostTop(_ resolvedSnapPoint: ResolvedSnapPoint) -> Bool {
      return resolvedSnapPoints.first?.hidingOffset == resolvedSnapPoint.hidingOffset
    }
    
    func resolvedSnapPoint(by snapPoint: RideauSnapPoint) -> ResolvedSnapPoint? {
      return resolvedSnapPoints.first { $0.source == snapPoint }
    }
    
    func currentLocation(from hidingOffset: CGFloat) -> Location {
      
      if let point = resolvedSnapPoints.first(where: { $0.hidingOffset == hidingOffset }) {
        return .exact(point)
      }
      
      precondition(!resolvedSnapPoints.isEmpty)
      
      let firstHalf = resolvedSnapPoints.lazy.filter { $0.hidingOffset <= hidingOffset }
      let secondHalf = resolvedSnapPoints.lazy.filter { $0.hidingOffset >= hidingOffset }
      
      if !firstHalf.isEmpty && !secondHalf.isEmpty {
        
        return .between(ResolvedSnapPointRange(firstHalf.last!, secondHalf.first!))
      }
      
      if firstHalf.isEmpty {
        return .outOfEnd(secondHalf.first!)
      }
      
      if secondHalf.isEmpty {
        return .outOfStart(firstHalf.last!)
      }
      
      fatalError()
      
    }
  }
}

extension RideauInternalView : UIGestureRecognizerDelegate {
  
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    
    switch trackingScrollViewOption {
    case .noTracking:
      return false
    case .automatic:
      return otherGestureRecognizer.isKind(of: UIPanGestureRecognizer.self)
    case .specific(let scrollView):
      return otherGestureRecognizer.view == scrollView
    }
    
  }
}
#endif

extension UISpringTimingParameters {
  convenience init(damping: CGFloat, response: CGFloat, initialVelocity: CGVector = .zero) {
    let stiffness = pow(2 * .pi / response, 2)
    let damp = 4 * .pi * damping / response
    self.init(mass: 1, stiffness: stiffness, damping: damp, initialVelocity: initialVelocity)
  }
}
