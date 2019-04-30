//
//  CAStreamBasicDescription.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/2.
//
//
/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 TPart of CoreAudio Utility Classes.
*/

import Foundation
import CoreAudio

// MARK:	This file needs to compile on more earlier versions of the OS, so please keep that in mind when editing it
//### We do not cosider old platforms which Swift does not support.

//=============================================================================
//	CAStreamBasicDescription
//
//	This is a wrapper class for the AudioStreamBasicDescription struct.
//	It adds a number of convenience routines, but otherwise adds nothing
//	to the footprint of the original struct.
//=============================================================================
//### CAStreamBasicDescription is a typealias of AudioStreamBasicDescription, we define an extension.
typealias CAStreamBasicDescription = AudioStreamBasicDescription
extension CAStreamBasicDescription {
    
    //	Constants
    
    enum CommonPCMFormat: Int {
        case other = 0
        case float32 = 1
        case int16 = 2
        case fixed824 = 3
        case float64 = 4
    }
    
    //	Construction/Destruction
    
    init?(_ inSampleRate: Double, _ inNumChannels: UInt32, _ pcmf: CommonPCMFormat, _ inIsInterleaved: Bool) {
        self.init()
        
        mSampleRate = inSampleRate
        mFormatID = kAudioFormatLinearPCM
        mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked
        mFramesPerPacket = 1
        mChannelsPerFrame = inNumChannels
        mBytesPerFrame = 0
        mBytesPerPacket = 0
        mReserved = 0
        
        let wordsize: UInt32
        switch pcmf {
        case .float32:
            wordsize = 4
            mFormatFlags |= kAudioFormatFlagIsFloat
        case .float64:
            wordsize = 8
            mFormatFlags |= kAudioFormatFlagIsFloat
        case .int16:
            wordsize = 2
            mFormatFlags |= kAudioFormatFlagIsSignedInteger
        case .fixed824:
            wordsize = 4
            mFormatFlags |= kAudioFormatFlagIsSignedInteger | (24 << kLinearPCMFormatFlagsSampleFractionShift)
        default:
            return nil
        }
        mBitsPerChannel = wordsize * 8
        if inIsInterleaved {
            mBytesPerPacket = wordsize * inNumChannels
            mBytesPerFrame = mBytesPerPacket
        } else {
            mFormatFlags |= kAudioFormatFlagIsNonInterleaved
            mBytesPerPacket = wordsize
            mBytesPerFrame = mBytesPerPacket
        }
    }
    
    //	Assignment
    
    mutating func setFrom(_ desc: AudioStreamBasicDescription) {
        self = desc
    }
    
    // _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    //
    // interrogation
    
    var isPCM: Bool {return mFormatID == kAudioFormatLinearPCM}
    
    var packednessIsSignificant: Bool {
        assert(isPCM, "PackednessIsSignificant only applies for PCM")
        return (sampleWordSize << 3) != Int(mBitsPerChannel)
    }
    
    var alignmentIsSignificant: Bool {
        return packednessIsSignificant || (mBitsPerChannel & 7) != 0
    }
    
