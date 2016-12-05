/*
 </samplecode>
*/

#import "AULevelMeter.h"
#import "LevelMeter.h"
#import "GLLevelMeter.h"

@interface AULevelMeter (AULevelMeter_priv)
- (void)layoutSubLevelMeters;
- (void)registerForBackgroundNotifications;
- (void)pauseTimer;
- (void)resumeTimer;
@end

@implementation AULevelMeter

@synthesize showsPeaks = _showsPeaks;
@synthesize vertical = _vertical;
@synthesize powerMeters = _powerMeters;

- (id)initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame]) {
		_refreshHz = 1. / kRefreshRate;
		_showsPeaks = YES;
		_channelNumbers = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
		_vertical = NO;
		_useGL = YES;
		sampleRate = kDefaultSampleRate;
		_meterTable = new MeterTable(kMinDBvalue);
		_powerMeters = new PowerMeter;
		color = nil;
		[self layoutSubLevelMeters];
		[self registerForBackgroundNotifications];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)coder {
	if (self = [super initWithCoder:coder]) {
		_refreshHz = 1. / kRefreshRate;
		_showsPeaks = YES;
		_channelNumbers = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
		_vertical = NO;
		_useGL = YES;
		sampleRate = kDefaultSampleRate;
		_meterTable = new MeterTable(kMinDBvalue);
		_powerMeters = new PowerMeter;
		color = nil;
		[self layoutSubLevelMeters];
        [self registerForBackgroundNotifications];
	}
	return self;
}

- (void)registerForBackgroundNotifications
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(pauseTimer)
												 name:UIApplicationWillResignActiveNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(resumeTimer)
												 name:UIApplicationWillEnterForegroundNotification
											   object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(resumeTimer)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)layoutSubLevelMeters
{
	int i;
	for (i=0; i<[_subLevelMeters count]; i++)
	{
		UIView *thisMeter = [_subLevelMeters objectAtIndex:i];
		[thisMeter removeFromSuperview];
	}
	[_subLevelMeters release];
	
	NSMutableArray *meters_build = [[NSMutableArray alloc] initWithCapacity:[_channelNumbers count]];
	
	_powerMeters = (PowerMeter*)realloc(_powerMeters, [_channelNumbers count] * sizeof(PowerMeter));
	
	for (NSInteger i=0; i < [_channelNumbers count]; i++) {
		_powerMeters[i].SetSampleRate(sampleRate);
	}
	
	CGRect totalRect;
	
	if (_vertical) totalRect = CGRectMake(0., 0., [self frame].size.width + 2., [self frame].size.height);
	else  totalRect = CGRectMake(0., 0., [self frame].size.width, [self frame].size.height + 2.);

	for (i=0; i<[_channelNumbers count]; i++)
	{
		CGRect fr;
		
		if (_vertical) {
			fr = CGRectMake(
							totalRect.origin.x + (((CGFloat)i / (CGFloat)[_channelNumbers count]) * totalRect.size.width), 
							totalRect.origin.y, 
							(1. / (CGFloat)[_channelNumbers count]) * totalRect.size.width - 2., 
							totalRect.size.height
							);
		} else {
			fr = CGRectMake(
							totalRect.origin.x, 
							totalRect.origin.y + (((CGFloat)i / (CGFloat)[_channelNumbers count]) * totalRect.size.height), 
							totalRect.size.width, 
							(1. / (CGFloat)[_channelNumbers count]) * totalRect.size.height - 2.
							);
		}
		
		LevelMeter *newMeter;

		if (_useGL) newMeter = [[GLLevelMeter alloc] initWithFrame:fr];
		else newMeter = [[LevelMeter alloc] initWithFrame:fr];
		
		newMeter.numLights = 30;
		newMeter.vertical = self.vertical;

		if (color != nil) {
			LevelMeterColorThreshold tmpThreshold = { 0.0f, color };	
			[newMeter setColorThresholds:&tmpThreshold count:1];
		}
		
		[meters_build addObject:newMeter];
		[self addSubview:newMeter];
		[newMeter release];
	}	
	
	_subLevelMeters = [[NSArray alloc] initWithArray:meters_build];
	
	[meters_build release];
}

