//
//  ViewController.swift
//  OpenGLTesting
//
//  Created by Nathan Rowbottom on 2018-04-19.
//  Copyright © 2018 Nathan Rowbottom. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation
import CoreMotion
import CoreGraphics

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    
    //MARK: outlets
    @IBOutlet weak var cameraView: UIView!
    
    enum DetectionModes {
        case YUV420v
        case BGRA
    }
    
    enum OperationState {
        case CALIBRATION
        case DETECTION
        case OTHER
    }
    //MARK: Variables
    var currentState : OperationState = .CALIBRATION
    
    let motionManager = CMMotionManager()
    
    var timer:Timer!;
    
    

    //-------Intensity --------------
    let INITIAL_INTENSITY = CGFloat(125)
    
    var successFrames = 4//this is the number of frames used in calibration
    

    var droppedFrames = 0
    var numFrames = 0
    var numEvents = 0
    var accData = (x: 0.0, y: 0.0, z:-1.0)
    var isFlat: Bool = false
    var timeStarted = CFAbsoluteTimeGetCurrent()
    var timeElapsed = CFAbsoluteTimeGetCurrent()
    var flux : Double = 0
    let detectionMode = DetectionModes.YUV420v
    var pixelsToSkip : Int = 4
    var xPixelsToSkip : Int = 8 //set in view did load
    //moved this to the outside
    var scale = UIScreen.main.scale
    var newFrame = CGRect(x: 0, y: 0, width: 100, height:100 )//this is for displaying the image on the view
   // var cameraFrame = CGRect(x: 0, y: 0, width: 100, height: 100)//this is for knowing the scale of the camera
    var intensityThreshholds = [
        (DetectionModes.BGRA, CGFloat(450.0)),//350 high 2 frameskip
        (DetectionModes.YUV420v, CGFloat(150))
        
    ]
    //var numActivePixels : Int = 0//BELOW use this to measure home many pixels were above the threshold
    let intensityMagnifier : CGFloat = 1.5;//use this to magnify the insensity value to make it easier to see
    //make the queue for the frames
    let imageQueue = DispatchQueue(label:"ca.hdsb.solta.queue")
    
    
    //MARK: object construction
    lazy var glContext: EAGLContext = {
        let glContext = EAGLContext(api: .openGLES3)
        return glContext!
    }()
    
    //GLKView is used for views that use OpenGL ES
    lazy var glView: GLKView = {
        let glView = GLKView(frame: CGRect(x: 0, y: 0, width: self.cameraView.bounds.width, height: self.cameraView.bounds.height), context: self.glContext)
        glView.bindDrawable() //bind the glView to the OpenGl instance.  Maybe need to switch this to the GLKViewController
    
        return glView
    }()
    
    //CIContext is used for image processing
    lazy var ciContext: CIContext = {
        let ciContext = CIContext(eaglContext: self.glContext)
        return ciContext
    }()
    
    //-------Cropping ---------------
    var successfulCropRect = CGRect(x: 0, y: 0, width: 100, height: 100) //the rect used to crop the image  width*cropRatio
    var successfulCrop = false //holds whether the event is sufficiently far enough from the edge that we can successfully crop the image
    let cropRatio : CGFloat = 1//0.3
    let circleRatio : CGFloat = 0.3
    var circleRect = CGRect(x: 0, y: 0, width: 50, height: 50)//(x: successfulCropRect.width*(1.0-circleRatio)*0.5, y: successfulCropRect.width*(1.0-circleRatio)*0.5, width: successfulCropRect.width*circleRatio, height: successfulCropRect.width*circleRatio)
    
    //image to display to the user  <==was in captureOutput but does not need to be done every time thats called
    static var lastImage = UIImage(named: "spongeBob")
    
    
    /*initializing the CIimage is very expensive so we will only make it one from the invalidState one,
     but the instance variable for the image is not available yet since self is not finished setting up yet so
     we have to make it static for use in the next line*/
    lazy var image = CIImage(cgImage: (ViewController.lastImage?.cgImage)!)
    lazy  var cgimage = ciContext.createCGImage(image, from: newFrame)
  //  var uiImage = UIImage()
    
    //obviously need a cameracapture session
    lazy var cameraSession: AVCaptureSession = {
        let session = AVCaptureSession()
        //testing difference between the two modes
        session.sessionPreset = AVCaptureSession.Preset.high
        //session.sessionPreset = AVCaptureSession.Preset.low
        return session
    }()
    
    
    //for checking all the ciFilters
    func logAllFilters() {
        let properties = CIFilter.filterNames(inCategory: kCICategoryBuiltIn)
        print("\(properties.debugDescription)")
        
        for filterName: Any in properties {
            let fltr = CIFilter(name:filterName as! String)
            print(fltr!.attributes)
        }
    }
    
    //MARK: viewController methods
    override func viewDidLoad() {
        super.viewDidLoad()
        motionManager.startAccelerometerUpdates()
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(ViewController.updateAcc), userInfo: nil, repeats: true)
        xPixelsToSkip = pixelsToSkip*4
        //  logAllFilters()
        setupCameraSession()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        cameraView.addSubview(glView)
        cameraSession.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        successfulCropRect = CGRect(x: successfulCropRect.width*(1.0-circleRatio)*0.5, y: successfulCropRect.width*(1.0-circleRatio)*0.5, width: successfulCropRect.width*circleRatio, height: successfulCropRect.width*circleRatio)

    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        //  imageQueue.  //<==not sure if/how I need to dismiss this
    }
    
    
    //MARK: Custom functions
    //use this method to see how many frames get dropped
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        droppedFrames = droppedFrames + 1
        //   print("Dropped frames : \(droppedFrames) out of \(numFrames) = \(droppedFrames/numFrames*100)")
    }
    
    func setupCameraSession(){
        
        //setup the cameraView a bit better
        cameraView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        cameraView.leftAnchor.constraint(equalTo: view.leftAnchor)
        
        // newFrame = CGRect(x: 0, y: 0, width: cameraView.frame.width, height: cameraView.frame.height)
        newFrame = CGRect(x: 0, y: 0, width: cameraView.frame.height*1.65*scale, height: cameraView.frame.width*2.08*scale)//<==prob a remainder of trying to get stuff to work
        //input handling
        //get the camera device, making sure its the rear facing; NOTe that the wideangle seems to be the general purpose
        let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back)
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice!)
            
         //  cameraSession.beginConfiguration()//is this harmful in that it will not be condusive to getting rays?
            
            //if we can, lets get that input from the camera
            if (cameraSession.canAddInput(deviceInput)){
                cameraSession.addInput(deviceInput)
            }
            
            //output handling
            
            let dataOutput = AVCaptureVideoDataOutput()
            //this next bit I have to admit if me flying by the seat of my pants...just swinging at getting a format
            // let mostValidPixelType = dataOutput.availableVideoPixelFormatTypes[0]//<==32 Bit BGRA 0,2
            var mostValidPixelType =  dataOutput.availableVideoPixelFormatTypes[0]
            //0 == YUV 420V
            //2 == BGRA
            
            switch detectionMode {
            case .BGRA:
                mostValidPixelType = dataOutput.availableVideoPixelFormatTypes[2]
                break
            case .YUV420v:
                mostValidPixelType = dataOutput.availableVideoPixelFormatTypes[0]
                break
            }
            
            //print("Pixel Type: \(mostValidPixelType)")
            dataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString):NSNumber(value: mostValidPixelType)] as [String : Any] //kCVPixelFormatType_32RGBA <== it really wants a string
            dataOutput.alwaysDiscardsLateVideoFrames = true //May have to relax this...
            
            if cameraSession.canAddOutput(dataOutput){
                cameraSession.addOutput(dataOutput)
            }
            
        //    cameraSession.commitConfiguration()//configuration was successful if we got here so commit it
            
            dataOutput.setSampleBufferDelegate(self,  queue: imageQueue)
            
        } catch let error as NSError{
            NSLog("\(error), \(error.localizedDescription)")
            
        }
    }
    
    //MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if (currentState == .CALIBRATION){
            
            
        }
        
        if !isFlat{
            //            if glContext != EAGLContext.current(){
            //                EAGLContext.setCurrent(glContext)
            //            }
            //
            //
            //            //
            //
            //            let invalidCIImage = CIImage(cgImage: (ViewController.invalidStateImage?.cgImage)!)
            
           // glView.bindDrawable()
            if (glContext != nil && image != nil){
                
               // ciContext.draw(image, in: newFrame, from: (image.extent))
                let invalidCIImage = CIImage(cgImage: (ViewController.lastImage?.cgImage)!)
                 ciContext.draw(invalidCIImage, in: newFrame, from: (invalidCIImage.extent))
                glView.display()
                print("Put Phone Flat")
            }
            return;
        }
        numFrames += 1
        //lets get those frame
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
        //lock that buffer down
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0)) //Important to lock down the memory because this might be moved while accessing it
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer!) //need to start at the beginning of the data
        
        let buffer = baseAddress!.assumingMemoryBound(to: UInt8.self)
        let buffermetadata = CMGetAttachment(sampleBuffer, kCGImagePropertyExifDictionary, nil)
        //let cosmicImage = CosmicImage(image: uiImage);
       // print(buffermetadata.debugDescription)
        
        var highestIntensity  = CGFloat.leastNormalMagnitude;
        var highestIntensityPoint = CGPoint(x: -1, y: -1);
        
        // Initialise an UIImage with our image data
        //   let capturedImage = UIImage.init(data: imageData , scale: 1.0)
        
        let width = CVPixelBufferGetWidth(pixelBuffer!)
        let w = CGFloat(width)
        let height = CVPixelBufferGetHeight(pixelBuffer!)
        let h = CGFloat(height)
        let pixelW = CGFloat(width) * cropRatio //CGFloat(width/200) //might have to play with this number; its the dimesionof the cropped image
    
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer!)
        
        var numActivePixels = 0
        let intensityThreshhold = detectionMode == DetectionModes.YUV420v ? intensityThreshholds[1].1 : intensityThreshholds[0].1
        var intensity: CGFloat = 0;//moved it out to shave operations
        //  let pixelsToSkip = 2;

     //IMPORTANT!  NOTE that once we trigger a threshold and want the picture, we will amplify the intensity of all pixels above the threshold AFTER we check them
        for x in stride(from: 0, to: width, by: xPixelsToSkip) {
            for y in stride(from: 0, to: height, by: pixelsToSkip) {
                
                let index = x +  y * bytesPerRow
            //    let isCosmicRay = false;
                
                switch detectionMode {
                case .BGRA:
                    let b = buffer[index]
                    let g = buffer[index+1]
                    let r = buffer[index+2]
                    
                    intensity =  (CGFloat(r) + CGFloat(b) + CGFloat(g))
                    
                    break;
                case .YUV420v:
                    //let y = changed to shave off operations of setting up y
                    intensity = (CGFloat(buffer[index]));
                    // print(intensity)
                    break
                }
                if (intensity > intensityThreshhold){//this reduces operations per frame slightly and will be important for calibration
                    numActivePixels = numActivePixels + 1
                    if(intensity > highestIntensity){
                        highestIntensity = intensity;
                        highestIntensityPoint = CGPoint(x: x, y: y);
                    }
                    //scale up the intensity
                  // let newI = CGFloat(buffer[index]) * intensityMagnifier//Magnifier the active pixels by 50%
                    //make the highest pixel stand out
                  // buffer[index] = UInt8.max//newI < 255 ? UInt8(newI) : UInt8.max //now thats a slick ternary conditional operator
                  // buffer[index+1] = UInt8.max
                  // buffer[index+2] = 0
                    
                    //for testing
                    for z in stride(from: Int(x - 100), to: Int(x ), by: 4) {
                        let tempIndex = z +  y * bytesPerRow
                        buffer[tempIndex] = UInt8.max//newI < 255 ? UInt8(newI) : UInt8.max //now thats a slick ternary conditional operator
                        buffer[index+1] = UInt8.max
                       // buffer[index+2] = UInt8.max

                    }
                            
                            
                    
                }
                
            }
            
            //print("Analyzing Row \(x) ______________________________")
        }
        

        if(highestIntensity >= intensityThreshhold){
            
            var pixelX = highestIntensityPoint.x
            var pixelY = highestIntensityPoint.y
            
            //COMMENTING OUT TO GET CIRCLE PLACEMTN CORRECT
            
            let halfW = pixelW*0.5
            var circleX = pixelX - halfW*circleRatio //If we were not cropping the circle
            var circleY = pixelY - halfW*circleRatio
            /*
            //need to adjust the cropping if the event was near the edge
            var nearSide = pixelX - halfW //1888 - 288 = 1600  //Supposed to be how much the cropped rect would be outside of the left side
            var farSide  = pixelX + halfW //1920-1888-288
            var x : CGFloat
            //shucks, I really wanted to use ternary conditional operators
            if (nearSide < 0){
                x = 0
                
            }
            else if (farSide > w){
                x = w - pixelW //1600+-256 = 1344
                pixelX = pixelX - x//used for positioning the event to put the circle around
            }
            else{
                x = nearSide
                pixelX = pixelX - x
            }
            //need to adjust the cropping if the event was near the edge
            nearSide = pixelY - halfW
            farSide  = pixelY + halfW
            var y : CGFloat

            if (nearSide < 0){
                y = 0
                            }
            else if (farSide > h){
                y = h - pixelW
                pixelY = pixelY - y
            }
            else{
                y = nearSide
                pixelY = pixelY - y
            }
        
            successfulCropRect = CGRect(x: x, y: y, width: pixelW, height: pixelW)
  */
            circleRect = CGRect(x:CGFloat(circleX),y: CGFloat(circleY),width: CGFloat(circleRatio*halfW), height: CGFloat(circleRatio*halfW))
            //let vec = CIVector(x: pixelX - pixelW/2, y: pixelY - pixelW/2, z: pixelX + pixelW/2, w: pixelY + pixelW/2)
 
            AudioServicesPlayAlertSound(SystemSoundID(1322))
            numEvents += 1
            timeElapsed = CFAbsoluteTimeGetCurrent() -  timeStarted
            flux = Double(numEvents)/timeElapsed
            
            print("Found me a cosmic ray! \(highestIntensity) at \(pixelX), \(pixelY) with \(numActivePixels).  \(numEvents) events in \(timeElapsed) ms " )
            print("The flux is  \(flux) " )
            
            //REPLACING LINES TO MOVE cropping to the filter as documentation implied it might be more efficient
           // image = CIImage(cvImageBuffer: pixelBuffer!).cropped(to: successfulCropRect)  /
            image  = CIImage(cvImageBuffer: pixelBuffer!)
            image = CIImage(bitmapData: buffer, bytesPerRow: bytesPerRow, size: CGSize(width: width, height: height), format: CMSampleBufferGetFormatDescription(CMSampleBuffer), colorSpace: )
            //let filter = CIFilter(name: "CICrop", withInputParameters: ["inputImage" : image, "inputRectangle" : vec])

            let filter = CIFilter(name : "CIExposureAdjust", withInputParameters: ["inputImage" : image, "inputEV" : 0.3])//this to reduce noise to find btrightest point
            image = filter!.outputImage!
            //image = image.cropped(to: successfulCropRect)
            cgimage = ciContext.createCGImage(image, from: image.extent)//from: successfulCropRect)
            
            
          //  print("outputimage is \(cgimage.debugDescription)")
            if (cgimage != nil){
                
               // ViewController.lastImage = UIImage(cgImage: cgimage!)
                ViewController.lastImage = UIImage(cgImage: cgimage!, scale: 1.0, orientation: .left)
                
                //ViewController.lastImage
                //uiContext?.
                UIGraphicsBeginImageContext(ViewController.lastImage!.size)
                ViewController.lastImage!.draw(at: CGPoint.zero)
                let uiContext = UIGraphicsGetCurrentContext()!
                uiContext.setStrokeColor(UIColor.init(red: 1.0, green: 1.0, blue: 0, alpha: 0.5).cgColor) //set the stroke color for the circle around the event
                uiContext.setAlpha(0.5)
                uiContext.setLineWidth(5.0)
                uiContext.addEllipse(in: circleRect)
                uiContext.drawPath(using: .stroke)
                ViewController.lastImage = UIGraphicsGetImageFromCurrentImageContext()
                glView.bindDrawable()
                // ciContext.draw(image, in: newFrame, from: image.extent)
                uiContext.draw((ViewController.lastImage?.cgImage!)!, in: newFrame)
                glView.display()
                UIGraphicsEndImageContext()
                UIImageWriteToSavedPhotosAlbum(ViewController.lastImage!, nil, nil, nil)
            }
            //   if glContext != EAGLContext.current(){
            //     EAGLContext.setCurrent(glContext)
            //  }
            

       //     ciContext.draw(ViewController.lastImage!.ciImage!,in: newFrame, from: image.extent)
            
        }
        
        //release the buffer
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
    }
    
    func pixelFrom(x: Int, y: Int, frame: CVPixelBuffer) -> (UInt8, UInt8, UInt8) {
        let baseAddress = CVPixelBufferGetBaseAddress(frame)
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
        let buffer = baseAddress!.assumingMemoryBound(to: UInt8.self)
        
        let index = x+y*bytesPerRow
        let b = buffer[index]
        let g = buffer[index+1]
        let r = buffer[index+2]
        
        return (r, g, b)
    }
    
    func convertCIImageToCGImage(inputImage: CIImage) -> CGImage! {
        //let context = CIContext(options: nil)<== instead recycle the one main one
        
        if ciContext != nil {
            return ciContext.createCGImage(inputImage, from: inputImage.extent)
        }
        
        return nil
    }
    
    @objc func updateAcc() {
        //        if let accelerometerData = motionManager.accelerometerData {
        //            print(accelerometerData)
        //        }
        if let ad = motionManager.accelerometerData {
            
            accData.x = ad.acceleration.x
            accData.y = ad.acceleration.y;
            accData.z = ad.acceleration.z;
            //  print("RAWWWW:  x: \(ad.rotationRate.x) y: \(ad.rotationRate.y) z: \(ad.rotationRate.z)")
            
        }
        isFlat = accData.z <= -0.95;
        //print("x: \(accData.x) y: \(accData.y) z: \(accData.z)")
        //print(isFlat)
        //        if let magnetometerData = motionManager.magnetometerData {
        //            print(magnetometerData)
        //        }
        //        if let deviceMotion = motionManager.deviceMotion {
        //            print(deviceMotion)
        //        }
    }
    
    func getIntensityThreshold(mode: DetectionModes) -> CGFloat{
        for data in intensityThreshholds{
            let tempDetectionMode = data.0;
            if(mode == tempDetectionMode){
                return data.1
            }
            
        }
        print("Unable to Get Threshold")
        return 0;
    }
    
}



extension UIColor {
    var red: CGFloat{ return self.cgColor.components![0] }
    var green: CGFloat{ return self.cgColor.components![1] }
    var blue: CGFloat{ return self.cgColor.components![2] }
}
extension UIImage {
    
    func crop(cropRect:CGRect) -> UIImage
    {
        UIGraphicsBeginImageContextWithOptions(cropRect.size, false, 0);
        let context = UIGraphicsGetCurrentContext();
        
        context?.translateBy(x: 0.0, y: self.size.height);
        context?.scaleBy(x: 1.0, y: -1.0);
        context?.draw(self.cgImage!, in: CGRect(x:0, y:0, width:self.size.width, height:self.size.height), byTiling: false);
        context?.clip(to: [cropRect]);
        
        let croppedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return croppedImage!;
    }
    
}
