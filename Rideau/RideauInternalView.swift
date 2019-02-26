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

import UIKit

protocol RideauInternalViewDelegate : class {
  
  func rideauView(_ rideauInternalView: RideauInternalView, alongsideAnimatorFor range: ResolvedSnapPointRange) -> UIViewPropertyAnimator?
  
  func rideauView(_ rideauInternalView: RideauInternalView, willMoveTo snapPoint: RideauSnapPoint)
  
  func rideauView(_ rideauInternalView: RideauInternalView, didMoveTo snapPoint: RideauSnapPoint)
  
}

final class RideauInternalView : RideauTouchThroughView {
  
  // MARK: - Nested types
  
  private struct CachedValueSet : Equatable {
    
    var sizeThatLastUpdated: CGSize
    var offsetThatLastUpdated: CGFloat
  }
  
  // MARK: - Properties
  
  weak var delegate: RideauInternalViewDelegate?
  
  // Needs for internal usage
  internal var willChangeSnapPoint: (RideauSnapPoint) -> Void = { _ in }
  internal var didChangeSnapPoint: (RideauSnapPoint) -> Void = { _ in }
  
  private var actualTopMargin: CGFloat {
    switch configuration.topMargin {
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
  
  let backdropView = RideauTouchThroughView()
  
  public let containerView = RideauContainerView()
  
  public let configuration: RideauView.Configuration
  
  private var resolvedConfiguration: ResolvedConfiguration?
  
  private var containerDraggingAnimator: UIViewPropertyAnimator?
  
  private var animatorStore: AnimatorStore = .init()
  
  private var currentSnapPoint: ResolvedSnapPoint?
  
  private var maximumContainerViewHeight: CGFloat?
  
  private var isInteracting: Bool = false
  
  private var shouldUpdate: Bool = false
  
  private var oldValueSet: CachedValueSet?
  
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
      
      let panGesture = RideauViewDragGestureRecognizer()
      panGesture.addTarget(self, action: #selector(handlePan))
      panGesture.delegate = self
      containerView.addGestureRecognizer(panGesture)
    }
    
  }
  
  @available(*, unavailable)
  required init?(coder aDecoder: NSCoder) {
    fatalError()
  }
  
  // MARK: - Functions
  
  override func layoutSubviews() {
    
    func resolve() -> ResolvedConfiguration {

      let maxHeight = self.bounds.height - actualTopMargin
      heightConstraint.constant = maxHeight
      self.maximumContainerViewHeight = maxHeight
      
      let points = configuration.snapPoints.map { snapPoint -> ResolvedSnapPoint in
        switch snapPoint {
        case .fraction(let fraction):
          return .init(round(maxHeight - maxHeight * fraction), source: snapPoint)
        case .pointsFromTop(let points):
          return .init(round(max(maxHeight, points)), source: snapPoint)
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
    
    let valueSet = CachedValueSet(
      sizeThatLastUpdated: bounds.size,
      offsetThatLastUpdated: actualTopMargin
    )
    
    super.layoutSubviews()
    
    guard oldValueSet != nil else {
      
      // First time layout
      
      oldValueSet = valueSet
      
      shouldUpdate = false
      
      let configuration = resolve()
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
    
    let newResolvedConfiguration = resolve()
    
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
      
      animatorStore.allAnimators().forEach {
        $0.stopAnimation(true)
      }
      
      animatorStore.removeAllAnimations()
      
      containerDraggingAnimator?.stopAnimation(true)
    }
    
    guard let target = resolvedConfiguration!.resolvedSnapPoints.first(where: { $0.source == snapPoint }) else {
      assertionFailure("Not found such as snappoint")
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
    case .exact(let point):
      result = resolvedConfiguration!.isReachedMostTop(point)
    case .between:
      result = false
    case .outOfEnd(let point):
      result = resolvedConfiguration!.isReachedMostTop(point)
    case .outOfStart(let point):
      result = resolvedConfiguration!.isReachedMostTop(point)
    }
    return result
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
  
  private var lastOffset: CGPoint!
  private var shouldKillDecelerate: Bool = false
  private var initialLocation: ResolvedConfiguration.Location?
  private var hasReachedMostTop: Bool = false
  private var initialShowsVerticalScrollIndicator: Bool = false
  
  @objc private func handlePan(gesture: RideauViewDragGestureRecognizer) {
    
    // If we are scrolling horizontally, we skip the rideau pan gesture
    if gesture.trackingScrollView?.bounds.height ==  gesture.trackingScrollView?.contentSize.height && (gesture.trackingScrollView?.isDragging == true || gesture.trackingScrollView?.isDecelerating == true) {
      return
    }
    
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
      
      animatorStore.allAnimators().forEach {
        $0.pauseAnimation()
      }
      
      if let scrollView = gesture.trackingScrollView {
        lastOffset = scrollView.contentOffset
        initialShowsVerticalScrollIndicator = scrollView.showsVerticalScrollIndicator
      }
      
      fallthrough
    case .changed:
      
      let isInitialReachedMostTop = isReachedMostTop(location: initialLocation!)
      let isCurrentReachedMostTop = isReachedMostTop(location: currentLocation)
      
      hasReachedMostTop = hasReachedMostTop ? hasReachedMostTop : isCurrentReachedMostTop
      
      if let scrollView = gesture.trackingScrollView {
        
        let isScrollingDown = gesture.velocity(in: gesture.view).y > 0
        let isScrollViewOnTop = scrollView.contentOffset.y <= _getActualContentInset(from: scrollView).top

        if isScrollingDown {
          
          switch (isScrollViewOnTop, isInitialReachedMostTop, isCurrentReachedMostTop, hasReachedMostTop) {
          case (false, false, false, true):
            shouldKillDecelerate = true
            lastOffset = scrollView.contentOffset
            return
          case (false, false, false, false):
            shouldKillDecelerate = true
            scrollView.contentOffset = lastOffset!
          case (true, true, false, _):
            shouldKillDecelerate = true
            scrollView.contentOffset.y = _getActualContentInset(from: scrollView).top
            lastOffset = scrollView.contentOffset
          case (false, true, true, _):
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
            return
          case (true, false, false, _):
            shouldKillDecelerate = true
            scrollView.contentOffset.y = _getActualContentInset(from: scrollView).top
            lastOffset = scrollView.contentOffset
          case (false, true, false, _):
            shouldKillDecelerate = true
            lastOffset = scrollView.contentOffset
            return
          case (false, false, true, _):
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
            return
          default:
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
            break
          }
          
        } else {

          if isCurrentReachedMostTop {
            shouldKillDecelerate = false
            lastOffset = scrollView.contentOffset
          } else {
            scrollView.contentOffset = lastOffset!
            shouldKillDecelerate = true
          }
        }
        
        if initialShowsVerticalScrollIndicator {
          scrollView.showsVerticalScrollIndicator = !shouldKillDecelerate
        }
        
      }
      
      switch nextLocation {
      case .exact:
        
        bottomConstraint.constant = nextOffset
        heightConstraint.constant = self.maximumContainerViewHeight!
        
      case .between(let range):
        
//        let fractionCompleteInRange = CalcBox.init(topConstraint.constant)
//          .progress(
//            start: range.start.pointsFromTop,
//            end: range.end.pointsFromTop
//          )
//          .clip(min: 0, max: 1)
//          .value
//          .fractionCompleted
        
        bottomConstraint.constant = nextOffset
        heightConstraint.constant = self.maximumContainerViewHeight!
        
//        animatorStore[range]?.forEach {
//          $0.isReversed = false
//          $0.pauseAnimation()
////          $0.fractionComplete = fractionCompleteInRange
//        }
//
//        animatorStore.animators(after: range).forEach {
//          $0.isReversed = false
//          $0.pauseAnimation()
//          $0.fractionComplete = 0
//        }
//
//        animatorStore.animators(before: range).forEach {
//          $0.isReversed = false
//          $0.pauseAnimation()
//          $0.fractionComplete = 1
//        }
        
      case .outOfStart(let point):
        bottomConstraint.constant = point.hidingOffset
        let offset = translation.y * 0.1
        heightConstraint.constant -= offset
      case .outOfEnd(let point):
        bottomConstraint.constant = point.hidingOffset
        if gesture.trackingScrollView == nil {
          let offset = translation.y * 0.1
          heightConstraint.constant -= offset
        }
      }
      
      lastOffset = gesture.trackingScrollView?.contentOffset
      
    case .ended, .cancelled, .failed:
      
      if let scrollView = gesture.trackingScrollView, shouldKillDecelerate {
        DispatchQueue.main.async {
          scrollView.setContentOffset(self.lastOffset!, animated: false)
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
          
          switch vy {
          case -20...20:
            return pointCloser
          case ...(-20):
            return range.start
          case 20...:
            return range.end
          default:
            fatalError()
          }
          
        case .exact(let point):
          return point
          
        case .outOfEnd(let point):
          return point
          
        case .outOfStart(let point):
          return point
        }
      }()
      
      let targetTranslateY = target.hidingOffset
      
      let velocity: CGVector = {
        
        let base = CGVector(
          dx: 0,
          dy: targetTranslateY - nextOffset
        )
        
        var initialVelocity = CGVector(
          dx: 0,
          dy: min(abs(vy / base.dy), 5)
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
    
    let oldSnapPoint = currentSnapPoint?.source
    
    let duration: TimeInterval = 0
    
    let topAnimator = UIViewPropertyAnimator(
      duration: duration,
      timingParameters: UISpringTimingParameters(
        mass: 300,
        stiffness: 160000,
        damping: max(0, 18000 - (1300 * velocity.dy)), // Workaround : Can't use initialVelocity, initialVelocity cause strange animation that will shrink and expand subviews"
        initialVelocity: .zero
        )
    )
    
    // flush pending updates
    
    layoutIfNeeded()
    
    topAnimator
      .addAnimations {
        self.updateLayout(target: target)
        self.layoutIfNeeded()
    }
    
    topAnimator.addCompletion { _ in
      
      self.delegate?.rideauView(self, didMoveTo: target.source)
      
      #warning("If topAnimator is stopped as force, this completion block will not be called.")
      
      completion()
      if oldSnapPoint != target.source {
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
    
    func animators(after: ResolvedSnapPointRange) -> [UIViewPropertyAnimator] {
      
      return backingStore
        .filter { $0.key.end < after.start }
        .reduce(into: [UIViewPropertyAnimator]()) { (result, args) in
          result += args.value
      }
      
    }
    
    func animators(before: ResolvedSnapPointRange) -> [UIViewPropertyAnimator] {
      
      return backingStore
        .filter { $0.key.start >= before.start }
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
        
        return .between(ResolvedSnapPointRange(firstHalf.last!, b:  secondHalf.first!))
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
    return true
  }
}
