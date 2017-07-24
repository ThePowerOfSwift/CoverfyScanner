//
//  CSPoint.swift
//  Pods
//
//  Created by Josep Bordes Jové on 24/7/17.
//
//

import Foundation

struct CSPoint {
    var point: CGPoint
    let type: CSPointType
    
    init(point: CGPoint, type: CSPointType) {
        self.point = point
        self.type = type
    }
}
