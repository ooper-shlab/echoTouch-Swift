//
//  PowerMeter.swift
//  echoTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/12/3.
//
//
/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 An object to calculate running average RMS power and peak of an audio stream
*/

import CoreAudio

private let kMinLinearPower = 1e-6
private let kMinDecibelsPower = -120.0
private let kMaxDecibelsPower = 20.0

private let kLog001 = -6.907755278982137 // natural log of 0.001 (0.001 is -60 dB)

func calcDecayConstant(_ in60dBDecayTimeInSeconds: Double, _ inSampleRate: Double) -> Double {
    let denominator = in60dBDecayTimeInSeconds * inSampleRate
    if denominator < 1e-5 {return 0.0}
    return exp(kLog001 / denominator)
}

func ampToDb(_ inAmp: Double) -> Double {
    return 20.0 * log10(inAmp)
}

func dbToAmp(_ inDb: Double) -> Double {
    return pow(10.0, 0.05 * inDb)
}

struct PowerMeter {
    
    var averagePowerDB: Double {return linearToDB(averagePowerLinear)}
    var peakPowerDB: Double {return linearToDB(peakPowerLinear)}
    var averagePowerLinear: Double {return mAveragePowerPeak}
    var peakPowerLinear: Double {return mMaxPeak}
    
    func linearToDB(_ p: Double) -> Double {return (p <= kMinLinearPower) ? kMinDecibelsPower : ampToDb(p)}
    
    private var mSampleRate: Double
    private var mPeakDecay1: Double = 0.0
    private var mPeakDecay: Double
    private var mDecay1: Double = 0.0
    private var mDecay: Double
    private var mPrevBlockSize: Int
    
    private var mAveragePower: Int = 0
    private var mPeakHoldCount: Int = 0
    private var mPeak: Double = 0.0
    private var mAveragePowerPeak: Double = 0.0
    private var mMaxPeak: Double = 0.0
    
    private let kPeakDecay = 0.006
    private let kDecay = 0.016
    
    private let kPeakResetTime = 0.9		// in seconds
    
    private let kUnknownSampleRate = 0.0
    private let kUnknownBlockSize = -1
    
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //	PowerMeter::PowerMeter()
    //
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    init() {
        mSampleRate = kUnknownSampleRate
        mPeakDecay = kPeakDecay
        mDecay = kDecay
        mPrevBlockSize = kUnknownBlockSize
        reset()
    }
    
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //	PowerMeter::Reset()
    //
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    mutating func reset() {
        mPeak = 0
        mMaxPeak = 0
        mAveragePower = 0
        mAveragePowerPeak = 0
        
        mPrevBlockSize = kUnknownBlockSize
        mPeakHoldCount = 0
    }
    
    mutating func setSampleRate(_ inSampleRate: Double) {
        mSampleRate = inSampleRate
        
        // 3.33 was determined by reverse engineering kPeakDecay:
        // x = 1 - pow(1 - kPeakDecay, 1/128);  ..this backs out the per sample value from the per block value.
        // 3.33 = log(0.001)/(44100. * log(1. - x))  ..this calculates the 60dB time constant
        // 3.33 seems too slow. use 2.5
        mPeakDecay1 = calcDecayConstant(2.5, inSampleRate)
        
        // 1.24 was determined by reverse engineering kDecay:
        // x = 1 - pow(1 - kDecay, 1/128);  ..this backs out the per sample value from the per block value.
        // 1.24 = log(0.001)/(44100. * log(1. - x));  ..this calculates the 60dB time constant
        mDecay1 = calcDecayConstant(1.24, inSampleRate)
    }
    
    mutating func processSilence(_ nframes: Int) {
        mPeak = 0
        mMaxPeak = 0
        mAveragePower = 0
        mAveragePowerPeak = 0
        mPeakHoldCount = 0
    }
    
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //	PowerMeter::ScaleDecayConstants()
    //
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    
    mutating func scaleDecayConstants(_ inFramesToProcess: Int) {
        if inFramesToProcess != mPrevBlockSize {
            if mSampleRate == kUnknownSampleRate {
                setSampleRate(44100.0)
            }
            mPeakDecay = 1.0 - pow(mPeakDecay1, Double(inFramesToProcess))
            mDecay = 1.0 - pow(mDecay1, Double(inFramesToProcess))
            mPrevBlockSize = inFramesToProcess
        }
    }
    
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //	PowerMeter::SavePeaks()
    //
    //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    
    mutating func savePeaks(_ inFramesToProcess: Int, _ averagePower: Int, _ maxSample: Int) {
        let fAveragePower = Double(averagePower) * 0x1.0p-30	// divide by 2^30
        let peakValue = Double(maxSample) * 0x1.0p-15			// divide by 2^15
        let powerValue = sqrt(fAveragePower) * M_SQRT2			// formula is to divide
        
        mAveragePower = averagePower
        
        // scale power value correctly
        if mPeak > peakValue {
            // exponential decay
            mPeak += (peakValue - mPeak) * mDecay
        } else {
            // hit peaks instantly
            mPeak = peakValue
        }
        
        mPeakHoldCount += inFramesToProcess
        
        let peakResetFrames = Int(kPeakResetTime * mSampleRate)
        
        if mPeakHoldCount >= peakResetFrames {
            // reset current peak
            mMaxPeak -=  mMaxPeak * mPeakDecay
        }
        if mMaxPeak < mPeak {
            mMaxPeak = mPeak
            mPeakHoldCount = 0
        }
        
        if mAveragePowerPeak > powerValue {
            // exponential decay
            mAveragePowerPeak += (powerValue - mAveragePowerPeak) * mDecay
        } else {
            // hit power peaks instantly
            mAveragePowerPeak = powerValue
        }
        
        if mAveragePowerPeak > mMaxPeak {
            mAveragePowerPeak = mMaxPeak	// ?
        }
    }
    
    mutating func process_Int16(_ src: UnsafePointer<Int16>,
                                _ stride: Int,
                                _ inFramesToProcess: Int)
    {
        scaleDecayConstants(inFramesToProcess)
        
        // update peak and average power
        var nframes = inFramesToProcess
        
        var averagePower = mAveragePower
        var maxSample = 0
        var src = src
        while true {
            nframes -= 1
            guard nframes >= 0 else {break}
            var sample = Int(src.pointee)
            src += stride
            if sample < 0 {sample = -sample}
            if sample > maxSample {maxSample = sample}
            averagePower += (sample * sample - averagePower) >> 5	// div 32 -- filter
            // sample is 0..32768 (2^15), so averagePower is relative to 2^30
        }
        
        savePeaks(inFramesToProcess, averagePower, maxSample)
    }
    
    mutating func process_Int32(_ src: UnsafePointer<Int32>,
                                _ stride: Int,
                                _ inFramesToProcess: Int)
    {
        scaleDecayConstants(inFramesToProcess)
        
        // update peak and average power
        var nframes = inFramesToProcess
        
        var averagePower = mAveragePower
        var maxSample = 0
        var src = src
        while true {
            nframes -= 1
            guard nframes >= 0 else {break}
            var sample = Int(src.pointee >> 9)	// 8.24 is really S7.24! -> S0.15 = 9 bits
            src += stride
            if sample < 0 {sample = -sample}
            if sample > maxSample {maxSample = sample}
            averagePower += (sample * sample - averagePower) >> 5	// div 32 -- filter
            // sample is 0..32768 (2^15), so averagePower is relative to 2^30
        }
        
        savePeaks(inFramesToProcess, averagePower, maxSample)
    }
}