- (void)_refresh
{
	BOOL success = NO;

	// if we have no queue, but still have levels, gradually bring them down
	if (_running == NO)
	{
		CGFloat maxLvl = -1.;
		CFAbsoluteTime thisFire = CFAbsoluteTimeGetCurrent();
		// calculate how much time passed since the last draw
		CFAbsoluteTime timePassed = thisFire - _peakFalloffLastFire;
		for (LevelMeter *thisMeter in _subLevelMeters)
		{
			CGFloat newPeak, newLevel;
			newLevel = thisMeter.level - timePassed * kLevelFalloffPerSec;
			if (newLevel < 0.) newLevel = 0.;
			thisMeter.level = newLevel;
			if (_showsPeaks)
			{
				newPeak = thisMeter.peakLevel - timePassed * kPeakFalloffPerSec;
				if (newPeak < 0.) newPeak = 0.;
				thisMeter.peakLevel = newPeak;
				if (newPeak > maxLvl) maxLvl = newPeak;
			}
			else if (newLevel > maxLvl) maxLvl = newLevel;
			
			[thisMeter setNeedsDisplay];
		}
		// stop the timer when the last level has hit 0
		if (maxLvl <= 0.)
		{
			[_updateTimer invalidate];
			_updateTimer = nil;
		}
		
		_peakFalloffLastFire = thisFire;
		success = YES;
	} else {
		for (int i=0; i<[_channelNumbers count]; i++)
		{
			NSInteger channelIdx = [(NSNumber *)[_channelNumbers objectAtIndex:i] intValue];
			LevelMeter *channelView = [_subLevelMeters objectAtIndex:channelIdx];
			
			if (channelIdx >= [_channelNumbers count]) goto bail;
			if (channelIdx > 127) goto bail;
			
			channelView.level = _meterTable->ValueAt(self.powerMeters[i].GetAveragePowerDB());
			if (_showsPeaks) channelView.peakLevel = _meterTable->ValueAt(self.powerMeters[i].GetPeakPowerDB());
			else
				channelView.peakLevel = 0.;
			
			[channelView setNeedsDisplay];
			success = YES;		
		}
	}
	
bail:
	
	if (!success)
	{
		for (LevelMeter *thisMeter in _subLevelMeters) { thisMeter.level = 0.; [thisMeter setNeedsDisplay]; }
		printf("ERROR: metering failed\n");
	}
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    
    [_updateTimer invalidate];
	[_channelNumbers release];
	[_subLevelMeters release];
	
    delete _meterTable;
	
	[super dealloc];
}

- (BOOL)running { return _running; }

- (void)setRunning:(BOOL)v
{	
	if ((_running == NO) && v)
	{
		if (_updateTimer) [_updateTimer invalidate];
		
		_updateTimer = [NSTimer 
						scheduledTimerWithTimeInterval:_refreshHz 
						target:self 
						selector:@selector(_refresh) 
						userInfo:nil 
						repeats:YES
						];
	} else if ((_running == NO) && (v == NO)) {
		_peakFalloffLastFire = CFAbsoluteTimeGetCurrent();
	}
	
	_running = v;
	
	for (LevelMeter *thisMeter in _subLevelMeters) {
		[thisMeter setNeedsDisplay];
	}
}

- (double)sampleRate { return sampleRate; }

- (void)setSampleRate:(double)v
{
	sampleRate = v;
	[self layoutSubLevelMeters];
}

- (CGFloat)refreshHz { return _refreshHz; }

- (void)setRefreshHz:(CGFloat)v
{
	_refreshHz = v;
	if (_updateTimer)
	{
		[_updateTimer invalidate];
		_updateTimer = [NSTimer 
						scheduledTimerWithTimeInterval:_refreshHz 
						target:self 
						selector:@selector(_refresh) 
						userInfo:nil 
						repeats:YES
						];
	}
}


- (NSArray *)channelNumbers { return _channelNumbers; }

- (void)setChannelNumbers:(NSArray *)v
{
	[v retain];
	[_channelNumbers release];
	_channelNumbers = v;
			
	[self layoutSubLevelMeters];
}

- (BOOL)useGL { return _useGL; }

- (void)setUseGL:(BOOL)v
{
	_useGL = v;
	[self layoutSubLevelMeters];
}

- (UIColor*)color { return color; }

- (void)setColor:(UIColor*)c
{
	[c retain];
	[color release];
	color = c;
	
	[self layoutSubLevelMeters];
}

- (void)pauseTimer
{
	[self setRunning:NO];
}

- (void)resumeTimer
{
	[self setRunning:YES];
}

@end
