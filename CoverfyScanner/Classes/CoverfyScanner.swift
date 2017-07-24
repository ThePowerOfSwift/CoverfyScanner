//
//  CSPoint.swift
//  Pods
//
//  Created by Josep Bordes Jové on 24/7/17.
//
//

import UIKit
import GLKit
import AVFoundation
import CoreMedia
import CoreImage
import OpenGLES
import QuartzCore

public protocol CoverfyScannerDelegate: class {
    func getCapturedImageFiltered(_ image: UIImage?)
    func getCapturingProgress(_ progress: Float?)
}

public class CoverfyScanner: NSObject {
    
    private var captureProgress: Float = 0 {
        didSet {
            delegate?.getCapturingProgress(self.captureProgress * 4 / 100)
        }
    }
    
    public var isBlackFilterActivated = false {
        didSet {
            self.captureProgress = 0
        }
    }
    
    public var isFlashActive = false {
        didSet {
            toggleFlash()
        }
    }
    
    private var detector: CIDetector?
    private var avSession: AVCaptureSession?
    fileprivate var applyFilter: ((CIImage) -> CIImage?)?
    
    private var detectedRectangle = CSRectangle()
    
    private let ratio: Float
    private let minRatio: Float
    private let maxRatio: Float
    private let superViewFrame: CGRect
    
    fileprivate var sessionQueue: DispatchQueue
    fileprivate var videoDisplayView: GLKView
    fileprivate var videoDisplayViewBounds: CGRect
    fileprivate var renderContext: CIContext
    fileprivate var currentImage: CIImage
    
    public weak var delegate: CoverfyScannerDelegate?
    
