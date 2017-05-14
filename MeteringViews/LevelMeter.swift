//
//  LevelMeter.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/3.
//
//
/*
 </samplecode>
*/

import UIKit

func LEVELMETER_CLAMP(_ min: CGFloat, _ x: CGFloat, _ max: CGFloat) -> CGFloat {
    return x < min ? min : (x > max ? max : x)
}

// The LevelMeterColorThreshold struct is used to define the colors for the LevelMeter,
// and at what values each of those colors begins.
struct LevelMeterColorThreshold {
    var maxValue: CGFloat // A value from 0 - 1. The maximum value shown in this color
    var color: UIColor // A UIColor to be used for this value range
}

@objc(LevelMeter)
class LevelMeter: UIView {
    var _colorThresholds: [LevelMeterColorThreshold] = [
        LevelMeterColorThreshold(maxValue: 0.25, color: UIColor(red: 0, green: 1, blue: 0, alpha: 1)),
        LevelMeterColorThreshold(maxValue: 0.8, color: UIColor(red: 1, green: 1, blue: 0, alpha: 1)),
        LevelMeterColorThreshold(maxValue: 1.0, color: UIColor(red: 1, green: 0, blue: 0, alpha: 1)),
        ]
    var _scaleFactor: CGFloat = 0.0
    
    // The current level, from 0 - 1
    var level: CGFloat = 0.0
    
    // Optional peak level, will be drawn if > 0
    var peakLevel: CGFloat = 0.0
    
    // The number of lights to show, or 0 to show a continuous bar
    var numLights: Int = 0
    
    // Whether the view is oriented V or H. This is initially automatically set based on the
    // aspect ratio of the view.
    var isVertical: Bool = false
    
    // Whether to use variable intensity lights. Has no effect if numLights == 0.
    var variableLightIntensity: Bool = true
    
    // The background color of the lights
    var bgColor: UIColor? = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6)
    
    // The border color of the lights
    var borderColor: UIColor? = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    
    func _performInit() {
        isVertical = self.frame.width < self.frame.height
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self._performInit()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self._performInit()
    }
    
    override func draw(_ rect: CGRect) {
        let bds: CGRect
        
        guard let cxt = UIGraphicsGetCurrentContext() else {
            fatalError("cannot get CurrentContext")
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        
        if isVertical {
            cxt.translateBy(x: 0.0, y: self.bounds.height)
            cxt.scaleBy(x: 1.0, y: -1.0)
            bds = self.bounds
        } else {
            cxt.translateBy(x: 0.0, y: self.bounds.height)
            cxt.rotate(by: -.pi/2)
            bds = CGRect(x: 0.0, y: 0.0, width: self.bounds.height, height: self.bounds.width)
        }
        
        cxt.setFillColorSpace(cs)
        cxt.setStrokeColorSpace(cs)
        
        if numLights == 0 {
            var currentTop: CGFloat = 0.0
            
            if let bgColor = bgColor {
                bgColor.set()
                cxt.fill(bds)
            }
            
            for thisThresh in _colorThresholds {
                let val = min(thisThresh.maxValue, level)
                
                let rect = CGRect(
                    x: 0,
                    y: (bds.size.height) * currentTop,
                    width: bds.size.width,
                    height: (bds.size.height) * (val - currentTop)
                )
                
                thisThresh.color.set()
                cxt.fill(rect)
                
                if level < thisThresh.maxValue {break}
                
                currentTop = val
            }
            
            if let borderColor = borderColor {
                borderColor.set()
                cxt.stroke(bds.insetBy(dx: 0.5, dy: 0.5))
            }
            
        } else {
            var lightMinVal: CGFloat = 0.0
            let insetAmount: CGFloat
            let lightVSpace = bds.size.height / CGFloat(numLights)
            if lightVSpace < 4.0 {insetAmount = 0.0}
            else if lightVSpace < 8.0 {insetAmount = 0.5}
            else {insetAmount = 1.0}
            
            var peakLight = -1
            if peakLevel > 0.0 {
                peakLight = Int(peakLevel * CGFloat(numLights))
                if peakLight >= numLights {peakLight = numLights - 1}
            }
            
            for light_i in 0..<numLights {
                let lightMaxVal = CGFloat(light_i + 1) / CGFloat(numLights)
                var lightIntensity: CGFloat
                
                if light_i == peakLight {
                    lightIntensity = 1.0
                } else {
                    lightIntensity = (level - lightMinVal) / (lightMaxVal - lightMinVal)
                    lightIntensity = LEVELMETER_CLAMP(0.0, lightIntensity, 1.0)
                    if !variableLightIntensity && lightIntensity > 0.0 {lightIntensity = 1.0}
                }
                
                var lightColor = _colorThresholds[0].color
                for color_i in 0..<_colorThresholds.count-1 {
                    let thisThresh = _colorThresholds[color_i]
                    let nextThresh = _colorThresholds[color_i + 1]
                    if thisThresh.maxValue <= lightMaxVal {lightColor = nextThresh.color}
                }
                
                var lightRect = CGRect(
                    x: 0.0,
                    y: bds.size.height * (CGFloat(light_i) / CGFloat(numLights)),
                    width: bds.size.width,
                    height: bds.size.height * (1.0 / CGFloat(numLights))
                )
                lightRect = lightRect.insetBy(dx: insetAmount, dy: insetAmount)
                
                if let bgColor = bgColor {
                    bgColor.set()
                    cxt.fill(lightRect)
                }
                
                if lightIntensity == 1.0 {
                    lightColor.set()
                    cxt.fill(lightRect)
                } else if lightIntensity > 0.0 {
                    let clr = lightColor.cgColor.copy(alpha: lightIntensity)
                    cxt.setFillColor(clr!)
                    cxt.fill(lightRect)
                }
                
                if let borderColor = borderColor {
                    borderColor.set()
                    cxt.stroke(lightRect.insetBy(dx: 0.5, dy: 0.5))
                }
                
                lightMinVal = lightMaxVal
            }
            
        }
        
    }
    
    
    var colorThresholds: [LevelMeterColorThreshold] {
        // Returns a pointer to the first LevelMeterColorThreshold struct. The number of color
        // thresholds is returned in count
        get {
            return _colorThresholds
        }
        
        // Load <count> elements from <thresholds> and use these as our color threshold values.
        set {
            _colorThresholds = newValue.sorted{$0.maxValue < $1.maxValue}
            
        }
    }
    
}
