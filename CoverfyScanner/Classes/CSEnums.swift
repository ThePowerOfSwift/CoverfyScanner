//
//  Enums.swift
//  DocumentScanner
//
//  Created by Josep Bordes Jové on 20/7/17.
//  Copyright © 2017 Josep Bordes Jové. All rights reserved.
//

import Foundation

public enum CSImageFilter {
    case contrast
    case none
}

public enum CSImageOrientation {
    case vertical
    case horizontal
}

public enum CSVideoFrame {
    case normal
    case fullScreen
}

public enum CSErrors: String, Error {
    case noAvSessionAvailable = "The AVSession was not created properly"
    case cannotSetFocusMode = "The focus mode cannot be set"
    case cannotSetInput = "The Device Media Input cannot be configured properly"
}
