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

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    
    //MARK: outlets
    @IBOutlet weak var cameraView: UIView!
    
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
        session.sessionPreset = AVCaptureSession.Preset.photo
        return session
    }()
    
    
    //MARK: viewController methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
            dataOutput.alwaysDiscardsLateVideoFrames = false //May have to relax this...I can't believe it will drop frames processing black
            
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
        

        
        //lets get those frames
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer!)
      
        let bufferW = CVPixelBufferGetWidth(pixelBuffer!)
        let bufferH = CVPixelBufferGetHeight(pixelBuffer!)
        let numPlanes = CVPixelBufferGetPlaneCount(pixelBuffer!)

        
        var pixelX : Int = 0//use for location of event
        var pixelY : Int = 0
        let pixelW : Int = 100
        
        //lets look thru
        /*
         for (i , p) in pixelBuffer.enumerated(){
         print("+++++++++++++++++++++++++++++++++++++++++++++++++++++")
         print("Pixel Info : \(i) ,  \(p.description)")
         print("+++++++++++++++++++++++++++++++++++++++++++++++++++++")
         }
         */

        
     // image.cropped(to:  CGRect(x: pixelX - pixelW/2, y: pixelX - pixelW/2, width: pixelX + pixelW/2, height: pixelX + pixelW/2))
        
     /*   print("+++++++++++++++++++++++++++++++++++++++++++++++++++++")
        print("PixelInfo -")
        print("\t  width: \(bufferW)")
        print("\t  height: \(bufferH)")
        print("\t  planes: \(numPlanes)")
        print("+++++++++++++++++++++++++++++++++++++++++++++++++++++")
       */

        
        if glContext != EAGLContext.current(){
            EAGLContext.setCurrent(glContext)
        }
        
        glView.bindDrawable()
        ciContext.draw(image, in: newFrame, from: image.extent)
        glView.display()
        
    }
    
    
}

