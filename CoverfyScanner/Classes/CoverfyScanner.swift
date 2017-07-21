//
//  CoreImageVideoFilter.swift
//  DocumentScanner
//
//  Created by Josep Bordes Jové on 18/7/17.
//  Copyright © 2017 Josep Bordes Jové. All rights reserved.
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
            do {
                try toggleFlash()
            } catch {
                print(error)
            }
        }
    }
    
    private var detector: CIDetector?
    private var avSession: AVCaptureSession?
    fileprivate var applyFilter: ((CIImage) -> CIImage?)?
    
    private var detectedRectangle = CSRectangle()
    
    private let minRatio: Float
    private let maxRatio: Float
    
    fileprivate var sessionQueue: DispatchQueue
    fileprivate var videoDisplayView: GLKView
    fileprivate var videoDisplayViewBounds: CGRect
    fileprivate var renderContext: CIContext
    fileprivate var currentImage: CIImage
    
    public weak var delegate: CoverfyScannerDelegate?
    
    public init(superview: UIView, applyFilterCallback: ((CIImage) -> CIImage?)?, ratio: Float) {
        let cameraFrame = CGRect(x: -32, y: 68, width: superview.bounds.width + 64, height: superview.bounds.width + 64)
        
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
    
        if avSession == nil {
            do {
                avSession = try createAVSession()
            } catch {
                throw CSErrors.noAvSessionAvailable
            }
        }
        
        avSession?.startRunning()
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
    
    // MARK: - Detection Document Methods
    
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
    
    private func prepareRectangleDetector() -> CIDetector? {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorAspectRatio: 1.5]
        return CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: options)
    }
    
    private func drawHighlightOverlayForPoints(_ image: CIImage, _ rectangle: CSRectangle) -> CIImage {
        refreshDocumentAreaPoints(withRectangle: rectangle)
        
        var redSquareOverlay = CIImage(color: CIColor(red: 1.0, green: 0, blue: 0, alpha: 0.5))
        redSquareOverlay = redSquareOverlay.cropping(to: image.extent)
        redSquareOverlay = redSquareOverlay.applyingFilter(kCIPerspectiveTransformWithExtent, withInputParameters:
            [
                kCIInputExtent: CIVector(cgRect: image.extent),
                kCIInputTopLeft: CIVector(cgPoint: detectedRectangle.topLeft),
                kCIInputTopRight: CIVector(cgPoint: detectedRectangle.topRight),
                kCIInputBottomLeft: CIVector(cgPoint: detectedRectangle.bottomLeft),
                kCIInputBottomRight: CIVector(cgPoint: detectedRectangle.bottomRight)
            ])
        
        return redSquareOverlay.compositingOverImage(image)
    }
    
    private func refreshDocumentAreaPoints(withRectangle rectangle: CSRectangle) {
        let ratio = rectangle.calculateRatio()
        
        captureProgress += 1
        
        if ratio > maxRatio || ratio < minRatio {
            return
        }
        
        detectedRectangle.topLeft = shouldRefreshPoint(previous: detectedRectangle.topLeft, actual: rectangle.topLeft)
        detectedRectangle.topRight = shouldRefreshPoint(previous: detectedRectangle.topRight, actual: rectangle.topRight)
        detectedRectangle.bottomLeft = shouldRefreshPoint(previous: detectedRectangle.bottomLeft, actual: rectangle.bottomLeft)
        detectedRectangle.bottomRight = shouldRefreshPoint(previous: detectedRectangle.bottomRight, actual: rectangle.bottomRight)
    }
    
    // MARK: - ConfigurationMethods
    
    public func changeVideoDisplayFrame(_ frame: CGRect) {
        UIView.animate(withDuration: 0.7) {
            self.videoDisplayView.frame = frame
        }
    }
    
    private func toggleFlash() throws {
        guard let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo) else { return }
        
        if device.hasTorch {
            do {
                try device.lockForConfiguration()
                
                if (device.torchMode == AVCaptureTorchMode.on) {
                    device.torchMode = AVCaptureTorchMode.off
                } else {
                    if self.isFlashActive {
                        try device.setTorchModeOnWithLevel(1.0)
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                throw error
            }
        }
        
    }
    
    // MARK: - Helper Methods
    
    private func shouldRefreshPoint(previous: CGPoint, actual: CGPoint) -> CGPoint {
        if abs(previous.x - actual.x) > 20 {
            if abs(previous.x - actual.x) > 17 { captureProgress = captureProgress > 0 ? captureProgress - 2 : captureProgress }
            return actual
        }
        
        if abs(previous.y - actual.y) > 20 {
            if abs(previous.y - actual.y) > 17 { captureProgress = captureProgress > 0 ? captureProgress - 2 : captureProgress }
            return actual
        }
        
        return previous
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
