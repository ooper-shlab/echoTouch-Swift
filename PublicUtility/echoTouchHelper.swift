//
//  echoTouchHelper.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/3.
//
//
/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Basic Utility Functions
*/

import AudioToolbox

func loadVoiceFileDataToMemory(_ inURL: URL,
                               _ outFileDesc: inout AudioStreamBasicDescription,
                               _ outFileSize: inout UInt64,
                               _ outFileData: inout UnsafeMutableRawPointer?)
{
    enum LoadVoiceFileDataToMemoryError : Error {
        case fail(String, OSStatus)
    }
    
    outFileData = nil
    var afid: AudioFileID? = nil
    
    do {
        var result = AudioFileOpenURL(inURL as CFURL, .readPermission, 0, &afid)
        
        guard result == noErr, let afid = afid else {
            throw LoadVoiceFileDataToMemoryError.fail("LOADING FILE", result)
        }
        
        var propSize = UInt32(MemoryLayout.size(ofValue: outFileSize))
        result = AudioFileGetProperty(afid, kAudioFilePropertyAudioDataByteCount, &propSize, &outFileSize)
        guard result == noErr else {
            throw LoadVoiceFileDataToMemoryError.fail("GETTING FILE SIZE", result)
        }
        
        propSize = UInt32(MemoryLayout.size(ofValue: outFileDesc))
        result = AudioFileGetProperty(afid, kAudioFilePropertyDataFormat, &propSize, &outFileDesc)
        guard result == noErr else {
            throw LoadVoiceFileDataToMemoryError.fail("GETTING FILE STREAM DESCRIPTION", result)
        }
        
        outFileData = malloc(Int(outFileSize))
        
        var bytesToRead = UInt32(outFileSize)
        result = AudioFileReadBytes(afid, false, 0, &bytesToRead, outFileData!)
        guard result == noErr && bytesToRead == UInt32(outFileSize) else {
            throw LoadVoiceFileDataToMemoryError.fail("READING FILE AUDIO DATA", result)
        }
        
        result = AudioFileClose(afid)
        if result != noErr {print("ERROR CLOSING FILE: \(result)")}
        
    } catch let error {
        if case let LoadVoiceFileDataToMemoryError.fail(message, result) = error {
            print("ERROR \(message): \(result)")
        }
        if let outFileData = outFileData {free(outFileData)}
        if let afid = afid {AudioFileClose(afid)}
        outFileSize = 0
        outFileData = nil
        
    }
}

func setupOutputUnit(_ inInputProc: AURenderCallbackStruct,
                     _ inRenderProc: AURenderCallbackStruct,
                     _ outUnit: inout AudioUnit?,
                     _ voiceIOFormat: inout AudioStreamBasicDescription) -> OSStatus
{
    enum SetupOutputUnitError: Error {
        case endWithResult(String, OSStatus)
        case end(String)
    }
    
    var result = noErr
    
    // Open the output unit
    var desc = AudioComponentDescription(
        componentType: kAudioUnitType_Output,               // type
        componentSubType: kAudioUnitSubType_VoiceProcessingIO, // subType
        componentManufacturer: kAudioUnitManufacturer_Apple,        // manufacturer
        componentFlags: 0, componentFlagsMask: 0)                              // flags
    
    do {
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw SetupOutputUnitError.end("no AudioComponent found")
        }
        
        result = AudioComponentInstanceNew(comp, &outUnit)
        guard result == noErr, let outUnit = outUnit else {
            throw SetupOutputUnitError.endWithResult("couldn't open the audio unit", result)
        }
        
        var one: UInt32 = 1
        result = AudioUnitSetProperty(outUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, UInt32(MemoryLayout.size(ofValue: one)))
        guard result == noErr else {
            throw SetupOutputUnitError.end("couldn't enable input on the audio unit")
        }
        
        var inputProc = inInputProc
        result = AudioUnitSetProperty(outUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &inputProc, UInt32(MemoryLayout.size(ofValue: inputProc)))
        guard result == noErr else {
            throw SetupOutputUnitError.end("couldn't set audio unit input proc")
        }
        
        var renderProc = inRenderProc
        result = AudioUnitSetProperty(outUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderProc, UInt32(MemoryLayout.size(ofValue: renderProc)))
        guard result == noErr else {
            throw SetupOutputUnitError.end("couldn't set audio render callback")
        }
        
        result = AudioUnitSetProperty(outUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &voiceIOFormat, UInt32(MemoryLayout.size(ofValue: voiceIOFormat)))
        guard result == noErr else {
            throw SetupOutputUnitError.end("couldn't set the audio unit's output format")
        }
        
        result = AudioUnitSetProperty(outUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &voiceIOFormat, UInt32(MemoryLayout.size(ofValue: voiceIOFormat)))
        guard result == noErr else {
            throw SetupOutputUnitError.end("couldn't set the audio unit's input client format")
        }
        
        result = AudioUnitInitialize(outUnit)
        guard result == noErr else {
            throw SetupOutputUnitError.end("couldn't initialize the audio unit")
        }
        
    } catch let SetupOutputUnitError.endWithResult(message, result) {
        print("\(message): \(result)")
    } catch let SetupOutputUnitError.end(message) {
        print(message)
    } catch {
        print("unknonw error: \(error)")
    }
    return result
}
