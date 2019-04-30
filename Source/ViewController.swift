//
//  ViewController.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/2.
//
//
/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 The main controller class.
*/

import UIKit
import AVFoundation
import AudioToolbox

@objc(ViewController)
class ViewController: UIViewController, AVAudioPlayerDelegate {
    @IBOutlet weak var fxMeter: AVLevelMeter!
    @IBOutlet weak var speechMeter: AULevelMeter!
    @IBOutlet weak var voiceUnitMeter: AULevelMeter!
    
    @IBOutlet weak var playButton: UIBarButtonItem!
    @IBOutlet weak var recordButton: UIBarButtonItem!
    @IBOutlet weak var fxSwitch: UISwitch!
    @IBOutlet weak var voiceSwitch: UISwitch!
    @IBOutlet weak var bypassSwitch: UISwitch!
    
    //MARK: properties
    
    var fxPlayer: AVAudioPlayer!
    
    var recording: Bool = false
    var bypassState: UInt32 = 0
    
    var inputBL: AUOutputBL!
    
    var fileURL: URL!
    var fileRef: ExtAudioFileRef?
    var filePlayer: AVAudioPlayer?
    var fileFormat: AVAudioFormat?
    
    var speechData: UnsafeMutableRawPointer?
    var speechDataSize: UInt64 = 0
    var speechDataOffset: Int = 0
    var playSpeech: Bool = false
    
    var voiceUnit: AudioUnit?
    var voiceIOFormat: CAStreamBasicDescription = CAStreamBasicDescription()
    
    //MARK: implementation
    
    //MARK:- OutputUnit Render Callback
    private let ReadVoiceData: AURenderCallback = {inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData in
        let This = Unmanaged<ViewController>.fromOpaque(inRefCon).takeUnretainedValue()
        
        var bytesToRead = This.voiceIOFormat.framesToBytes(Int(inNumberFrames))
        
        if !This.playSpeech {
            This.speechMeter.powerMeters[0].processSilence(Int(inNumberFrames))
            memset(ioData!.pointee.mBuffers.mData, 0, bytesToRead)
            return noErr
        }
        
        if This.speechDataOffset + Int(bytesToRead) > Int(This.speechDataSize) {
            bytesToRead = Int(This.speechDataSize) - This.speechDataOffset
        }
        
        //NSLog("Reading \(bytesToRead) bytes (from offset \(This.speechDataOffset)), for \(inNumberFrames) requested frames")
        
        ioData!.pointee.mBuffers.mData = This.speechData! + This.speechDataOffset
        ioData!.pointee.mBuffers.mDataByteSize = UInt32(bytesToRead)
        
        This.speechDataOffset += Int(ioData!.pointee.mBuffers.mDataByteSize)
        
        if This.speechDataOffset >= Int(This.speechDataSize) {
            This.speechDataOffset = 0
        }
        This.speechMeter.powerMeters[0].process_Int16(ioData!.pointee.mBuffers.mData!.assumingMemoryBound(to: Int16.self), 1, Int(inNumberFrames))
        
        return noErr
    }
    
    //MARK:- OutpuUnit Input Callback
    private let MonitorInput: AURenderCallback = {inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData in
        
        let This = Unmanaged<ViewController>.fromOpaque(inRefCon).takeUnretainedValue()
        
        try! This.inputBL.prepare(Int(inNumberFrames))
        
        var err = AudioUnitRender(This.voiceUnit!, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, This.inputBL.abl!.unsafeMutablePointer)
        if err != noErr {NSLog("inputProc: error \(err)\n"); return err}
        
        if This.recording {
            err = ExtAudioFileWriteAsync(This.fileRef!, inNumberFrames, This.inputBL.abl!.unsafePointer)
            if err != noErr {NSLog("ExtAudioFileWriteAsync: error \(err)\n"); return err}
        }
        
        This.voiceUnitMeter.powerMeters[0].process_Int16(This.inputBL.abl![0].mData!.assumingMemoryBound(to: Int16.self), 1, Int(inNumberFrames))
        
        //This.inputBL.print()
        
        return err
    }
    
    //MARK:- AVAudioSession Notifications
    
