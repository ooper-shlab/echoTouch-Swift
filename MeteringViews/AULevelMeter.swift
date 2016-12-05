//
//  AULevelMeter.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/3.
//
//
/*
 </samplecode>
*/

import UIKit

private let kPeakFalloffPerSec = 0.7
private let kLevelFalloffPerSec = 0.8
private let kMinDBvalue = -80.0
private let kRefreshRate = 60.0
private let kDefaultSampleRate = 44100.0

// A LevelMeter subclass which is used specifically for AVAudioPlayer objects
//### We are not sure if above comment is appropriate...
@objc(AULevelMeter)
class AULevelMeter: UIView {
    
    private var _channelNumbers: [Int]
    private var _subLevelMeters: [LevelMeter] = []
    private var _meterTable: MeterTable
    private var _updateTimer: Timer?
    private var _refreshHz: TimeInterval
    private var _sampleRate: Double
    private var _useGL: Bool
    private var _running: Bool = false
    private var _peakFalloffLastFire: CFAbsoluteTime = 0
    private var _color: UIColor?
    
    var showsPeaks: Bool		// Whether or not we show peak levels
    var vertical: Bool		// Whether the view is oriented V or H
    var powerMeters: [PowerMeter]
    
    override init(frame: CGRect) {
        _refreshHz = 1.0 / kRefreshRate
        showsPeaks = true
        _channelNumbers = [0]
        vertical = false
        _useGL = true
        _sampleRate = kDefaultSampleRate
        _meterTable = MeterTable(Float(kMinDBvalue))!
        powerMeters = [PowerMeter()]
        _color = nil
        
        super.init(frame: frame)
        
        self.layoutSubLevelMeters()
        self.registerForBackgroundNotifications()
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        _refreshHz = 1.0 / kRefreshRate
        showsPeaks = true
        _channelNumbers = [0]
        vertical = false
        _useGL = true
        _sampleRate = kDefaultSampleRate
        _meterTable = MeterTable(Float(kMinDBvalue))!
        powerMeters = [PowerMeter()]
        _color = nil
        
        super.init(coder: aDecoder)
        
        self.layoutSubLevelMeters()
        self.registerForBackgroundNotifications()
    }
    
