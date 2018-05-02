//
//  CosmicImage.swift
//  Camera
//
//  Created by Ansar Khan on 2018-03-23.
//

import Foundation
import UIKit
import AVFoundation


class CosmicImage {
    private enum MyColor {
        case red, blue, green
    }
    
    var image:UIImage;
    
    //    var data: UnsafePointer<UInt8>?;
    var dataArr: [UInt8]?;
    
    let numberOfComponents = 4//Number of Params in color, 4 b/c R,G,B,A
    
    
    
    init(image: UIImage){
        self.image = image;
        initRGB {[weak self] length, data in
            guard let sself = self, let notNilData = data else { return }
            //            sself.data = notNilData
            sself.dataArr = convert(length: length, data: notNilData);
        }
    }
    
    private func convert(length: Int, data: UnsafePointer<UInt8>) -> [UInt8] {
        let buffer = UnsafeBufferPointer(start: data, count: length);
        return Array(buffer)
    }
    
    private func initRGB(completion: (CFIndex, UnsafePointer<UInt8>?) -> Void){
        let provider =  self.image.cgImage?.dataProvider;
        let providerData = provider?.data
        let length = CFDataGetLength(providerData)
        guard length != 0 else {
            completion(0, nil)
            return
        }
        completion(length, (CFDataGetBytePtr(providerData)))
    }
    
    func getColor(x: Int, y:Int) -> UIColor{
        let r = getColour(x: x, y:y, colour: .red)
        let g = getColour(x: x, y:y, colour: .green)
        let b = getColour(x: x, y:y, colour: .blue)
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    private func getColour(x: Int, y: Int, colour: MyColor) -> CGFloat
    {
        let size = image.size;
        let index: Int
        
        switch colour {
        case .red:
            index = ((Int(size.width) * y) + x) * numberOfComponents
        case .blue:
            index = ((Int(size.width) * y) + x) * numberOfComponents + 1
        case .green:
            index = ((Int(size.width) * y) + x) * numberOfComponents + 2
        }
        
        if let data = self.dataArr, data.indices.contains(index) {
            return CGFloat(data[index])
        }
        return CGFloat(-1)
    }
}
