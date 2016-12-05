/*
 </samplecode>
*/

#include "MeterTable.h"

inline double DbToAmp(double inDb) { return pow(10., 0.05 * inDb); }

MeterTable::MeterTable(float inMinDecibels, size_t inTableSize, float inRoot)
	: mMinDecibels(inMinDecibels),
	mDecibelResolution(mMinDecibels / (inTableSize - 1)), 
	mScaleFactor(1. / mDecibelResolution)
{
	if (inMinDecibels >= 0.) {
		printf("MeterTable inMinDecibels must be negative");
		return;
	}

	mTable = (float*)malloc(inTableSize*sizeof(float));

	double minAmp = DbToAmp(inMinDecibels);
	double ampRange = 1. - minAmp;
	double invAmpRange = 1. / ampRange;
	
	double rroot = 1. / inRoot;
	for (size_t i = 0; i < inTableSize; ++i) {
		double decibels = i * mDecibelResolution;
		double amp = DbToAmp(decibels);
		double adjAmp = (amp - minAmp) * invAmpRange;
		mTable[i] = pow(adjAmp, rroot);
	}
}

MeterTable::~MeterTable()
{
	free(mTable);
}
