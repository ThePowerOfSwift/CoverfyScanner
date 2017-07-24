//
//  CSPoint.swift
//  Pods
//
//  Created by Josep Bordes Jové on 24/7/17.
//
//

import UIKit

public struct CSRectangle {
    var topLeft: CSPoint
    var topRight: CSPoint
    var bottomLeft: CSPoint
    var bottomRight: CSPoint
    
    init() {
        self.topLeft = CSPoint(point: CGPoint(x: 0, y: 0), type: .topLeft)
        self.topRight = CSPoint(point: CGPoint(x: 0, y: 0), type: .topRight)
        self.bottomLeft = CSPoint(point: CGPoint(x: 0, y: 0), type: .bottomLeft)
        self.bottomRight = CSPoint(point: CGPoint(x: 0, y: 0), type: .bottomRight)
        
    }
    
    init(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        self.topLeft = CSPoint(point: topLeft, type: .topLeft)
        self.topRight = CSPoint(point: topRight, type: .topRight)
        self.bottomLeft = CSPoint(point: bottomLeft, type: .bottomLeft)
        self.bottomRight = CSPoint(point: bottomRight, type: .bottomRight)
    }
    
    init(rectangle: CIRectangleFeature) {
        self.topLeft = CSPoint(point: rectangle.topLeft, type: .topLeft)
        self.topRight = CSPoint(point: rectangle.topRight, type: .topRight)
        self.bottomLeft = CSPoint(point: rectangle.bottomLeft, type: .bottomLeft)
        self.bottomRight = CSPoint(point: rectangle.bottomRight, type: .bottomRight)
    }
    
    init(rectangle: CSRectangle, newPoint: CSPoint) {
        
        switch newPoint.type {
        case .topLeft:
            self.topLeft = newPoint
            self.topRight = CSPoint(point: rectangle.topRight.point, type: .topRight)
            self.bottomLeft = CSPoint(point: rectangle.bottomLeft.point, type: .bottomLeft)
            self.bottomRight = CSPoint(point: rectangle.bottomRight.point, type: .bottomRight)
            
        case .topRight:
            self.topRight = newPoint
            self.topLeft = CSPoint(point: rectangle.topLeft.point, type: .topLeft)
            self.bottomLeft = CSPoint(point: rectangle.bottomLeft.point, type: .bottomLeft)
            self.bottomRight = CSPoint(point: rectangle.bottomRight.point, type: .bottomRight)
            
        case .bottomLeft:
            self.bottomLeft = newPoint
            self.topLeft = CSPoint(point: rectangle.topLeft.point, type: .topLeft)
            self.topRight = CSPoint(point: rectangle.topRight.point, type: .topRight)
            self.bottomRight = CSPoint(point: rectangle.bottomRight.point, type: .bottomRight)
            
        case .bottomRight:
            self.bottomRight = newPoint
            self.topLeft = CSPoint(point: rectangle.topLeft.point, type: .topLeft)
            self.topRight = CSPoint(point: rectangle.topRight.point, type: .topRight)
            self.bottomLeft = CSPoint(point: rectangle.bottomLeft.point, type: .bottomLeft)
            
        }
    }
    
    func calculateRatio() -> Float {
        let heightOne: Float = Float(self.bottomRight.point.x - self.bottomLeft.point.x)
        let widthOne: Float = Float(self.topRight.point.y - self.bottomRight.point.y)
        
        if heightOne > widthOne {
            return heightOne / widthOne
        } else {
            return widthOne / heightOne
        }
    }
    
    func size() -> Float {
        let height = abs(self.topLeft.point.y - self.bottomLeft.point.y)
        let width = abs(self.topLeft.point.x - self.topRight.point.y)
        
        return Float(height * width)
    }
    
    func calculateTopAngles() -> (Float, Float) {
        return (90, 90)
    }
    
    func calculateBottomAngles() -> (Float, Float) {
        return (90, 90)
    }
    
}