    // we just print out the results for informational purposes
    @objc func handleInterruption(_ notification: Notification) {
        let theInterruptionType = notification.userInfo![AVAudioSessionInterruptionTypeKey] as! UInt
        NSLog("Session interrupted > --- \(theInterruptionType == AVAudioSession.InterruptionType.began.rawValue ? "Begin Interruption" : "End Interruption") ---\n")
        
        if theInterruptionType == AVAudioSession.InterruptionType.began.rawValue {
            // your audio session is deactivated automatically when your app is interrupted
            // perform any other tasks required to handled being interrupted
            
            if recording {
                recording = false
                recordButton.title = "Record"
                
                if fileRef != nil {
                    ExtAudioFileDispose(fileRef!)
                    fileRef = nil
                }
            }
            
            // turn off the playback elements
            fxSwitch.setOn(false, animated: false)
            self.toggleFXPlayback(false)
            
            filePlayer?.delegate = nil
            filePlayer = nil
            
            playButton.isEnabled = false
            playButton.title = "Play"
            
        }
        
        if theInterruptionType == AVAudioSession.InterruptionType.ended.rawValue {
            // make sure to activate the session, it does not get activated for you automatically
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                NSLog("AVAudioSession set active failed with error: \(error)")
            }
            
            // perform any other tasks to have the app start up after an interruption
            
            self.toggleFXPlayback(fxSwitch.isOn)
            
            // Synchronize bypass state
            let result = AudioUnitSetProperty(voiceUnit!, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &bypassState, UInt32(MemoryLayout.size(ofValue: bypassState)))
            if result != noErr {NSLog("Error setting voice unit bypass: \(result)\n")}
            
            AudioOutputUnitStart(voiceUnit!)
        }
    }
    
    // we just print out the results for informational purposes
    @objc func handleRouteChange(_ notification: Notification) {
        let reasonValue = notification.userInfo![AVAudioSessionRouteChangeReasonKey] as! UInt
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        let routeDescription = notification.userInfo![AVAudioSessionRouteChangePreviousRouteKey] as! AVAudioSessionRouteDescription
        
        NSLog("Route change:")
        switch reason {
        case .newDeviceAvailable?:
            NSLog("     NewDeviceAvailable")
        case .oldDeviceUnavailable?:
            NSLog("     OldDeviceUnavailable")
        case .categoryChange?:
            NSLog("     CategoryChange")
            NSLog(" New Category: \(AVAudioSession.sharedInstance().category)")
        case .override?:
            NSLog("     Override")
        case .wakeFromSleep?:
            NSLog("     WakeFromSleep")
        case .noSuitableRouteForCategory?:
            NSLog("     NoSuitableRouteForCategory")
        case .routeConfigurationChange?:
            NSLog("    RouteConfigurationChange")
        case .unknown?:
            NSLog("     Reason Unknown")
        default:
            NSLog("     Reason Really Unknown")
            NSLog("           Reason Value \(reasonValue)")
        }
        
        NSLog("Previous route:\n")
        NSLog("\(routeDescription)")
        
        NSLog("Current route:\n")
        NSLog("\(AVAudioSession.sharedInstance().currentRoute)")
        
    }
    // reset the world!
    // see https://developer.apple.com/library/content/qa/qa1749/_index.html
    @objc func handleMediaServicesWereReset(_ notification: Notification) {
        NSLog("Media services have reset - ouch!")
        
        self.resetIOUnit()
        self.setupIOUnit()
    }
    
    //MARK:-
    
    private func toggleFXPlayback(_ playbackOn: Bool) {
        if playbackOn {
            fxPlayer.play()
            fxMeter.player = fxPlayer
        } else {
            fxPlayer.pause()
            fxMeter.player = nil
        }
    }
    
    private func toggleSpeechPlayback(_ speechOn: Bool) {
        self.playSpeech = speechOn
        self.speechMeter.running = speechOn
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupIOUnit()
        
        // add AVAudioSession interruption handlers
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
        
        // we don't do anything special in the route change notification
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRouteChange),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: AVAudioSession.sharedInstance())
        
        // if media services are reset, we need to rebuild our audio chain
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMediaServicesWereReset),
                                               name: AVAudioSession.mediaServicesWereResetNotification,
                                               object: AVAudioSession.sharedInstance())
        
        fileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("input.caf")
        filePlayer = nil
        
        NSLog("record file url: \(fileURL!)")
    }
    
    private func setupIOUnit() {
        // Configure the audio session
        let sessionInstance = AVAudioSession.sharedInstance()
        
        // we are going to play and record so we pick that category
        do {
            if #available(iOS 10.0, *) {
                try sessionInstance.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            } else {
                try sessionInstance.setCategory(.playAndRecord, options: .defaultToSpeaker)
            }
        } catch let error as NSError {
            NSLog("ERROR SETTING AUDIO CATEGORY: \(error.code)")
        }
        
        // setting this mode no longer allows AVAudioSessionCategoryOptionDefaultToSpeaker so you would
        // need to use the override in the case you wanted to go to speaker
        /*do {
         try sessionInstance.setMode(AVAudioSessionModeVoiceChat)
         } catch let error as NSError {
         NSLog("ERROR MODE: \(error.code)")
         }*/
        
        // Setup the sound fx player
        // loops the playing of sound effects
        // this is an AAC, Stereo, 44.100 kHz file
        let fxURL = Bundle.main.url(forResource: "fx", withExtension: "caf")!
        
        fxPlayer = try! AVAudioPlayer(contentsOf: fxURL)
        fxPlayer.numberOfLoops = -1
        
        // Setup the speech sample file and set the voice processing I/O format
        //
        // There are 4 different speech files at various sample rates to test with - sampleVoice8kHz, sampleVoice16kHz, sampleVoice441kHz and sampleVoice48kHz
        // This "speech" file is meant to simulate a "far-end" talkers telephone conversation
        //
        // Audio data for all three is in the same sample data format - 16-bit Integer (Little Endian), Mono and only the sample rates differ
        //
        // IMPORTANT:
        // We use the file data format and sample rate to set up the VPIO input / output format and use
        // the sample rate to set the hardware preferred sample rate as well - any changes to the speech file will alter these settings
        // so make sure you understand what's being changed!
        
        // The meters and API used for the meters expect 16-bit integer data which we provide in the speech test .wav file (see the meters Process_Int16 function)
        // if you would like to test a different data format and expect the meters to work you will need to modify the code accordingly
        
        var speechFileFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
        
        // there are a number of sample "speech" files for 8, 16, 44.1 & 48kHz sample rates included named 'sampleVoiceXXXkHz'
        let speechFileURL = Bundle.main.url(forResource: "sampleVoice8kHz", withExtension: "wav")!
        loadVoiceFileDataToMemory(speechFileURL, &speechFileFormat, &speechDataSize, &speechData)
        
        // set up voiceIO AU format using the format of the "speech" file which simulates a far end talking "connection"
        voiceIOFormat = CAStreamBasicDescription(speechFileFormat)
        print("Voice I/O Format: ", terminator: "")
        voiceIOFormat.print()
        
        // We need to use this sample rate for the voice unit and speech output metering
        speechMeter.sampleRate = voiceIOFormat.mSampleRate
        let speechMeterColor = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        speechMeter.color = speechMeterColor
        
        voiceUnitMeter.sampleRate = voiceIOFormat.mSampleRate
        let voiceMeterColor = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        voiceUnitMeter.color = voiceMeterColor
        
        let fxMeterColor = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        fxMeter.color = fxMeterColor
        
        speechDataOffset = 0
        playSpeech = false
        
        // Now setup the voice unit
        let renderProc = AURenderCallbackStruct(inputProc: ReadVoiceData, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        let inputProc = AURenderCallbackStruct(inputProc: MonitorInput, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        
        // we will use the same format for playing the sample voice audio and capturing the voice processor input
        var result = setupOutputUnit(inputProc, renderProc, &voiceUnit, &voiceIOFormat)
        if result != noErr {NSLog("ERROR SETTING UP VOICE UNIT: \(result)\n")}
        
        inputBL = AUOutputBL(voiceIOFormat, 1024)
        
        // set the captured audio file as signed 16-bit native-endian integers with a sample rate and channel count
        // to what will be provided by the voice processing unit
        fileFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: voiceIOFormat.mSampleRate,
                                   channels: AVAudioChannelCount(voiceIOFormat.numberChannels),
                                   interleaved: true)
        
        NSLog("Speech File Audio Format: \(fileFormat?.settings ?? [:])\n")
        
        // set the preferred hardware rate to our simulated voice connection format
        // however, if we don't get this rate it's perfectly fine since the I/O unit performs
        // any required sample rate conversions for us
        do {
            try AVAudioSession.sharedInstance().setPreferredSampleRate(voiceIOFormat.mSampleRate)
        } catch let error as NSError {
            NSLog("ERROR SETTING SESSION SAMPLE RATE! \(error.code)")
        }
        
        // activate the audio session
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error as NSError {
            NSLog("ERROR SETTING SESSION ACTIVE! \(error.code)")
        }
        
        // print out the hardware sample rate for informational purposes, if it's not the
        // same as our consistently used simulated voice connection sample rate it's perfectly fine
        // since the I/O unit takes care of any sample rate conversions for us
        NSLog("Hardware Sample Rate: %f\n", AVAudioSession.sharedInstance().sampleRate)
        
        result = AudioOutputUnitStart(voiceUnit!)
        if result != noErr {NSLog("ERROR STARTING VOICE UNIT: \(result)\n")}
        
        voiceUnitMeter.running = true
        bypassState = 0
    }
    
    // called due to a AVAudioSessionMediaServicesWereResetNotification
    // causing us to tear down everything in hopes to set it all up again
    private func resetIOUnit() {
        voiceUnitMeter.running = false
        bypassSwitch.setOn(false, animated: true)
        
        // turn off the playback elements
        fxSwitch.setOn(false, animated: true)
        self.toggleFXPlayback(false)
        
        voiceSwitch.setOn(false, animated: true)
        self.toggleSpeechPlayback(false)
        
        playButton.isEnabled = false
        playButton.title = "Play"
        
        fxPlayer = nil
        
        filePlayer?.delegate = nil
        filePlayer = nil
        
        recording = false
        recordButton.title = "Record"
        
        if fileRef != nil {
            ExtAudioFileDispose(fileRef!)
            fileRef = nil
        }
        
        fileFormat = nil
        
        AudioComponentInstanceDispose(voiceUnit!)
        voiceUnit = nil
        
        inputBL = nil
        voiceIOFormat = CAStreamBasicDescription.sEmpty
    }
    
    @IBAction func fxSwitchPressed(_ sender: UISwitch) {
        
        self.toggleFXPlayback(sender.isOn)
    }
    
    @IBAction func voiceSwitchPressed(_ sender: UISwitch) {
        
        self.toggleSpeechPlayback(sender.isOn)
    }
    
    @IBAction func bypassSwitchPressed(_ sender: UISwitch) {
        
        bypassState = sender.isOn ? 1 : 0
        
        let result = AudioUnitSetProperty(voiceUnit!, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &bypassState, UInt32(MemoryLayout.size(ofValue: bypassState)))
        if result == noErr {NSLog("Voice Processor \(bypassState != 0 ? "Bypassed" : "On")\n")} else {NSLog("Error setting voice unit bypass: \(result)\n")}
    }
    
    @IBAction func playPressed(_ sender: UIBarButtonItem) {
        
        if filePlayer == nil {
            do {
                filePlayer = try AVAudioPlayer(contentsOf: fileURL)
            } catch let error as NSError {
                NSLog("Error Creating File Player \(error.code)")
            }
        }
        
        if let filePlayer = filePlayer {
            if filePlayer.isPlaying {
                
                NSLog("playPressed: File Player Paused")
                
                filePlayer.pause()
                
                // Synchronize bypass state
                var result = AudioUnitSetProperty(voiceUnit!, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &bypassState, UInt32(MemoryLayout.size(ofValue: bypassState)))
                if result != noErr {NSLog("Error setting voice unit bypass: \(result)\n")}
                
                // Start the voice unit
                result = AudioOutputUnitStart(voiceUnit!)
                if result != noErr {NSLog("ERROR STARTING VOICE UNIT: \(result)\n")}
                
                voiceUnitMeter.running = true
                
                sender.title = "Play"
                
            } else {
                
                NSLog("playPressed: File Player Playing")
                
                // Stop the voice unit
                let result = AudioOutputUnitStop(voiceUnit!)
                if result != noErr {NSLog("ERROR STOPPING VOICE UNIT: \(result)\n")}
                
                voiceUnitMeter.running = false
                
                // turn off the playback elements
                fxSwitch.setOn(false, animated: true)
                self.toggleFXPlayback(false)
                
                voiceSwitch.setOn(false, animated: true)
                self.toggleSpeechPlayback(false)
                
                filePlayer.delegate = self
                filePlayer.play()
                
                sender.title = "Stop"
            }
        } else {
            // we don't have a valid file player, so don't allow playback
            NSLog("playPressed: No File Player!")
            
            sender.isEnabled = false
        }
    }
    
    @IBAction func recordPressed(_ sender: UIBarButtonItem) {
        
        var result = noErr
        
        if recording {
            
            NSLog("recordPressed: Stopped Recording!")
            
            recording = false
            
            // close the file just recorded
            result = ExtAudioFileDispose(fileRef!)
            if result != noErr {NSLog("Error disposing audio file! \(result)")}
            
            // log the output file lenght
            var byteCount: UInt64 = 0
            var size: UInt32 = UInt32(MemoryLayout.size(ofValue: byteCount))
            var outAudioFile: AudioFileID? = nil
            AudioFileOpenURL(fileURL as CFURL, .readPermission, 0, &outAudioFile)
            AudioFileGetProperty(outAudioFile!, kAudioFilePropertyAudioDataByteCount, &size, &byteCount)
            NSLog("Time: %f", Double(byteCount) / (fileFormat!.streamDescription.pointee.mSampleRate * Double(fileFormat!.streamDescription.pointee.mChannelsPerFrame) * Double(fileFormat!.streamDescription.pointee.mBitsPerChannel/8)))
            AudioFileClose(outAudioFile!)
            
            // dispose of any previous players
            filePlayer?.delegate = nil
            filePlayer = nil
            
            sender.title = "Record"
            
            // turn off the playback elements
            fxSwitch.setOn(false, animated: true)
            self.toggleFXPlayback(false)
            
            voiceSwitch.setOn(false, animated: true)
            self.toggleSpeechPlayback(false)
            
            playButton.isEnabled = true
            
        } else {
            
            NSLog("recordPressed: Recording!")
            
            playButton.isEnabled = false
            
            result = ExtAudioFileCreateWithURL(fileURL! as CFURL, kAudioFileCAFType, fileFormat!.streamDescription, nil, AudioFileFlags.eraseFile.rawValue, &fileRef)
            if result != noErr { NSLog("ERROR CREATING RECORD FILE: \(result)"); return; }
            
            result = ExtAudioFileSetProperty(fileRef!, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.stride(ofValue: voiceIOFormat)), &voiceIOFormat)
            if result != noErr { NSLog("ERROR SETTING CLIENT FORMAT: \(result)"); return; }
            
            // initialize async writes with 0 number of frames
            result = ExtAudioFileWriteAsync(fileRef!, 0, nil)
            if result != noErr { NSLog("ERROR PRIMING RECORD FILE: \(result)"); return; }
            
            sender.title = "Stop"
            
            recording = true
        }
    }
    
    deinit {
        
        filePlayer?.delegate = nil
        
        if fileRef != nil {
            ExtAudioFileDispose(fileRef!)
            fileRef = nil
        }
        
        AudioComponentInstanceDispose(voiceUnit!)
        
    }
    
    //MARK: AVAudioPlayer delegate methods
    // only used by the recorded file player
    
    func audioPlayerDidFinishPlaying(_ avPlayer: AVAudioPlayer, successfully flag: Bool) {
        if avPlayer === filePlayer {
            
            NSLog("           : File Player Stopped Playing")
            
            let result = AudioOutputUnitStart(voiceUnit!)
            if result != noErr {NSLog("ERROR STARTING VOICE UNIT: \(result)\n")}
            
            voiceUnitMeter.running = true
            
            avPlayer.currentTime = 0.0
            
            playButton.title = "Play"
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        NSLog("ERROR IN DECODE: \(error?.localizedDescription ?? "nil")\n")
    }
    
}
