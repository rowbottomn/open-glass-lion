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
    
    let motionManager = CMMotionManager()
    
    var timer:Timer!;

     enum DetectionModes {
        case YUV420v
        case BGRA
    }
    enum OperationState{
        case CALIBRATION
        case RUNNING
        case DORMANT
    }

    
    //MARK: Variables
    var droppedFrames = 0
    var numFrames = 0
    var numEvents = 0
    var accData = (x: 0.0, y: 0.0, z:-1.0)
    var isFlat: Bool = false
    var timeStarted = CFAbsoluteTimeGetCurrent()
    var timeElapsed = CFAbsoluteTimeGetCurrent()
    var flux : Double = 0
    let targetFlux = 1.0/10.0;
     let detectionMode = DetectionModes.YUV420v
    var pixelsToSkip : Int = 4
    //moved this to the outside
    var scale = UIScreen.main.scale
    var newFrame = CGRect(x: 0, y: 0, width: 100, height:100 )
    var intensityThreshholds = [
        (DetectionModes.BGRA, CGFloat(450.0)),//350 high 2 frameskip
        (DetectionModes.YUV420v, CGFloat(160))
    ]
    var minRaySize = 4;//numberof pixels that represents how many pizels should be in an image
    var currentState: OperationState = OperationState.RUNNING;
    
    
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
    
    //image to display to the user  <==was in captureOutput but does not need to be done every time thats called
    static let invalidStateImage = UIImage(named: "spongeBob")
    /*initializing the CIimage is very expensive so we will only make it one from the invalidState one,
     but the instance variable for the image is not available yet since self is not finished setting up yet so
     we have to make it static for use in the next line*/
    lazy var image = CIImage(cgImage: (ViewController.invalidStateImage?.cgImage)!)
    lazy  var cgimage = ciContext.createCGImage(image, from: image.extent)
    var uiImage = UIImage()
    
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
        timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(ViewController.updateThreshold), userInfo: nil, repeats: true)


      //  logAllFilters()
        setupCameraSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        cameraView.addSubview(glView)
        cameraSession.startRunning()
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
            scale = UIScreen.main.scale

         //   newFrame = CGRect(x: 0, y: 0, width: cameraView.frame.width*scale, height: cameraView.frame.height*scale)
       // newFrame = CGRect(x: 0, y: 0, width: cameraView.frame.width, height: cameraView.frame.height)
        newFrame = CGRect(x: 0, y: 0, width: cameraView.frame.height*1.65*scale, height: cameraView.frame.width*2.08*scale)
        //input handling
        //get the camera device, making sure its the rear facing; NOTe that the wideangle seems to be the general purpose
        let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back)
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice!)
            
            cameraSession.beginConfiguration()//is this harmful in that it will not be condusive to getting rays?
            
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
            
            cameraSession.commitConfiguration()//configuration was successful if we got here so commit it
            
            dataOutput.setSampleBufferDelegate(self,  queue: imageQueue)
            
        } catch let error as NSError{
            NSLog("\(error), \(error.localizedDescription)")
            
        }
    }
    
    //MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      
        if !isFlat{
            currentState = .DORMANT
        }
        else{
            currentState = .RUNNING
        }
        
        numFrames += 1
        
        switch (currentState){

        
        case .RUNNING, .CALIBRATION:
            //lets get those frame
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            
            //lock that buffer down
            CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer!)
            
            let buffer = baseAddress!.assumingMemoryBound(to: UInt8.self)
            
            //let cosmicImage = CosmicImage(image: uiImage);
            
            
            var highestIntensity  = CGFloat.leastNormalMagnitude;
            var highestIntensityPoint = CGPoint(x: -1, y: -1);
            
            // Initialise an UIImage with our image data
            //   let capturedImage = UIImage.init(data: imageData , scale: 1.0)
            
            let width = CVPixelBufferGetWidth(pixelBuffer!)
            let height = CVPixelBufferGetHeight(pixelBuffer!)
            
            //let pixelW : Int = 100
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer!)
            
            //  let pixelsToSkip = 2;
            
            var numBrightPixels = 0;
            

            
            for x in stride(from: 0, to: width, by: pixelsToSkip) {
                for y in stride(from: 0, to: height, by: pixelsToSkip) {
                    
                    let index = x +  y * bytesPerRow
                    let isCosmicRay = false;
                    let intensity: CGFloat;
                    
                    switch detectionMode {
                    case .BGRA:
                        let b = buffer[index]
                        let g = buffer[index+1]
                        let r = buffer[index+2]
                        
                        intensity =  (CGFloat(r) + CGFloat(b) + CGFloat(g))
                        
                        break;
                    case .YUV420v:
                        let y = buffer[index]
                        intensity = (CGFloat(y));
                        // print(intensity)
                        break
                    }
                    
                    if (intensity > getIntensityThreshold(mode: detectionMode)*0.75){
                        numBrightPixels += 1;
                    }
                    if(intensity > highestIntensity){
                        highestIntensity = intensity;
                        highestIntensityPoint = CGPoint(x: x, y: y);
                    }
                    
                    
                    
                    
                }
                
                //print("Analyzing Row \(x) ______________________________")
            }
            let intensityThreshhold = getIntensityThreshold(mode: detectionMode)
            if(highestIntensity >= intensityThreshhold
                && numBrightPixels >= minRaySize
                && numBrightPixels <= Int(Double(width*height)*0.25)){
                
                let pixelX = highestIntensityPoint.x
                let pixelY = highestIntensityPoint.y
                let pixelW  : CGFloat = 100//CGFloat(width/200) //might have to play with this number; its the dimesionof the cropped image
                let rect = CGRect(x: pixelX - pixelW/2, y: pixelY - pixelW/2, width: pixelX + pixelW/2, height: pixelY + pixelW/2)
                let vec = CIVector(x: pixelX - pixelW/2, y: pixelY - pixelW/2, z: pixelX + pixelW/2, w: pixelY + pixelW/2)
                
               
                numEvents += 1
                timeElapsed = CFAbsoluteTimeGetCurrent() -  timeStarted
                flux = Double(numEvents)/timeElapsed
                
                if (flux > targetFlux*1.5){
                    return;
                }
                print("Found me a cosmic ray! \(highestIntensity) at \(pixelX), \(pixelY).  \(numEvents) events in \(timeElapsed) ms " )
                print("The flux is  \(flux) " )
                let percent = Double (numBrightPixels) / Double(width * height)
                print("Percentage of Bright Pixels: \(percent * 100.0 )")
                print("Threshold is \(getIntensityThreshold(mode: detectionMode))")
                image = CIImage(cvImageBuffer: pixelBuffer!)
                
                //maybe abstract this into a function later
                let filter = CIFilter(name: "CICrop", withInputParameters: ["inputImage" : image, "inputRectangle" : vec])
               // print("filter is \(filter.debugDescription)")
                
                image = filter!.outputImage!
                cgimage = ciContext.createCGImage(image, from: image.extent)
               // print("outputimage is \(cgimage.debugDescription)")
                if (cgimage != nil){
                    uiImage = UIImage(cgImage: cgimage!)
                    UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                }
                 AudioServicesPlayAlertSound(SystemSoundID(1322))
                //   if glContext != EAGLContext.current(){
                //     EAGLContext.setCurrent(glContext)
                //  }
                
                glView.bindDrawable()
                ciContext.draw(image, in: newFrame, from: image.extent)
                glView.display()
                
            }
            
            //release the buffer
            CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
            break;
            
        case .DORMANT:
            glView.bindDrawable()
            if (glContext != nil && image != nil){
                ciContext.draw(image, in: newFrame, from: (image.extent))
                glView.display()
                print("Put Phone Flat")
            }
            return;
        }
        
        
       

        
    }
    
    
    func pixelFrom(x: Int, y: Int, frame: CVPixelBuffer) -> (UInt8, UInt8, UInt8) {
        let baseAddress = CVPixelBufferGetBaseAddress(frame)
        
        //let width = CVPixelBufferGetWidth(frame)
        //let height = CVPixelBufferGetHeight(frame)
        
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
    
    @objc func updateThreshold(){
        timeElapsed = CFAbsoluteTimeGetCurrent() -  timeStarted
        flux = Double(numEvents)/timeElapsed
        if (flux > targetFlux){
            incrementIntensityThreshold(mode: detectionMode, value: 5)
            
        }
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
    func setIntensityThreshold(mode: DetectionModes, value: Double) -> Void{
        switch(mode){
        case .BGRA:
            intensityThreshholds[0].1 = CGFloat(value)
        
        case .YUV420v:
            intensityThreshholds[1].1 = CGFloat(value)
        }
        print("Changed intensity to \(getIntensityThreshold(mode: mode))")
        
    }
    func incrementIntensityThreshold(mode: DetectionModes, value: Double){
        setIntensityThreshold(mode: mode, value: Double(getIntensityThreshold(mode: mode))+(value))
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
