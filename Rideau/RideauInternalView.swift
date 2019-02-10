//
// Rideau
//
// Copyright (c) 2019 muukii
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

final class RideauInternalView : TouchThroughView {
  
  private struct CachedValueSet : Equatable {
    
    var sizeThatLastUpdated: CGSize
    var offsetThatLastUpdated: CGFloat
  }
  
  weak var delegate: RideauInternalViewDelegate?
  
  // Needs for internal usage
  internal var didChangeSnapPoint: (RideauSnapPoint) -> Void = { _ in }
  
  private var heightConstraint: NSLayoutConstraint!
  
  private var bottomConstraint: NSLayoutConstraint!
  
  let backdropView = TouchThroughView()
  
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
  
  private var topMargin: CGFloat {
    let offset: CGFloat
    if #available(iOS 11.0, *) {
      offset = safeAreaInsets.top + 20
    } else {
      offset = 40
    }
    return offset
  }
  
  init(
    frame: CGRect,
    configuration: RideauView.Configuration?
    ) {
    self.configuration = configuration ?? .init()
    super.init(frame: .zero)
    
  }
  
  func setup() {
    
    containerView.didChangeContent = { [weak self] in
      guard let self = self else { return }
      guard self.isInteracting == false else { return }
      // It needs to update update ResolvedConfiguration
      self.shouldUpdate = true
      self.setNeedsLayout()
      self.layoutIfNeeded()
    }
    
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
    
    gesture: do {
      
      let panGesture = ScrollPanGestureRecognizer(target: self, action: #selector(handlePan))
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
    
    #warning("TODO: Animation should not run during layout")
    
    let offset = topMargin
    
    func resolve() -> ResolvedConfiguration {

      let maxHeight = self.bounds.height - topMargin
      heightConstraint.constant = maxHeight
      self.maximumContainerViewHeight = maxHeight
      
      let points = configuration.snapPoints.map { snapPoint -> ResolvedSnapPoint in
        switch snapPoint {
        case .fraction(let fraction):
          return .init(round(maxHeight - maxHeight * fraction) + topMargin, source: snapPoint)
        case .pointsFromTop(let points):
          return .init(round(max(maxHeight, points + topMargin)), source: snapPoint)
        case .pointsFromBottom(let points):
          return .init(round(maxHeight - points + topMargin), source: snapPoint)
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
          
          return .init(min(maxHeight, max(0, maxHeight - size.height)) + topMargin, source: snapPoint)
        }
      }
      
      return ResolvedConfiguration(snapPoints: points)
    }
    
    let valueSet = CachedValueSet(
      sizeThatLastUpdated: bounds.size,
      offsetThatLastUpdated: topMargin
    )
    
    if oldValueSet == nil {
      super.layoutSubviews()
      
      oldValueSet = valueSet
            
      shouldUpdate = false
      
      let configuration = resolve()
      resolvedConfiguration = configuration
      
      if let initial = configuration.snapPoints.last {
        set(snapPoint: initial.source, animated: false, completion: {})
      }
      
      return
    }
    
    super.layoutSubviews()
    
    guard shouldUpdate || oldValueSet != valueSet else {
      return
    }
    
    oldValueSet = valueSet
    shouldUpdate = false
    
    let newConfig = resolve()
    guard resolvedConfiguration != newConfig else { return }
    resolvedConfiguration = newConfig
    
    set(snapPoint: currentSnapPoint!.source, animated: true, completion: {})
    
  }
  
  func set(snapPoint: RideauSnapPoint, animated: Bool, completion: @escaping () -> Void) {
    
    preventCurrentAnimations: do {
      
      animatorStore.allAnimators().forEach {
        $0.stopAnimation(true)
      }
      
      animatorStore.removeAllAnimations()
      
      containerDraggingAnimator?.stopAnimation(true)
    }
    
    guard let target = resolvedConfiguration!.snapPoints.first(where: { $0.source == snapPoint }) else {
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
  
  @objc private func handlePan(gesture: UIPanGestureRecognizer) {
    
    let translation = gesture.translation(in: gesture.view!)
    
    let offset = topMargin
    
    var nextValue: CGFloat
    if let v = containerView.layer.presentation().map({ $0.frame.origin.y }) {
      nextValue = v
    } else {
      nextValue = containerView.frame.origin.y
    }
    
    nextValue += translation.y
    nextValue -= offset

    nextValue.round()

    let currentLocation = resolvedConfiguration!.currentLocation(from: nextValue + offset)
    
    switch gesture.state {
    case .began:
      
      isInteracting = true
      
      containerDraggingAnimator?.pauseAnimation()
      containerDraggingAnimator?.stopAnimation(true)
      
      
      
      animatorStore.allAnimators().forEach {
        $0.pauseAnimation()
      }
      
      fallthrough
    case .changed:
      
      switch currentLocation {
      case .exact:
        
        bottomConstraint.constant = nextValue
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
        
        bottomConstraint.constant = nextValue
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
        
      case .outOf(let point):
        let offset = translation.y * 0.1
        heightConstraint.constant -= offset
      }
      
    case .ended, .cancelled, .failed:
      
      let vy = gesture.velocity(in: gesture.view!).y
      
      let target: ResolvedSnapPoint = {
        switch currentLocation {
        case .between(let range):
          
          guard let pointCloser = range.pointCloser(by: nextValue + offset) else {
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
          
        case .outOf(let point):
          return point
        }
      }()
      
      let targetTranslateY = target.pointsFromTop
      
      let velocity: CGVector = {
        
        let base = CGVector(
          dx: 0,
          dy: targetTranslateY - nextValue
        )
        
        var initialVelocity = CGVector(
          dx: 0,
          dy: min(abs(vy / base.dy), 5)
        )
        
        if initialVelocity.dy.isInfinite || initialVelocity.dy.isNaN {
          initialVelocity.dy = 0
        }
        
        if case .outOf = currentLocation {
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
    
    gesture.setTranslation(.zero, in: gesture.view!)
    
  }
  
  private func continueInteractiveTransition(
    target: ResolvedSnapPoint,
    velocity: CGVector,
    completion: @escaping () -> Void
    ) {
    
    delegate?.rideauView(self, willMoveTo: target.source)
    
    let oldSnapPoint = currentSnapPoint?.source
    currentSnapPoint = target
    
    let duration: TimeInterval = 0
    
    
    let topAnimator = UIViewPropertyAnimator(
      duration: duration,
      timingParameters: UISpringTimingParameters(
        mass: 5,
        stiffness: 2300,
        damping: 300,
        initialVelocity: .zero
      )
    )
    
    #warning("TODO: Use initialVelocity, initialVelocity affects shrink and expand animation")
    
    // flush pending updates
    
    layoutIfNeeded()
    
    topAnimator
      .addAnimations {
        self.bottomConstraint.constant = target.pointsFromTop - self.topMargin
        self.heightConstraint.constant = self.maximumContainerViewHeight!
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
  
  private struct ResolvedConfiguration : Equatable {
    
    let snapPoints: [ResolvedSnapPoint]
    
    init<T : Collection>(snapPoints: T) where T.Element == ResolvedSnapPoint {
      self.snapPoints = snapPoints.sorted(by: <)
    }
    
    enum Location {
      case between(ResolvedSnapPointRange)
      case exact(ResolvedSnapPoint)
      case outOf(ResolvedSnapPoint)
    }
    
    func currentLocation(from currentPoint: CGFloat) -> Location {
      
      if let point = snapPoints.first(where: { $0.pointsFromTop == currentPoint }) {
        return .exact(point)
      }
      
      precondition(!snapPoints.isEmpty)
      
      let firstHalf = snapPoints.lazy.filter { $0.pointsFromTop <= currentPoint }
      let secondHalf = snapPoints.lazy.filter { $0.pointsFromTop >= currentPoint }
      
      if !firstHalf.isEmpty && !secondHalf.isEmpty {
        
        return .between(ResolvedSnapPointRange(firstHalf.last!, b:  secondHalf.first!))
      }
      
      if firstHalf.isEmpty {
        return .outOf(secondHalf.first!)
      }
      
      if secondHalf.isEmpty {
        return .outOf(firstHalf.last!)
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