    private func registerForBackgroundNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(pauseTimer),
                                               name: .UIApplicationWillResignActive,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(resumeTimer),
                                               name: .UIApplicationWillEnterForeground,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(resumeTimer),
                                               name: .UIApplicationDidBecomeActive,
                                               object: nil)
    }
    
    private func layoutSubLevelMeters() {
        for thisMeter in _subLevelMeters {
            thisMeter.removeFromSuperview()
        }
        _subLevelMeters = []
        
        var meters_build: [LevelMeter] = []
        meters_build.reserveCapacity(_channelNumbers.count)
        
        powerMeters = Array(repeating: PowerMeter(), count: _channelNumbers.count)
        
        for i in _channelNumbers.indices {
            powerMeters[i].setSampleRate(_sampleRate)
        }
        
        let totalRect: CGRect
        
        if vertical {totalRect = CGRect(x: 0.0, y: 0.0, width: self.frame.width + 2.0, height: self.frame.height)}
        else {totalRect = CGRect(x: 0.0, y: 0.0, width: self.frame.width, height: self.frame.height + 2.0)}
        
        for i in _channelNumbers.indices {
            let fr: CGRect
            
            if vertical {
                fr = CGRect(
                    x: totalRect.origin.x + ((CGFloat(i) / CGFloat(_channelNumbers.count)) * totalRect.size.width),
                    y: totalRect.origin.y,
                    width: (1.0 / CGFloat(_channelNumbers.count)) * totalRect.size.width - 2.0,
                    height: totalRect.size.height)
            } else {
                fr = CGRect(
                    x: totalRect.origin.x,
                    y: totalRect.origin.y + ((CGFloat(i) / CGFloat(_channelNumbers.count)) * totalRect.size.height),
                    width: totalRect.size.width,
                    height: (1.0 / CGFloat(_channelNumbers.count)) * totalRect.size.height - 2.0)
            }
            
            let newMeter: LevelMeter
            
            if _useGL {newMeter = GLLevelMeter(frame: fr)}
            else {newMeter = LevelMeter(frame: fr)}
            
            newMeter.numLights = 30
            newMeter.isVertical = self.vertical
            
            if let color = color {
                let tmpThreshold = LevelMeterColorThreshold(maxValue: 0.0, color: color)
                newMeter.colorThresholds = [tmpThreshold]
            }
            
            meters_build.append(newMeter)
            self.addSubview(newMeter)
        }
        
        _subLevelMeters = meters_build
        
    }
    
    @objc private func _refresh() {
        enum RefreshError: Error {
            case bail
        }
        
        // if we have no queue, but still have levels, gradually bring them down
        do {
            if !_running {
                var maxLvl: CGFloat = -1.0
                let thisFire = CFAbsoluteTimeGetCurrent()
                // calculate how much time passed since the last draw
                let timePassed = thisFire - _peakFalloffLastFire
                for thisMeter in _subLevelMeters {
                    var newLevel: CGFloat = thisMeter.level - CGFloat(timePassed * kLevelFalloffPerSec)
                    if newLevel < 0.0 {newLevel = 0.0}
                    thisMeter.level = newLevel
                    if showsPeaks {
                        var newPeak: CGFloat = thisMeter.peakLevel - CGFloat(timePassed * kPeakFalloffPerSec)
                        if newPeak < 0.0 {newPeak = 0.0}
                        thisMeter.peakLevel = newPeak
                        if newPeak > maxLvl {maxLvl = newPeak}
                    } else if newLevel > maxLvl {maxLvl = newLevel}
                    
                    thisMeter.setNeedsDisplay()
                }
                // stop the timer when the last level has hit 0
                if maxLvl <= 0.0 {
                    _updateTimer?.invalidate()
                    _updateTimer = nil
                }
                
                _peakFalloffLastFire = thisFire
            } else {
                for i in _channelNumbers.indices {
                    let channelIdx = _channelNumbers[i]
                    
                    if channelIdx >= _channelNumbers.count {throw RefreshError.bail}
                    if channelIdx > 127 {throw RefreshError.bail}
                    
                    let channelView = _subLevelMeters[channelIdx]
                    
                    channelView.level = CGFloat(_meterTable.valueAt(Float(self.powerMeters[i].averagePowerDB)))
                    if showsPeaks {channelView.peakLevel = CGFloat(_meterTable.valueAt(Float(self.powerMeters[i].peakPowerDB)))
                    } else {
                        channelView.peakLevel = 0.0
                    }
                    
                    channelView.setNeedsDisplay()
                }
            }
            
        } catch {
            
            for thisMeter in _subLevelMeters {thisMeter.level = 0.0; thisMeter.setNeedsDisplay()}
            print("ERROR: metering failed")
        }
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.removeObserver(self, name: .UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.removeObserver(self, name: .UIApplicationDidBecomeActive, object: nil)
        
        _updateTimer?.invalidate()
        
    }
    
    // Whether the unit is currently running
    var running: Bool {
        get {return _running}
        
        set(v) {
            if !_running && v {
                _updateTimer?.invalidate()
                
                _updateTimer = Timer.scheduledTimer(
                    timeInterval: _refreshHz,
                    target: self,
                    selector: #selector(_refresh),
                    userInfo: nil, repeats: true)
            } else if !_running && !v {
                _peakFalloffLastFire = CFAbsoluteTimeGetCurrent()
            }
            
            _running = v
            
            for thisMeter in _subLevelMeters {
                thisMeter.setNeedsDisplay()
            }
        }
    }
    
    // Sample rate of the audio unit
    var sampleRate: Double {
        get {return _sampleRate}
        
        set(v) {
            _sampleRate = v
            layoutSubLevelMeters()
        }
    }
    
    // How many times per second to redraw
    var refreshHz: TimeInterval {
        get {return _refreshHz}
        
        set(v) {
            _refreshHz = v
            if _updateTimer != nil {
                _updateTimer!.invalidate()
                _updateTimer = Timer.scheduledTimer(timeInterval: _refreshHz,
                                                    target: self,
                                                    selector: #selector(_refresh),
                                                    userInfo: nil,
                                                    repeats: true)
            }
        }
    }
    
    
    // Array of NSNumber objects: The indices of the channels to display in this meter
    var channelNumbers: [Int] {
        get {return _channelNumbers}
        
        set(v) {
            _channelNumbers = v
            
            layoutSubLevelMeters()
        }
    }
    
    // Whether or not to use OpenGL for drawing
    var useGL: Bool {
        get {return _useGL}
        
        set(v) {
            _useGL = v
            layoutSubLevelMeters()
        }
    }
    
    var color: UIColor? {
        get {return _color}
        
        set(c) {
            _color = c
            
            layoutSubLevelMeters()
        }
    }
    
    @objc private func pauseTimer() {
        self.running = false
    }
    
    @objc private func resumeTimer() {
        self.running = true
    }
    
}
