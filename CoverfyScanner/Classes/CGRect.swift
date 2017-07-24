//
//  CGRect.swift
//  Pods
//
//  Created by Josep Bordes Jové on 24/7/17.
//
//

import Foundation

extension CGRect {
    func topLeftZone() -> CGRect {
        return CGRect(x: 0, y: 0, width: self.width / 2, height: self.height / 2)
    }
    
    func bottomLeftZone() -> CGRect {
        return CGRect(x: 0, y: self.height / 2, width: self.width / 2, height: self.height / 2)
    }
    
    func topRightZone() -> CGRect {
        return CGRect(x: self.width / 2, y: 0, width: self.width / 2, height: self.height / 2)
    }
    
    func bottomRightZone() -> CGRect {
        return CGRect(x: self.width / 2, y: self.height / 2, width: self.width / 2, height: self.height / 2)
    }
    
    func size() -> Float {
        return Float(self.height * self.width)
    }
}
