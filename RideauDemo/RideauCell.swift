//
//  RideauCell.swift
//  RideauDemo
//
//  Created by Rebouh Aymen on 26/02/2019.
//  Copyright © 2019 Hiroshi Kimura. All rights reserved.
//

import UIKit

class RideauCell: UICollectionViewCell {
  
  @IBOutlet weak var imageView: UIImageView!
  
  override func awakeFromNib() {
    super.awakeFromNib()
    
    setupShadow: do {
      layer.cornerRadius = 4
      layer.shadowColor = UIColor.black.cgColor
      layer.shadowRadius = 4
      layer.shadowOpacity = 0.3
      layer.shadowOffset =  .init(width: 4, height: 4)
      clipsToBounds = false
    }
    
    // Parallax effect when rotating the iPhone, for fun.
    setupMotions: do {
      let horizontalMotionEffect = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
      horizontalMotionEffect.minimumRelativeValue = -50
      horizontalMotionEffect.maximumRelativeValue = 50
      imageView.addMotionEffect(horizontalMotionEffect)
      
      let verticalMotionEffect = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongHorizontalAxis)
      verticalMotionEffect.minimumRelativeValue = -50
      verticalMotionEffect.maximumRelativeValue = 50
      imageView.addMotionEffect(verticalMotionEffect)
    }
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    layer.shadowPath = UIBezierPath(rect: bounds).cgPath
  }
}
