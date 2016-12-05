/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 An object to calculate running average RMS power and peak of an audio stream
*/

#include "PowerMeter.h"

const double kPeakDecay = 0.006;
const double kDecay = 0.016;

const double kPeakResetTime = 0.9;		// in seconds

#define kUnknownSampleRate 0.0
#define kUnknownBlockSize (-1)

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//	PowerMeter::PowerMeter()
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PowerMeter::PowerMeter()
	: mSampleRate(kUnknownSampleRate), mPeakDecay(kPeakDecay), mDecay(kDecay), mPrevBlockSize(kUnknownBlockSize)
{
	Reset();
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//	PowerMeter::Reset()
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
void PowerMeter::Reset()
{
	mPeak = 0;
	mMaxPeak = 0;
	mAveragePower = 0;
	mAveragePowerPeak = 0;
	
	mPrevBlockSize = kUnknownBlockSize;
	mPeakHoldCount = 0;
}

void	PowerMeter::SetSampleRate(double inSampleRate)
{
	mSampleRate = inSampleRate;
	
	// 3.33 was determined by reverse engineering kPeakDecay:  
	// x = 1 - pow(1 - kPeakDecay, 1/128);  ..this backs out the per sample value from the per block value.
	// 3.33 = log(0.001)/(44100. * log(1. - x))  ..this calculates the 60dB time constant
	// 3.33 seems too slow. use 2.5
	mPeakDecay1 = CalcDecayConstant(2.5, inSampleRate);
	
	// 1.24 was determined by reverse engineering kDecay: 
	// x = 1 - pow(1 - kDecay, 1/128);  ..this backs out the per sample value from the per block value.
	// 1.24 = log(0.001)/(44100. * log(1. - x));  ..this calculates the 60dB time constant
	mDecay1 = CalcDecayConstant(1.24, inSampleRate);
}

void	PowerMeter::ProcessSilence(int nframes)
{
	mPeak = 0;
	mMaxPeak = 0;
	mAveragePower = 0;
	mAveragePowerPeak = 0;
	mPeakHoldCount = 0;
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//	PowerMeter::ScaleDecayConstants()
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

void	PowerMeter::ScaleDecayConstants(int inFramesToProcess)
{
	if (inFramesToProcess != mPrevBlockSize) {
		if (mSampleRate == kUnknownSampleRate)
			SetSampleRate(44100.);
		mPeakDecay = 1. - pow(mPeakDecay1, inFramesToProcess);
		mDecay = 1. - pow(mDecay1, inFramesToProcess);
		mPrevBlockSize = inFramesToProcess;
	}
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//	PowerMeter::SavePeaks()
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

void PowerMeter::SavePeaks(int inFramesToProcess, int averagePower, int maxSample)
{
	double fAveragePower = double(averagePower) * 0x1.0p-30;	// divide by 2^30
	float peakValue = double(maxSample) * 0x1.0p-15;			// divide by 2^15
	double powerValue = sqrt(fAveragePower) * M_SQRT2;			// formula is to divide by 1/sqrt(2)
	
	mAveragePower = averagePower;
	
	// scale power value correctly	
	if (mPeak > peakValue)
		// exponential decay
		mPeak += (peakValue - mPeak) * mDecay;
	else
		// hit peaks instantly
		mPeak = peakValue;

	mPeakHoldCount += inFramesToProcess;
	
	int peakResetFrames = int(kPeakResetTime * mSampleRate);

	if (mPeakHoldCount >= peakResetFrames)
		// reset current peak
		mMaxPeak -=  mMaxPeak * mPeakDecay;
	if (mMaxPeak < mPeak) {
		mMaxPeak = mPeak;
		mPeakHoldCount = 0;
	}

	if(mAveragePowerPeak > powerValue)
		// exponential decay
		mAveragePowerPeak += (powerValue - mAveragePowerPeak) * mDecay;
	else
		// hit power peaks instantly
		mAveragePowerPeak = powerValue;

	if (mAveragePowerPeak > mMaxPeak)
		mAveragePowerPeak = mMaxPeak;	// ?
}

void	PowerMeter::Process_Int16(	const SInt16 *	src,
								int				stride,
								int		 		inFramesToProcess)
{
	ScaleDecayConstants(inFramesToProcess);
	
	// update peak and average power
	int nframes = inFramesToProcess;

	int averagePower = mAveragePower;
	int maxSample = 0;
	while (--nframes >= 0) {
		int sample = *src;
		src += stride;
		if (sample < 0) sample = -sample;		
		if (sample > maxSample) maxSample = sample;
		averagePower += (sample * sample - averagePower) >> 5;	// div 32 -- filter
		// sample is 0..32768 (2^15), so averagePower is relative to 2^30
	}

	SavePeaks(inFramesToProcess, averagePower, maxSample);
}

void	PowerMeter::Process_Int32(	const SInt32 *	src,
								int				stride,
								int		 		inFramesToProcess)
{
	ScaleDecayConstants(inFramesToProcess);
	
	// update peak and average power
	int nframes = inFramesToProcess;

	int averagePower = mAveragePower;
	int maxSample = 0;
	while (--nframes >= 0) {
		int sample = *src >> 9;	// 8.24 is really S7.24! -> S0.15 = 9 bits
		src += stride;
		if (sample < 0) sample = -sample;
		if (sample > maxSample) maxSample = sample;
		averagePower += (sample * sample - averagePower) >> 5;	// div 32 -- filter
		// sample is 0..32768 (2^15), so averagePower is relative to 2^30
	}

	SavePeaks(inFramesToProcess, averagePower, maxSample);
}
