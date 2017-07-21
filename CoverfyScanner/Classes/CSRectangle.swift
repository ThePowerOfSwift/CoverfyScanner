//
//  Model.swift
//  DocumentScanner
//
//  Created by Josep Bordes Jové on 20/7/17.
//  Copyright © 2017 Josep Bordes Jové. All rights reserved.
//

import UIKit

public struct CSRectangle {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
    
    init() {
        self.topLeft = CGPoint(x: 0, y: 0)
        self.topRight = CGPoint(x: 0, y: 0)
        self.bottomLeft = CGPoint(x: 0, y: 0)
        self.bottomRight = CGPoint(x: 0, y: 0)
    }
    
    init(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
    
    init(rectangle: CIRectangleFeature) {
        self.topLeft = rectangle.topLeft
        self.topRight = rectangle.topRight
        self.bottomLeft = rectangle.bottomLeft
        self.bottomRight = rectangle.bottomRight
    }
    
    func calculateRatio() -> Float {
        let heightOne: Float = Float(self.bottomRight.x - self.bottomLeft.x)
        let widthOne: Float = Float(self.topRight.y - self.bottomRight.y)
        
        if heightOne > widthOne {
            return heightOne / widthOne
        } else {
            return widthOne / heightOne
        }
    }
    
}
