//
//  SelectRideauViewController.swift
//  RideauDemo
//
//  Created by Rebouh Aymen on 26/02/2019.
//  Copyright © 2019 Hiroshi Kimura. All rights reserved.
//

import UIKit
import Rideau

class SelectRideauViewController: UIViewController {

  @IBOutlet weak var collectionView: UICollectionView!
  
  let rideauxImages = [#imageLiteral(resourceName: "rideau1"),#imageLiteral(resourceName: "rideau6"),#imageLiteral(resourceName: "rideau2"),#imageLiteral(resourceName: "rideau3"),#imageLiteral(resourceName: "rideau5"),#imageLiteral(resourceName: "rideau4"),#imageLiteral(resourceName: "rideau7")]
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    collectionView.reloadData()
  }
}

extension SelectRideauViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout  {
  
  func numberOfSections(in collectionView: UICollectionView) -> Int {
    return 1
  }
  
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return rideauxImages.capacity
  }
  
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: RideauCell.self), for: indexPath) as! RideauCell
    
    let rideau = rideauxImages[indexPath.item]
    
    cell.imageView.image = rideau
    
    return cell
  }
  
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    return CGSize(width: collectionView.bounds.width/1.2, height: collectionView.bounds.height/1.5)
  }
}

extension SelectRideauViewController: RideauViewDelegate {
  func rideauView(_ rideauView: RideauView, alongsideAnimatorFor range: ResolvedSnapPointRange) -> UIViewPropertyAnimator? {
    return nil
  }
  
  func rideauView(_ rideauView: RideauView, willMoveTo snapPoint: RideauSnapPoint) {
    
    if snapPoint == .autoPointsFromBottom {
      collectionView.alpha = 0.8
    } else {
      collectionView.alpha = 1
    }
  }
  
  func rideauView(_ rideauView: RideauView, didMoveTo snapPoint: RideauSnapPoint) {
    collectionView.collectionViewLayout.invalidateLayout()
  }
}