    public init(superview: UIView, videoFrameOption: CSVideoFrame, applyFilterCallback: ((CIImage) -> CIImage?)?, ratio: Float) {
        let cameraFrame = CoverfyScanner.calculateFrameForScreenOption(videoFrameOption, superview.frame)
        
        self.superViewFrame = superview.frame
        
        self.ratio = ratio
        self.minRatio = ratio - 0.2
        self.maxRatio = ratio + 0.2
        self.applyFilter = applyFilterCallback
        
        self.videoDisplayView = GLKView(frame: cameraFrame, context: EAGLContext(api: .openGLES2))
        self.videoDisplayView.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))
        self.videoDisplayView.bindDrawable()
        
        self.renderContext = CIContext(eaglContext: videoDisplayView.context)

        self.videoDisplayViewBounds = CGRect(x: 0, y: 0, width: videoDisplayView.drawableWidth, height: videoDisplayView.drawableHeight)
        
        self.sessionQueue = DispatchQueue(label: "AVSessionQueue", attributes: [])
        
        self.currentImage = CIImage()
        
        superview.addSubview(videoDisplayView)
        superview.sendSubview(toBack: videoDisplayView)
    }
    
    public init(superview: UIView, applyFilterCallback: ((CIImage) -> CIImage?)?, ratio: Float) {
        let cameraFrame = CoverfyScanner.calculateFrameForScreenOption(.normal, superview.frame)
        
        self.superViewFrame = superview.frame
        
        self.ratio = ratio
        self.minRatio = ratio - 0.2
        self.maxRatio = ratio + 0.2
        self.applyFilter = applyFilterCallback
        
        self.videoDisplayView = GLKView(frame: cameraFrame, context: EAGLContext(api: .openGLES2))
        self.videoDisplayView.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))
        self.videoDisplayView.bindDrawable()
        
        self.renderContext = CIContext(eaglContext: videoDisplayView.context)
        
        self.videoDisplayViewBounds = CGRect(x: 0, y: 0, width: videoDisplayView.drawableWidth, height: videoDisplayView.drawableHeight)
        
        self.sessionQueue = DispatchQueue(label: "AVSessionQueue", attributes: [])
        
        self.currentImage = CIImage()
        
        superview.addSubview(videoDisplayView)
        superview.sendSubview(toBack: videoDisplayView)
    }
    
    deinit {
        stop()
    }
    
    
    // MARK: - Scanner Control Methods
    
    public func start() throws {
        do {
            try activateScannerDetection()
        } catch {
            throw error
        }
    }
    
    public func stop() {
        avSession?.stopRunning()
    }
    
    public func configure() {
        detector = prepareRectangleDetector()
        
        self.applyFilter = { image in
            self.currentImage = image
            
            return self.performRectangleDetection(image: image)
        }
    }
    
    public func captureImage(withFilter filter: CSImageFilter, andOrientation orientation: CSImageOrientation) {
        var image: UIImage? = UIImage()
        
        switch filter {
        case .contrast:
            image = self.currentImage.cropWithColorContrast(withRectangle: self.detectedRectangle, preferredOrientation: orientation)
        case .none:
            image = self.currentImage.crop(withRectangle: self.detectedRectangle, preferredOrientation: orientation)
        }
        
        self.captureProgress = 0
        delegate?.getCapturedImageFiltered(image)
    }
    
    public func captureImage(withOrientation orientation: CSImageOrientation) {
        var image: UIImage? = UIImage()
        image = self.currentImage.crop(withRectangle: self.detectedRectangle, preferredOrientation: orientation)
        
        self.captureProgress = 0
        delegate?.getCapturedImageFiltered(image)
    }
    
    // MARK: - Scanner setup methods
    
    private func prepareAvSession() throws {
        if avSession == nil {
            do {
                avSession = try createAVSession()
            } catch {
                throw CSErrors.noAvSessionAvailable
            }
        }
        
        avSession?.startRunning()
    }
    
    private func createAVSession() throws -> AVCaptureSession {
        // Set the input media as Video Input from the device
        guard let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo) else { throw CSErrors.noAvSessionAvailable }
        
        try device.lockForConfiguration()
        device.focusMode = .continuousAutoFocus
        device.unlockForConfiguration()
        
        let input = try AVCaptureDeviceInput(device: device)
        
        // Set the image mode as High Quality
        let session = AVCaptureSession()
        session.sessionPreset = AVCaptureSessionPreset1920x1080
        
        // Configure the video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        
        // Join it all together
        session.addInput(input)
        session.addOutput(videoOutput)
        
        return session
    }
    
    private static func calculateFrameForScreenOption(_ frameOption: CSVideoFrame, _ viewFrame: CGRect) -> CGRect {
        
        switch frameOption {
        case .fullScreen:
            let topMargin: CGFloat = 20
            let bottomMargin: CGFloat = 0
            
            let width = viewFrame.width
            let height = viewFrame.height - topMargin - bottomMargin
            
            let doubledDifference = height - width
            let simpleDifference = doubledDifference / 2
            
            return CGRect(x: -simpleDifference, y: topMargin, width: width + doubledDifference, height: width + doubledDifference)
        case .square:
            let topMargin: CGFloat = 70
            
            let width = viewFrame.width
            let heigh = viewFrame.width
            
            return CGRect(x: 0, y: topMargin, width: width, height: heigh)
        case .normal:
            let topMargin: CGFloat = 70
            let bottomMargin: CGFloat = 120
            
            let width = viewFrame.width
            let height = viewFrame.height - topMargin - bottomMargin
            
            let doubledDifference = height - width
            let simpleDifference = doubledDifference / 2
            
            return CGRect(x: -simpleDifference, y: topMargin, width: width + doubledDifference, height: width + doubledDifference)
        }
        
    }
    
    // MARK: - Document Detection Setup
    
    private func prepareRectangleDetector() -> CIDetector? {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorAspectRatio: 1.5]
        return CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: options)
    }
    
    // MARK: - Document Detection Methods
    
    private func performRectangleDetection(image: CIImage) -> CIImage? {
        var resultImage: CIImage?
        
        if let detector = detector {
            let features = detector.features(in: image)
            
            for feature in features as! [CIRectangleFeature] {
                let rectangle = CSRectangle(rectangle: feature)
                resultImage = drawHighlightOverlayForPoints(image, rectangle)
            }
        }
        
        return resultImage
    }
    
    private func drawHighlightOverlayForPoints(_ image: CIImage, _ rectangle: CSRectangle) -> CIImage {
        refreshDocumentAreaPoints(withRectangle: rectangle)
        
        var redSquareOverlay = CIImage(color: CIColor(red: 1.0, green: 0, blue: 0, alpha: 0.5))
        redSquareOverlay = redSquareOverlay.cropping(to: image.extent)
        redSquareOverlay = redSquareOverlay.applyingFilter(kCIPerspectiveTransformWithExtent, withInputParameters:
            [
                kCIInputExtent: CIVector(cgRect: image.extent),
                kCIInputTopLeft: CIVector(cgPoint: detectedRectangle.topLeft.point),
                kCIInputTopRight: CIVector(cgPoint: detectedRectangle.topRight.point),
                kCIInputBottomLeft: CIVector(cgPoint: detectedRectangle.bottomLeft.point),
                kCIInputBottomRight: CIVector(cgPoint: detectedRectangle.bottomRight.point)
            ])
        
        return redSquareOverlay.compositingOverImage(image)
    }
    
    // MARK: Document Detection Points Correction
    
    private func refreshDocumentAreaPoints(withRectangle rectangle: CSRectangle) {
        let ratio = rectangle.calculateRatio()
        
        captureProgress += 1
        
        if ratio > maxRatio || ratio < minRatio {
            return
        }
        
        detectedRectangle.topLeft.point = shouldRefreshPoint(previous: detectedRectangle.topLeft, actual: rectangle.topLeft)
        detectedRectangle.topRight.point = shouldRefreshPoint(previous: detectedRectangle.topRight, actual: rectangle.topRight)
        detectedRectangle.bottomLeft.point = shouldRefreshPoint(previous: detectedRectangle.bottomLeft, actual: rectangle.bottomLeft)
        detectedRectangle.bottomRight.point = shouldRefreshPoint(previous: detectedRectangle.bottomRight, actual: rectangle.bottomRight)
    }
    
    private func shouldRefreshPoint(previous: CSPoint, actual: CSPoint) -> CGPoint {
        if !passPointsPosition(actual) {
            return previous.point
        }
        
        if !passRatio(previous, actual) {
            return previous.point
        }
        
        if !passAbsoluteMovement(previous, actual) {
            if abs(previous.point.x - actual.point.x) > 17 { captureProgress = captureProgress > 0 ? captureProgress - 2 : captureProgress }
            return previous.point
        }
        
        if !passDocumentSize(actual) {
            return previous.point
        }
        
        if !passAnglesRules(actual) {
            return previous.point
        }
        
        return actual.point
    }
    
    private func passPointsPosition(_ actual: CSPoint) -> Bool {
        var frame: CGRect = CGRect()
        
        switch actual.type {
        case .topLeft:
            frame = superViewFrame.topLeftZone()
        
        case .topRight:
            frame = superViewFrame.topRightZone()
            
        case .bottomLeft:
            frame = superViewFrame.bottomLeftZone()
            
        case .bottomRight:
            frame = superViewFrame.bottomRightZone()
            
        }
        
        return actual.point.isInside(frame)
    }
    
    private func passRatio(_ previous: CSPoint, _ actual: CSPoint) -> Bool {
        let actualRectangleRatio = CSRectangle(rectangle: self.detectedRectangle, newPoint: actual).calculateRatio()
        
        if actualRectangleRatio > self.minRatio && actualRectangleRatio < maxRatio {
            return true
        }
        
        return false
    }
    
    private func passAbsoluteMovement(_ previous: CSPoint, _ actual: CSPoint) -> Bool {
        let xMovement = abs(previous.point.x - actual.point.x)
        let yMovement = abs(previous.point.y - actual.point.y)
        
        let movementError: CGFloat = 10
        
        let xMovementPercentage = xMovement / superViewFrame.width * 100
        let yMovementPercentage = yMovement / superViewFrame.height * 100
        
        if  xMovementPercentage > movementError {
            return false
        }
        
        if  yMovementPercentage > movementError {
            return false
        }
        
        return true
    }
    
    private func passDocumentSize( _ actual: CSPoint) -> Bool {
        let rectangleWithNewPoint = CSRectangle(rectangle: self.detectedRectangle, newPoint: actual)
        
        let newRectangleSize = rectangleWithNewPoint.size()
        let superviewSize = superViewFrame.size()
        
        let occupation = (newRectangleSize / superviewSize) * 100
        
        if occupation < 60 {
            return false
        }
        
        return true
    }
    
    private func passAnglesRules(_ actual: CSPoint) -> Bool {
        let newRectangle = CSRectangle(rectangle: self.detectedRectangle, newPoint: actual)
        let angleError: Float = 10
        
        switch actual.type {
        case .topLeft, .topRight:
            let (alphaOne,alphaTwo) = newRectangle.calculateTopAngles()
            
            if alphaOne - alphaTwo > angleError {
                return false
            }
        case .bottomLeft, .bottomRight:
            let (alphaThree,alphaFour) = newRectangle.calculateBottomAngles()
            
            if alphaThree - alphaFour > angleError {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - ConfigurationMethods
    
    public func changeVideoDisplayFrame(_ frame: CGRect) {
        UIView.animate(withDuration: 0.7) {
            self.videoDisplayView.frame = frame
        }
    }
    
    private func toggleFlash() {
        guard let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo) else { return }
        
        if device.hasTorch {
            do {
                try device.lockForConfiguration()
                
                if self.isFlashActive {
                    try device.setTorchModeOnWithLevel(1.0)
                } else {
                    device.torchMode = AVCaptureTorchMode.off
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Toggle Flas: \(error.localizedDescription)")
            }
        }
        
    }
    
    // MARK: - Helper Methods
    
    private func activateScannerDetection() throws {
        // TODO: - Implement a timer that activates the detection
        do {
            try prepareAvSession()
        } catch {
            throw error
        }
    }

}

//MARK: AVCaptureVideoDataOutputSampleBufferDelegate

extension CoverfyScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        // Need to shimmy this through type-hell
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Force the type change - pass through opaque buffer
        let opaqueBuffer = Unmanaged<CVImageBuffer>.passUnretained(imageBuffer).toOpaque()
        let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueBuffer).takeUnretainedValue()
        
        var sourceImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        
        if isBlackFilterActivated {
            guard let blackAndWhiteImage = sourceImage.filterImageUsingContrastFilter() else { return }
            sourceImage = blackAndWhiteImage
        }
        
        // Do some detection on the image
        let detectionResult = applyFilter?(sourceImage)
        var outputImage = sourceImage
        
        if let detectionResult = detectionResult {
            outputImage = detectionResult
        }
                
        // Do some clipping
        var drawFrame = outputImage.extent
        let imageAR = drawFrame.width / drawFrame.height
        let viewAR = videoDisplayViewBounds.width / videoDisplayViewBounds.height
        
        if imageAR > viewAR {
            drawFrame.origin.x += (drawFrame.width - drawFrame.height * viewAR) / 2.0
            drawFrame.size.width = drawFrame.height / viewAR
        } else {
            drawFrame.origin.y += (drawFrame.height - drawFrame.width / viewAR) / 2.0
            drawFrame.size.height = drawFrame.width / viewAR
        }
        
        videoDisplayView.bindDrawable()
        if videoDisplayView.context != EAGLContext.current() {
            EAGLContext.setCurrent(videoDisplayView.context)
        }
        
        // clear eagl view to grey
        glClearColor(0.5, 0.5, 0.5, 1.0)
        glClear(0x00004000)
        
        // set the blend mode to "source over" so that CI will use that
        glEnable(0x0BE2)
        glBlendFunc(1, 0x0303)
        
        renderContext.draw(outputImage, in: videoDisplayViewBounds, from: drawFrame)
        
        videoDisplayView.display()
    }
}
