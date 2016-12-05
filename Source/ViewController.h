/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The main controller class.
*/

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AVFoundation/AVAudioSession.h>
#import <AudioToolbox/AudioToolbox.h>

#import "AUOutputBL.h"
#import "AVLevelMeter.h"
#import "AULevelMeter.h"

@interface ViewController : UIViewController <AVAudioPlayerDelegate> {
IBOutlet AVLevelMeter       *fxMeter;
IBOutlet AULevelMeter       *speechMeter;
IBOutlet AULevelMeter       *voiceUnitMeter;

IBOutlet UIBarButtonItem    *playButton;
IBOutlet UIBarButtonItem    *recordButton;
IBOutlet UISwitch           *fxSwitch;
IBOutlet UISwitch           *voiceSwitch;
IBOutlet UISwitch           *bypassSwitch;
    
AVAudioPlayer               *fxPlayer;

BOOL						recording;
UInt32						bypassState;

AUOutputBL                  *inputBL;

CFURLRef					fileURL;
ExtAudioFileRef				fileRef;
AVAudioPlayer               *filePlayer;
AVAudioFormat               *fileFormat;

void                        *speechData;
UInt64						speechDataSize;
UInt64						speechDataOffset;
BOOL						playSpeech;

AudioUnit					voiceUnit;
CAStreamBasicDescription	voiceIOFormat;
}

- (IBAction)fxSwitchPressed:(UISwitch*)sender;
- (IBAction)voiceSwitchPressed:(UISwitch*)sender;
- (IBAction)bypassSwitchPressed:(UISwitch*)sender;
- (IBAction)playPressed:(UIBarButtonItem*)sender;
- (IBAction)recordPressed:(UIBarButtonItem*)sender;

@property (nonatomic, retain)	AVLevelMeter*				fxMeter;
@property (nonatomic, retain)	AULevelMeter*				speechMeter;
@property (nonatomic, retain)	AULevelMeter*				voiceUnitMeter;

@property (nonatomic, retain)	AVAudioPlayer*				fxPlayer;
@property (nonatomic, assign)	AudioUnit					voiceUnit;
@property (nonatomic, assign)	AUOutputBL*					inputBL;
@property (assign)				BOOL						recording;
@property (assign)				UInt32						bypassState;
@property (nonatomic, assign)	ExtAudioFileRef				fileRef;

@property (nonatomic, assign)	void*						speechData;
@property (nonatomic, assign)	UInt64						speechDataSize;
@property (nonatomic, assign)	UInt64						speechDataOffset;
@property (nonatomic)			BOOL						playSpeech;
@property (nonatomic, assign)	CAStreamBasicDescription    voiceIOFormat;

@end
