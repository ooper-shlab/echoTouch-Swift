//
//  AVLevelMeter.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/3.
//
//
/*
 </samplecode>
*/

import UIKit
import AudioToolbox.AudioQueue
import AVFoundation

private let kPeakFalloffPerSec	= 0.7
private let kLevelFalloffPerSec = 0.8
private let kMinDBvalue = -80.0

// A LevelMeter subclass which is used specifically for AVAudioPlayer objects
@objc(AVLevelMeter)
class AVLevelMeter: UIView {
    private var _player: AVAudioPlayer?
    private var _channelNumbers: [Int]
    private var _subLevelMeters: [LevelMeter] = []
    private var _meterTable: MeterTable
    private var _updateTimer: Timer?
    private var _refreshHz: TimeInterval
    private var _useGL: Bool
    
    private var _peakFalloffLastFire: CFAbsoluteTime = 0
    private var _color: UIColor?
    
    var showsPeaks: Bool // Whether or not we show peak levels
    var vertical: Bool // Whether the view is oriented V or H
    
    override init(frame: CGRect) {
        _refreshHz = 1.0 / 60.0
        showsPeaks = true
        _channelNumbers = [0]
        vertical = false
        _useGL = true
        _meterTable = MeterTable(Float(kMinDBvalue))!
        
        super.init(frame: frame)
        
        self.layoutSubLevelMeters()
        self.registerForBackgroundNotifications()
    }
    
    required init?(coder aDecoder: NSCoder) {
        _refreshHz = 1.0 / 60.0
        showsPeaks = true
        _channelNumbers = [0]
        vertical = false
        _useGL = true
        _meterTable = MeterTable(Float(kMinDBvalue))!
        
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
    }
    
    private func layoutSubLevelMeters() {
        for thisMeter in _subLevelMeters {
            thisMeter.removeFromSuperview()
        }
        _subLevelMeters = []
        
        var meters_build: [LevelMeter] = []
        meters_build.reserveCapacity(_channelNumbers.count)
        
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
                    height: totalRect.size.height
                )
            } else {
                fr = CGRect(
                    x: totalRect.origin.x,
                    y: totalRect.origin.y + ((CGFloat(i) / CGFloat(_channelNumbers.count)) * totalRect.size.height),
                    width: totalRect.size.width,
                    height: (1.0 / CGFloat(_channelNumbers.count)) * totalRect.size.height - 2.0
                )
            }
            
            let newMeter: LevelMeter
            
            if _useGL {newMeter = GLLevelMeter(frame: fr)}
            else {newMeter = LevelMeter(frame: fr)}
            
            if let color = _color {
                let tmpThreshold = LevelMeterColorThreshold(maxValue: 0.0, color: color)
                newMeter.colorThresholds = [tmpThreshold]
            }
            
            newMeter.numLights = 30
            newMeter.isVertical = self.vertical
            meters_build.append(newMeter)
            self.addSubview(newMeter)
        }
        
        _subLevelMeters = meters_build
        
    }
    
    @objc private func _refresh() {
        enum RefreshError: Error {
            case bail
        }
        
        do {
            // if we have no queue, but still have levels, gradually bring them down
            if _player == nil {
                var maxLvl: CGFloat = -1.0
                let thisFire = CFAbsoluteTimeGetCurrent()
                // calculate how much time passed since the last draw
                let timePassed = thisFire - _peakFalloffLastFire
                for thisMeter in _subLevelMeters {
                    var newLevel = thisMeter.level - CGFloat(timePassed * kLevelFalloffPerSec)
                    if newLevel < 0.0 {newLevel = 0.0}
                    thisMeter.level = newLevel
                    if showsPeaks {
                        var newPeak = thisMeter.peakLevel - CGFloat(timePassed * kPeakFalloffPerSec)
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
                _player!.updateMeters()
                for i in _channelNumbers.indices {
                    let channelIdx = _channelNumbers[i]
                    
                    if channelIdx >= _channelNumbers.count {throw RefreshError.bail}
                    if channelIdx > 127 {throw RefreshError.bail}
                    
                    let channelView = _subLevelMeters[channelIdx]
                    
                    channelView.level = CGFloat(_meterTable.valueAt(_player!.averagePower(forChannel: i)))
                    if showsPeaks {channelView.peakLevel = CGFloat(_meterTable.valueAt(_player!.peakPower(forChannel: i)))
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
        
        _updateTimer?.invalidate()
        
    }
    
    // The AVAudioPlayer object
    var player: AVAudioPlayer? {
        get {return _player}
        
        set(v) {
            if _player == nil && v != nil {
                _updateTimer?.invalidate()
                
                _updateTimer = Timer.scheduledTimer(timeInterval: _refreshHz,
                                                    target: self,
                                                    selector: #selector(_refresh),
                                                    userInfo: nil,
                                                    repeats: true)
            } else if _player != nil && v == nil {
                _peakFalloffLastFire = CFAbsoluteTimeGetCurrent()
            }
            
            _player = v
            
            if let thePlayer = _player {
                thePlayer.isMeteringEnabled = true
                // now check the number of channels in the new queue, we will need to reallocate if this has changed
                if thePlayer.numberOfChannels != _channelNumbers.count {
                    let chan_array: [Int]
                    if thePlayer.numberOfChannels < 2 {
                        chan_array = [0]
                    } else {
                        chan_array = [0, 1]
                    }
                    self.channelNumbers = chan_array
                }
            } else {
                for thisMeter in _subLevelMeters {
                    thisMeter.setNeedsDisplay()
                }
            }
        }
    }
    
    // How many times per second to redraw
    var refreshHz: TimeInterval {
        get {return _refreshHz}
        set(v) {
            _refreshHz = v
            if let updateTimer = _updateTimer {
                updateTimer.invalidate()
                _updateTimer = Timer.scheduledTimer(timeInterval: _refreshHz,
                                                    target: self,
                                                    selector: #selector(_refresh),
                                                    userInfo: nil,
                                                    repeats: true
                )
            }
        }
    }
    
    // Array of NSNumber objects: The indices of the channels to display in this meter
    var channelNumbers: [Int] {
        get {return _channelNumbers}
        set(v) {
            _channelNumbers = v
            self.layoutSubLevelMeters()
        }
    }
    
    // Whether or not to use OpenGL for drawing
    var useGL: Bool {
        get {return _useGL}
        set(v) {
            _useGL = v
            self.layoutSubLevelMeters()
        }
    }
    
    var color: UIColor? {
        get {return _color}
        set(c) {
            _color = c
            self.layoutSubLevelMeters()
        }
    }
    
    @objc private func pauseTimer() {
        if _player != nil, let updateTimer = _updateTimer {
            updateTimer.invalidate()
            _updateTimer = nil
        }
    }
    
    @objc private func resumeTimer() {
        if _player != nil {
            _updateTimer = Timer.scheduledTimer(
                timeInterval: _refreshHz,
                target: self,
                selector: #selector(_refresh),
                userInfo: nil,
                repeats: true)
        }
    }
    
}