    var isInterleaved: Bool {
        return (mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    }
    
    // for sanity with interleaved/deinterleaved possibilities, never access mChannelsPerFrame, use these:
    var numberInterleavedChannels: Int {return isInterleaved ? Int(mChannelsPerFrame) : 1}
    var numberChannels: Int {return Int(mChannelsPerFrame)}
    var sampleWordSize: Int {
        return (mBytesPerFrame > 0 && numberInterleavedChannels != 0) ? Int(mBytesPerFrame) / numberInterleavedChannels :  0
    }
    
    func framesToBytes(_ nframes: Int) -> Int {return nframes * Int(mBytesPerFrame)}
    
    func identifyCommonPCMFormat(_ outFormat: inout CommonPCMFormat, _ outIsInterleaved: UnsafeMutablePointer<Bool>? = nil) -> Bool {	// return true if it's a valid PCM format.
        
        outFormat = .other
        // trap out patently invalid formats.
        if mFormatID != kAudioFormatLinearPCM || mFramesPerPacket != 1 || mBytesPerFrame != mBytesPerPacket || mBitsPerChannel/8 > mBytesPerFrame || mChannelsPerFrame == 0 {
            return false
        }
        let interleaved = (mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        outIsInterleaved?.pointee = interleaved
        var wordsize: UInt32 = mBytesPerFrame
        if interleaved {
            if wordsize % mChannelsPerFrame != 0 {return false}
            wordsize /= mChannelsPerFrame
        }
        
        if (mFormatFlags & kAudioFormatFlagIsBigEndian) == kAudioFormatFlagsNativeEndian
            && wordsize * 8 == mBitsPerChannel {
            // packed and native endian, good
            if (mFormatFlags & kLinearPCMFormatFlagIsFloat) != 0 {
                // float: reject nonsense bits
                if mFormatFlags & (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagsSampleFractionMask) != 0 {
                    return false
                }
                if wordsize == 4 {
                    outFormat = .float32
                }
                if wordsize == 8 {
                    outFormat = .float64
                }
            } else if (mFormatFlags & kLinearPCMFormatFlagIsSignedInteger) != 0 {
                // signed int
                let fracbits = (mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift
                if wordsize == 4 && fracbits == 24 {
                    outFormat = .fixed824
                } else if wordsize == 2 && fracbits == 0 {
                    outFormat = .int16
                }
            }
        }
        return true
    }
    
    // _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    //
    //	manipulation
    
    //MARK:- Deprecations
    /*
     void	SetCanonical(UInt32 nChannels, bool interleaved)
     // note: leaves sample rate untouched
     {
     mFormatID = kAudioFormatLinearPCM;
     UInt32 sampleSize = SizeOf32(AudioSampleType);
     mFormatFlags = kAudioFormatFlagsCanonical;
     mBitsPerChannel = 8 * sampleSize;
     mChannelsPerFrame = nChannels;
     mFramesPerPacket = 1;
     if (interleaved)
     mBytesPerPacket = mBytesPerFrame = nChannels * sampleSize;
     else {
     mBytesPerPacket = mBytesPerFrame = sampleSize;
     mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
     }
     }
     
     bool	IsCanonical() const
     {
     if (mFormatID != kAudioFormatLinearPCM) return false;
     UInt32 reqFormatFlags;
     UInt32 flagsMask = (kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagsSampleFractionMask);
     bool interleaved = (mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0;
     unsigned sampleSize = SizeOf32(AudioSampleType);
     reqFormatFlags = kAudioFormatFlagsCanonical;
     UInt32 reqFrameSize = interleaved ? (mChannelsPerFrame * sampleSize) : sampleSize;
     
     return ((mFormatFlags & flagsMask) == reqFormatFlags
     && mBitsPerChannel == 8 * sampleSize
     && mFramesPerPacket == 1
     && mBytesPerFrame == reqFrameSize
     && mBytesPerPacket == reqFrameSize);
     }
     
     void	SetAUCanonical(UInt32 nChannels, bool interleaved)
     {
     mFormatID = kAudioFormatLinearPCM;
     #if CA_PREFER_FIXED_POINT
     mFormatFlags = kAudioFormatFlagsCanonical | (kAudioUnitSampleFractionBits << kLinearPCMFormatFlagsSampleFractionShift);
     #else
     mFormatFlags = kAudioFormatFlagsCanonical;
     #endif
     mChannelsPerFrame = nChannels;
     mFramesPerPacket = 1;
     mBitsPerChannel = 8 * SizeOf32(AudioUnitSampleType);
     if (interleaved)
     mBytesPerPacket = mBytesPerFrame = nChannels * SizeOf32(AudioUnitSampleType);
     else {
     mBytesPerPacket = mBytesPerFrame = SizeOf32(AudioUnitSampleType);
     mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
     }
     }
     */
    
    //MARK:-
    
    // _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    //
    //	other
    
    func print() {
        print(stdout)
    }
    
    func print(_ file: UnsafeMutablePointer<FILE>) {
        printFormat(file, "", "AudioStreamBasicDescription:")
    }
    
    func printFormat(_ f: UnsafeMutablePointer<FILE>, _ indent: String, _ name: String) {
        fputs("\(indent)\(name) \(asString())\n", f)
    }
    
    //	Operations
    
    
    func CAStringForOSType(_ t: OSType) -> String {
        let str: [UInt8] = (0..<4).map{UInt8(truncatingIfNeeded: t >> (24-$0*8))}
        
        let hasNonPrint = str.reduce(false) {result, c in result || !(isprint(Int32(c)) != 0 && c != UInt8(ascii: "\\"))}
        if !hasNonPrint, let code = String(bytes: str, encoding: .utf8) {
            return "'\(code)'"
        } else {
            return "0x"+str.map{String(format: "%02X", $0)}.joined()
        }
    }
    
    
    static let sEmpty = AudioStreamBasicDescription()
    
    init(_ desc: AudioStreamBasicDescription) {
        self.init()
        setFrom(desc)
    }
    
    func asString(_ brief: Bool = false) -> String {
        var buf: String = ""
        let formatID = CAStringForOSType(mFormatID)
        if brief {
            var com: CommonPCMFormat = .other
            var interleaved: Bool = false
            if identifyCommonPCMFormat(&com, &interleaved) && com != .other {
                let desc: String?
                switch com {
                case .int16:
                    desc = "Int16"
                case .fixed824:
                    desc = "Int8.24"
                case .float32:
                    desc = "Float32"
                case .float64:
                    desc = "Float64"
                default:
                    desc = nil
                }
                if let descr = desc {
                    var inter = ""
                    
                    if mChannelsPerFrame > 1 {
                        inter = !interleaved ? ", non-inter" : ", inter"
                    }
                    buf += String(format: "%2d ch, %6.0f Hz, %@%@", mChannelsPerFrame, mSampleRate, descr, inter)
                    return buf
                }
            }
            if mChannelsPerFrame == 0 && mSampleRate == 0.0 && mFormatID == 0 {
                buf += String(format: "%2d ch, %6.0f Hz", mChannelsPerFrame, mSampleRate)
                return buf
            }
        }
        
        buf += String(format: "%2d ch, %6.0f Hz, %@ (0x%08X) ", numberChannels, mSampleRate, formatID, mFormatFlags)
        if mFormatID == kAudioFormatLinearPCM {
            let isInt = (mFormatFlags & kLinearPCMFormatFlagIsFloat) == 0
            let wordSize = sampleWordSize
            let endian = (wordSize > 1) ?
                ((mFormatFlags & kLinearPCMFormatFlagIsBigEndian) != 0 ? " big-endian" : " little-endian" ) : ""
            let sign = isInt ?
                ((mFormatFlags & kLinearPCMFormatFlagIsSignedInteger) != 0 ? " signed" : " unsigned") : ""
            let floatInt = isInt ? "integer" : "float"
            let packed: String
            if wordSize > 0 && packednessIsSignificant {
                if (mFormatFlags & kLinearPCMFormatFlagIsPacked) != 0 {
                    packed = "packed in \(wordSize) bytes"
                } else {
                    packed = "unpacked in \(wordSize) bytes"
                }
            } else {
                packed = ""
            }
            let align = (wordSize > 0 && alignmentIsSignificant) ?
                ((mFormatFlags & kLinearPCMFormatFlagIsAlignedHigh) != 0 ? " high-aligned" : " low-aligned") : ""
            let deinter = (mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 ? ", deinterleaved" : ""
            let commaSpace = (!packed.isEmpty) || (!align.isEmpty) ? ", " : ""
            let bitdepth: String
            
            let fracbits = (mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift
            if fracbits > 0 {
                bitdepth = "\(mBitsPerChannel - fracbits).\(fracbits)"
            } else {
                bitdepth = String(mBitsPerChannel)
            }
            
            buf += "\(bitdepth)-bit\(endian)\(sign) \(floatInt)\(commaSpace)\(packed)\(align)\(deinter)"
        } else if mFormatID == kAudioFormatAppleLossless {
            var sourceBits = 0
            switch mFormatFlags {
            case 1:	//	kAppleLosslessFormatFlag_16BitSourceData
                sourceBits = 16
            case 2:	//	kAppleLosslessFormatFlag_20BitSourceData
                sourceBits = 20
            case 3:	//	kAppleLosslessFormatFlag_24BitSourceData
                sourceBits = 24
            case 4:	//	kAppleLosslessFormatFlag_32BitSourceData
                sourceBits = 32
            default:
                break
            }
            if sourceBits != 0 {
                buf += String(format: "from %d-bit source, ", sourceBits)
            } else {
                buf += "from UNKNOWN source bit depth, "
            }
            buf += String(format: "%d frames/packet", mFramesPerPacket)
        } else {
            buf += String(format: "%d bits/channel, %d bytes/packet, %d frames/packet, %d bytes/frame",
                          mBitsPerChannel, mBytesPerPacket, mFramesPerPacket, mBytesPerFrame)
        }
        return buf
    }
    
    //MARK:- Deprecations
    
    /*
     void	CAStreamBasicDescription::NormalizeLinearPCMFormat(AudioStreamBasicDescription& ioDescription)
     {
     //  the only thing that changes is to make mixable linear PCM into the canonical linear PCM format
     if((ioDescription.mFormatID == kAudioFormatLinearPCM) && ((ioDescription.mFormatFlags & kIsNonMixableFlag) == 0))
     {
     //  the canonical linear PCM format
     ioDescription.mFormatFlags = kAudioFormatFlagsCanonical;
     ioDescription.mBytesPerPacket = SizeOf32(AudioSampleType) * ioDescription.mChannelsPerFrame;
     ioDescription.mFramesPerPacket = 1;
     ioDescription.mBytesPerFrame = SizeOf32(AudioSampleType) * ioDescription.mChannelsPerFrame;
     ioDescription.mBitsPerChannel = 8 * SizeOf32(AudioSampleType);
     }
     }
     
     void	CAStreamBasicDescription::NormalizeLinearPCMFormat(bool inNativeEndian, AudioStreamBasicDescription& ioDescription)
     {
     //  the only thing that changes is to make mixable linear PCM into the canonical linear PCM format
     if((ioDescription.mFormatID == kAudioFormatLinearPCM) && ((ioDescription.mFormatFlags & kIsNonMixableFlag) == 0))
     {
     //  the canonical linear PCM format
     ioDescription.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
     if(inNativeEndian)
     {
     #if TARGET_RT_BIG_ENDIAN
     ioDescription.mFormatFlags |= kAudioFormatFlagIsBigEndian;
     #endif
     }
     else
     {
     #if TARGET_RT_LITTLE_ENDIAN
     ioDescription.mFormatFlags |= kAudioFormatFlagIsBigEndian;
     #endif
     }
     ioDescription.mBytesPerPacket = SizeOf32(AudioSampleType) * ioDescription.mChannelsPerFrame;
     ioDescription.mFramesPerPacket = 1;
     ioDescription.mBytesPerFrame = SizeOf32(AudioSampleType) * ioDescription.mChannelsPerFrame;
     ioDescription.mBitsPerChannel = 8 * SizeOf32(AudioSampleType);
     }
     }
     */
    
    //MARK-
    
    private enum FromTextError: Error {
        case bail
    }
    func hexValue(_ c: CChar) -> Int32? {
        if c >= "0" && c <= "9" {return Int32(c - "0")}
        if c >= "A" && c <= "F" {return Int32(c - "A" + 10)}
        if c >= "a" && c <= "f" {return Int32(c - "a" + 10)}
        return nil
    }
    private func sscanHex2(_ p: UnsafePointer<CChar>, _ value: UnsafeMutablePointer<Int32>) -> Int {
        if p[0] == 0 || p[1] == 0 {return 0}
        if let v0 = hexValue(p[0]), let v1 = hexValue(p[1]) {
            value.pointee = (v0 << 4) | v1
            return 1
        }
        return 0
    }
    func fromText(_ inTextDesc: UnsafePointer<CChar>, fmt: inout CAStreamBasicDescription) -> Bool {
        var p = inTextDesc
        
        fmt = CAStreamBasicDescription()
        
        var isPCM = true	// until proven otherwise
        var pcmFlags: UInt32 = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger
        
        do {
            if p[0] == "-" {	// previously we required a leading dash on PCM formats
                p += 1
            }
            
            if p[0] == "B" && p[1] == "E" {
                pcmFlags |= kLinearPCMFormatFlagIsBigEndian
                p += 2
            } else if p[0] == "L" && p[1] == "E" {
                p += 2
            } else {
                // default is native-endian
                if 1.bigEndian == 1 {
                    pcmFlags |= kLinearPCMFormatFlagIsBigEndian
                }
            }
            if p[0] == "F" {
                pcmFlags = (pcmFlags & ~kAudioFormatFlagIsSignedInteger) | kAudioFormatFlagIsFloat
                p += 1
            } else {
                if p[0] == "U" {
                    pcmFlags &= ~kAudioFormatFlagIsSignedInteger
                    p += 1
                }
                if p[0] == "I" {
                    p += 1
                } else {
                    // it's not PCM; presumably some other format (NOT VALIDATED; use AudioFormat for that)
                    isPCM = false
                    p = inTextDesc;	// go back to the beginning
                    var buf: [CChar] = Array(repeating: " ", count: 4)
                    for i in 0..<4 {
                        if p.pointee != "\\" {
                            buf[i] = p.pointee
                            p += 1
                            if buf[i] == "\0" {
                                // special-case for 'aac'
                                if i != 3 {return false}
                                p -= 1	// keep pointing at the terminating null
                                buf[i] = " "
                                break
                            }
                        } else {
                            // "\xNN" is a hex byte
                            p += 1
                            if p.pointee != "x" {return false}
                            var x: Int32 = 0
                            p += 1
                            if sscanHex2(p, &x) != 1 {
                                return false
                            }
                            buf[i] = CChar(truncatingIfNeeded: x)
                            p += 2
                        }
                    }
                    
                    if strchr("-@/#", Int32(buf[3])) != nil {
                        // further special-casing for 'aac'
                        buf[3] = " "
                        p -= 1
                    }
                    
                    memcpy(&fmt.mFormatID, buf, 4)
                    fmt.mFormatID = CFSwapInt32BigToHost(fmt.mFormatID)
                }
            }
            
            if isPCM {
                fmt.mFormatID = kAudioFormatLinearPCM
                fmt.mFormatFlags = pcmFlags
                fmt.mFramesPerPacket = 1
                fmt.mChannelsPerFrame = 1
                var bitdepth: UInt32 = 0
                var fracbits: UInt32 = 0
                while isdigit(Int32(p.pointee)) != 0 {
                    bitdepth = 10 * bitdepth + UInt32(p.pointee - "0")
                    p += 1
                }
                if p.pointee == "." {
                    p += 1
                    if isdigit(Int32(p.pointee)) == 0 {
                        fputs("Expected fractional bits following '.'\n", stderr)
                        throw FromTextError.bail
                    }
                    while isdigit(Int32(p.pointee)) != 0 {
                        fracbits = 10 * fracbits + UInt32(p.pointee - "0")
                        p += 1
                    }
                    bitdepth += fracbits
                    fmt.mFormatFlags |= (fracbits << kLinearPCMFormatFlagsSampleFractionShift)
                }
                fmt.mBitsPerChannel = bitdepth
                fmt.mBytesPerFrame = (bitdepth + 7) / 8
                fmt.mBytesPerPacket = fmt.mBytesPerFrame
                if bitdepth & 7 != 0 {
                    // assume unpacked. (packed odd bit depths are describable but not supported in AudioConverter.)
                    fmt.mFormatFlags &= ~kLinearPCMFormatFlagIsPacked
                    // alignment matters; default to high-aligned. use ':L_' for low.
                    fmt.mFormatFlags |= kLinearPCMFormatFlagIsAlignedHigh
                }
            }
            if p.pointee == "@" {
                p += 1
                while isdigit(Int32(p.pointee)) != 0 {
                    fmt.mSampleRate = 10 * fmt.mSampleRate + Double(p.pointee - "0")
                    p += 1
                }
            }
            if p.pointee == "/" {
                var flags: UInt32 = 0
                while true {
                    p += 1
                    let c = p.pointee
                    if let v = hexValue(c) {
                        flags = (flags << 4) | UInt32(bitPattern: v)
                    } else {
                        break
                    }
                }
                fmt.mFormatFlags = flags
            }
            if p.pointee == "#" {
                p += 1
                while isdigit(Int32(p.pointee)) != 0 {
                    fmt.mFramesPerPacket = 10 * fmt.mFramesPerPacket + UInt32(p.pointee - "0")
                    p += 1
                }
            }
            if p.pointee == ":" {
                p += 1
                fmt.mFormatFlags &= ~kLinearPCMFormatFlagIsPacked
                if p.pointee == "L" {
                    fmt.mFormatFlags &= ~kLinearPCMFormatFlagIsAlignedHigh
                } else if p.pointee == "H" {
                    fmt.mFormatFlags |= kLinearPCMFormatFlagIsAlignedHigh
                } else {
                    throw FromTextError.bail
                }
                p += 1
                var bytesPerFrame: UInt32 = 0
                while isdigit(Int32(p.pointee)) != 0 {
                    bytesPerFrame = 10 * bytesPerFrame + UInt32(p.pointee - "0")
                    p += 1
                }
                fmt.mBytesPerPacket = bytesPerFrame
                fmt.mBytesPerFrame = fmt.mBytesPerPacket
            }
            if p.pointee == "," {
                p += 1
                var ch: UInt32 = 0
                while isdigit(Int32(p.pointee)) != 0 {
                    ch = 10 * ch + UInt32(p.pointee - "0")
                    p += 1
                }
                fmt.mChannelsPerFrame = ch
                if p.pointee == "D" {
                    p += 1
                    if fmt.mFormatID != kAudioFormatLinearPCM {
                        fputs("non-interleaved flag invalid for non-PCM formats\n", stderr)
                        throw FromTextError.bail
                    }
                    fmt.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
                } else {
                    if p.pointee == "I" {p += 1}	// default
                    if fmt.mFormatID == kAudioFormatLinearPCM {
                        fmt.mBytesPerFrame *= UInt32(ch)
                        fmt.mBytesPerPacket = fmt.mBytesPerFrame
                    }
                }
            }
            if p.pointee != "\0" {
                fputs(String(format: "extra characters at end of format string: %s\n", p), stderr)
                throw FromTextError.bail
            }
            return true
        } catch {
            
            fputs(String(format: "Invalid format string: %s\n", inTextDesc), stderr)
            fputs("Syntax of format strings is: \n", stderr)
            return false
        }
    }
    
    static let sTextParsingUsageString =
        "format[@sample_rate_hz][/format_flags][#frames_per_packet][:LHbytesPerFrame][,channelsDI].\n" +
    "Format for PCM is [-][BE|LE]{F|I|UI}{bitdepth}; else a 4-char format code (e.g. aac, alac).\n"
}
