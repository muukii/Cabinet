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

import Rideau

final class MainMenuViewController : UIViewController {
  
  @IBAction func didTapShowModalButton(_ sender: Any) {
    
    let target = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "TargetViewController") as! TargetViewController
    
    let controller = RideauViewController(
      bodyViewController: target,
      configuration: {
        var config = RideauView.Configuration()
        config.snapPoints = [.hidden, .autoPointsFromBottom, .fraction(1)]
        return config
    }(),
      initialSnapPoint: .autoPointsFromBottom
    )
    
    present(controller, animated: true, completion: nil)
    
  }
  
  @IBAction func didTapShowMenuButton(_ sender: Any) {
    
    let target = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "HasScrollableContentViewController") as! HasScrollableContentViewController
    
    let controller = RideauViewController(
      bodyViewController: RideauMaskedCornerRoundedViewController(viewController: target),
      configuration: {
        var config = RideauView.Configuration()
        config.snapPoints = [.hidden, .autoPointsFromBottom, .fraction(0.6), .fraction(1)]
        return config
    }(),
      initialSnapPoint: .autoPointsFromBottom
    )
    
    controller.rideauView.delegate = target
    
    present(controller, animated: true, completion: nil)
  }
  
  @IBAction func didTapShowFullScreen(_ sender: Any) {
    
    let target = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "HasScrollableContentViewController") as! HasScrollableContentViewController
    
    let controller = RideauViewController(
      bodyViewController: target,
      configuration: {
        var config = RideauView.Configuration()
        config.snapPoints = [.hidden, .autoPointsFromBottom, .fraction(1)]
        return config
    }(),
      initialSnapPoint: .autoPointsFromBottom
    )
    
    controller.rideauView.delegate = target
    
    present(controller, animated: true, completion: nil)
    
  }
    
    @IBAction func didTapShowRideauList(_ sender: Any) {
        let target = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SelectRideauViewController") as! SelectRideauViewController
        
        let controller = RideauViewController(
            bodyViewController: target,
            configuration: {
                var config = RideauView.Configuration()
                return config
        }(),
            initialSnapPoint: .fraction(1)
        )
        
        controller.rideauView.delegate = target
        
        present(controller, animated: true, completion: nil)
    }
    
}
