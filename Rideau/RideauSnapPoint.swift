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
import Foundation
import UIKit

public enum RideauSnapPoint : Hashable {
  
  case fraction(CGFloat)
  case pointsFromTop(CGFloat)
  case pointsFromBottom(CGFloat)
  case autoPointsFromBottom
  
  public static let hidden: RideauSnapPoint = .pointsFromBottom(-8)
  public static let full: RideauSnapPoint = .fraction(1)
}

public struct ResolvedSnapPoint : Hashable, Comparable {
  public static func < (lhs: ResolvedSnapPoint, rhs: ResolvedSnapPoint) -> Bool {
    return lhs.hidingOffset < rhs.hidingOffset
  }
  
  let hidingOffset: CGFloat
  
  public let source: RideauSnapPoint
  
  init(_ pointsFromSafeAreaTop: CGFloat, source: RideauSnapPoint) {
    self.hidingOffset = pointsFromSafeAreaTop.rounded()
    self.source = source
  }
}

public struct ResolvedSnapPointRange : Hashable {
  
  /// Direction to more visible
  public let start: ResolvedSnapPoint
  /// Direction to more invisible
  public let end: ResolvedSnapPoint
  
  init(_ a: ResolvedSnapPoint, _ b: ResolvedSnapPoint) {
    
    if a < b {
      self.start = a
      self.end = b
    } else {
      self.start = b
      self.end = a
    }
    
  }
  
  public func pointCloser(by point: CGFloat) -> ResolvedSnapPoint? {
    
    if (start.hidingOffset ... end.hidingOffset).contains(point) {
      
      let first = abs(point - start.hidingOffset)
      let second = abs(end.hidingOffset - point)
      
      if first > second {
        return end
      } else {
        return start
      }
      
    } else {
      return nil
    }
  }
  
}

extension RideauSnapPoint: ExpressibleByFloatLiteral {
  
  public init(floatLiteral value: Double) {
    self = .fraction(CGFloat(value))
  }
  
}

#endif
