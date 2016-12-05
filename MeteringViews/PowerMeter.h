/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 An object to calculate running average RMS power and peak of an audio stream
*/

#ifndef __PowerMeter
#define __PowerMeter

#include <CoreAudio/CoreAudioTypes.h>
#include <math.h>

const double kMinLinearPower = 1e-6;
const double kMinDecibelsPower = -120.0;
const double kMaxDecibelsPower = 20.0;

const double kLog001 = -6.907755278982137; // natural log of 0.001 (0.001 is -60 dB)

inline double CalcDecayConstant(double in60dBDecayTimeInSeconds, double inSampleRate)
{
	double denominator = in60dBDecayTimeInSeconds * inSampleRate;
	if (denominator < 1e-5) return 0.;
	return exp(kLog001 / denominator);
}

inline double AmpToDb(double inAmp)
{
	return 20. * log10(inAmp);
}

inline double DbToAmp(double inDb)
{
	return pow(10., 0.05 * inDb);
}

class PowerMeter
{
public:
	PowerMeter();
	
	void		Reset();
	void		SetSampleRate(double sr);

	void		Process_Int32(	const SInt32 	*inSourceP,
							int					inSourceStride,
							int					inFramesToProcess);

	void		Process_Int16(	const SInt16 	*inSourceP,
							int					inSourceStride,
							int					inFramesToProcess);
		
	void		ProcessSilence(int nframes);
	
	double		GetAveragePowerDB() const { return LinearToDB(GetAveragePowerLinear()); }
	double		GetPeakPowerDB() const { return LinearToDB(GetPeakPowerLinear()); }
	double		GetAveragePowerLinear() const { return mAveragePowerPeak; }
	double		GetPeakPowerLinear() const { return mMaxPeak; }

private:	
	void		ScaleDecayConstants(int inFramesToProcess);
	double		LinearToDB(double p) const { return (p <= kMinLinearPower) ? kMinDecibelsPower : AmpToDb(p); }
	void		SavePeaks(int inFramesToProcess, int averagePower, int maxSample);

private:
	double	mSampleRate;
	double	mPeakDecay1, mPeakDecay;
	double	mDecay1, mDecay;
	int		mPrevBlockSize;

	int		mAveragePower;
	int		mPeakHoldCount;
	double	mPeak;
	double	mAveragePowerPeak;
	double	mMaxPeak;
};

#endif // __PowerMeter
