/*
 </samplecode>
*/

#include <stdlib.h>
#include <stdio.h>
#include <math.h>

class MeterTable
{
public:
// MeterTable constructor arguments: 
// inNumUISteps - the number of steps in the UI element that will be drawn. 
//					This could be a height in pixels or number of bars in an LED style display.
// inTableSize - The size of the table. The table needs to be large enough that there are no large gaps in the response.
// inMinDecibels - the decibel value of the minimum displayed amplitude.
// inRoot - this controls the curvature of the response. 2.0 is square root, 3.0 is cube root. But inRoot doesn't have to be integer valued, it could be 1.8 or 2.5, etc.

MeterTable(float inMinDecibels = -80., size_t inTableSize = 400, float inRoot = 2.0);	
~MeterTable();
	
	float ValueAt(float inDecibels)
	{
		if (inDecibels < mMinDecibels) return  0.;
		if (inDecibels >= 0.) return 1.;
		int index = (int)(inDecibels * mScaleFactor);
		return mTable[index];
	}
private:
	float	mMinDecibels;
	float	mDecibelResolution;
	float	mScaleFactor;
	float	*mTable;
};
