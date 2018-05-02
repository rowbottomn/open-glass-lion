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


class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    
    //MARK: outlets
    @IBOutlet weak var cameraView: UIView!
    
    let motionManager = CMMotionManager()
    var timer:Timer!;
    
    var accData = (x: 0.0, y: 0.0, z:0.0)
    var isFlat: Bool = false;

    
    

    
    //MARK: Variables
    var droppedFrames = 0
    //move this to the outside
    var scale = UIScreen.main.scale
    var newFrame = CGRect(x: 0, y: 0, width: 0, height:0 )
    
    //make the queue for the frames
    let imageQueue = DispatchQueue(label:"ca.hdsb.solta.queue")
    //multiple attempts of going from objective C methods
    // let imageQueue = DispatchQueue.//dispatch_queue_create("ca.hdsb.solta.queue", DISPATCH_QUEUE_SERIAL)
    
    //MARK: object construction
    var glContext: EAGLContext = {
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
    
    
    //obviously need a cameracapture session
    lazy var cameraSession: AVCaptureSession = {
       let session = AVCaptureSession()
       //testing difference between the two modes
        //session.sessionPreset = AVCaptureSession.Preset.high
        session.sessionPreset = AVCaptureSession.Preset.low
        return session
    }()
    
    
    //MARK: viewController methods
    override func viewDidLoad() {
        super.viewDidLoad()
        motionManager.startAccelerometerUpdates()
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(ViewController.updateAcc), userInfo: nil, repeats: true)


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
        print("Dropped frames : \(droppedFrames)")
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
            let mostValidPixelType = dataOutput.availableVideoPixelFormatTypes[2]//<==32 Bit BGRA
            print("Pixel Type: \(mostValidPixelType)")
            dataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString):NSNumber(value: mostValidPixelType)] as [String : Any] //kCVPixelFormatType_32RGBA <== it really wants a string
            dataOutput.alwaysDiscardsLateVideoFrames = true //May have to relax this...I can't believe it will drop frames processing black
            
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
            if glContext != EAGLContext.current(){
                EAGLContext.setCurrent(glContext)
            }
            
            
            let invalidStateImage = UIImage(named: "spongeBob")
            let invalidCIImage = CIImage(cgImage: (invalidStateImage?.cgImage)!)
                glView.bindDrawable()
            ciContext.draw((invalidCIImage), in: newFrame, from: (invalidCIImage.extent))
                glView.display()
                //print("Put Phone Flat")
            
            return;
        }
        
        //lets get those frames
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer!)
    
        let uiImage = UIImage(cgImage: convertCIImageToCGImage(inputImage: image))
        let cosmicImage = CosmicImage(image: uiImage);
        

        
        var highestIntensity = CGFloat.leastNormalMagnitude;
        var highestIntensityPoint = CGPoint(x: -1, y: -1);
        
        // Initialise an UIImage with our image data
        //let capturedImage = UIImage.init(data: imageData , scale: 1.0)
      
        let width = CVPixelBufferGetWidth(pixelBuffer!)
        let height = CVPixelBufferGetHeight(pixelBuffer!)

        let pixelW : Int = 100
        
        
        let pixelsToSkip = 10;
        
        for i in stride(from: 0, to: width, by: pixelsToSkip) {
            for j in stride(from: 0, to: height, by: pixelsToSkip) {
                let c = (cosmicImage.getColor(x: i, y: j))
                
                let intensity = c.red + c.blue + c.green
                
                if(intensity > highestIntensity){
                    highestIntensity = intensity;
                    highestIntensityPoint = CGPoint(x: i, y: j);
                }
                
            }
            
            //print("Analyzing Row \(i)")
        }
        
        

        if(highestIntensity >= 300){
            let pixelX = Int(highestIntensityPoint.x);
            let pixelY = Int(highestIntensityPoint.y);
            AudioServicesPlayAlertSound(SystemSoundID(1322))
            //print("Found me a cosmic  ray")
            UIImageWriteToSavedPhotosAlbum(uiImage.crop(cropRect: CGRect(x: pixelX - pixelW/2, y: pixelX - pixelW/2, width: pixelX + pixelW/2, height: pixelX + pixelW/2)), nil, nil, nil)
        }
        
    
        
    

        
        
        if glContext != EAGLContext.current(){
            EAGLContext.setCurrent(glContext)
        }
        
        glView.bindDrawable()
        ciContext.draw(image, in: newFrame, from: image.extent)
        glView.display()
        
        
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
        let context = CIContext(options: nil)
        if context != nil {
            return context.createCGImage(inputImage, from: inputImage.extent)
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
