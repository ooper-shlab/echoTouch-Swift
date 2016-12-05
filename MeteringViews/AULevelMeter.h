/*
 </samplecode>
*/

#import <UIKit/UIKit.h>

#import "MeterTable.h"
#import "PowerMeter.h"

#define kPeakFalloffPerSec		.7
#define kLevelFalloffPerSec		.8
#define kMinDBvalue				-80.0
#define kRefreshRate			60.
#define kDefaultSampleRate		44100.

// A LevelMeter subclass which is used specifically for AVAudioPlayer objects
@interface AULevelMeter : UIView {

	NSArray*			_channelNumbers;
	NSArray*			_subLevelMeters;
	MeterTable*			_meterTable;
	PowerMeter*			_powerMeters;
	NSTimer*			_updateTimer;
	CGFloat				_refreshHz;
	double				sampleRate;
	BOOL				_showsPeaks;
	BOOL				_vertical;
	BOOL				_useGL;
	BOOL				_running;
	CFAbsoluteTime		_peakFalloffLastFire;
	UIColor*			color;
}

@property (assign)		BOOL		running;		// Whether the unit is currently running
@property (assign)		CGFloat		refreshHz;		// How many times per second to redraw
@property (assign)		double		sampleRate;		// Sample rate of the audio unit
@property (retain)		NSArray*	channelNumbers; // Array of NSNumber objects: The indices of the channels to display in this meter
@property (retain)		UIColor*	color;
@property (assign)		BOOL		showsPeaks;		// Whether or not we show peak levels
@property (assign)		BOOL		vertical;		// Whether the view is oriented V or H
@property (assign)		BOOL		useGL;			// Whether or not to use OpenGL for drawing
@property (assign)		PowerMeter*	powerMeters;
@end
