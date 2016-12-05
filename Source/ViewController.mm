/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The main controller class.
*/

#import "ViewController.h"
#import "echoTouchHelper.h"
#import "CAStreamBasicDescription.h"

@implementation ViewController

#pragma mark properties

@synthesize fxPlayer;
@synthesize voiceUnit;
@synthesize inputBL;
@synthesize recording;
@synthesize bypassState;
@synthesize fileRef;

@synthesize fxMeter;
@synthesize voiceUnitMeter;
@synthesize speechMeter;

@synthesize speechData;
@synthesize speechDataSize;
@synthesize speechDataOffset;
@synthesize voiceIOFormat;
@synthesize playSpeech;

#pragma mark implementation

#pragma mark- OutputUnit Render Callback
static OSStatus	ReadVoiceData(void						 *inRefCon,
                              AudioUnitRenderActionFlags *ioActionFlags,
                              const AudioTimeStamp 		 *inTimeStamp,
                              UInt32                     inBusNumber,
                              UInt32 					 inNumberFrames,
                              AudioBufferList 			 *ioData)
{
    ViewController *This = (ViewController*)inRefCon;
    
    UInt32 bytesToRead = This.voiceIOFormat.FramesToBytes(inNumberFrames);
    
    if (This.playSpeech == NO) {
        This.speechMeter.powerMeters[0].ProcessSilence(inNumberFrames);
        memset(ioData->mBuffers[0].mData, 0, bytesToRead);
        return noErr;
    }
    
    if ((This.speechDataOffset + bytesToRead) > This.speechDataSize)
        bytesToRead = (UInt32)(This.speechDataSize - This.speechDataOffset);
    
    //NSLog(@"Reading %d bytes (from offset %d), for %d requested frames", bytesToRead, This.speechDataOffset, inNumberFrames);
    
    ioData->mBuffers[0].mData = (UInt8*)This.speechData + This.speechDataOffset;
    ioData->mBuffers[0].mDataByteSize = bytesToRead;
    
    This.speechDataOffset += ioData->mBuffers[0].mDataByteSize;
    
    if (This.speechDataOffset >= This.speechDataSize)
        This.speechDataOffset = 0;
    
    This.speechMeter.powerMeters[0].Process_Int16((SInt16*)ioData->mBuffers[0].mData, 1, inNumberFrames);
    
    return noErr;
}

#pragma mark- OutpuUnit Input Callback
static OSStatus	MonitorInput(void						*inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp 		*inTimeStamp,
                             UInt32 					inBusNumber,
                             UInt32 					inNumberFrames,
                             AudioBufferList 			*ioData)
{
    ViewController *This = (ViewController*)inRefCon;
    
    This.inputBL->Prepare(inNumberFrames);
    
    OSStatus err = AudioUnitRender(This.voiceUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, This.inputBL->ABL());
    if (err) { NSLog(@"inputProc: error %d\n", (int)err); return err; }
    
    if (This.recording) {
        err = ExtAudioFileWriteAsync(This.fileRef, inNumberFrames, This.inputBL->ABL());
        if (err) { NSLog(@"ExtAudioFileWriteAsync: error %d\n", (int)err); return err; }
    }
    
    This.voiceUnitMeter.powerMeters[0].Process_Int16((SInt16*)This.inputBL->ABL()->mBuffers[0].mData, 1, inNumberFrames);
    
    //This.inputBL->Print();
    
    return err;
}

#pragma mark- AVAudioSession Notifications

// we just print out the results for informational purposes
- (void)handleInterruption:(NSNotification *)notification
{
    UInt8 theInterruptionType = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
    NSLog(@"Session interrupted > --- %s ---\n", theInterruptionType == AVAudioSessionInterruptionTypeBegan ? "Begin Interruption" : "End Interruption");
    
    if (theInterruptionType == AVAudioSessionInterruptionTypeBegan) {
        // your audio session is deactivated automatically when your app is interrupted
        // perform any other tasks required to handled being interrupted
        
        if (recording) {
            recording = NO;
            recordButton.title = @"Record";
            
            if (fileRef) {
                ExtAudioFileDispose(fileRef);
                fileRef = NULL;
            }
        }
        
        // turn off the playback elements
        [fxSwitch setOn:NO animated:NO];
        [self toggleFXPlayback:NO];
        
        if (nil != filePlayer) {
            filePlayer.delegate = nil;
            [filePlayer release];
            filePlayer = nil;
        }
        
        playButton.enabled = NO;
        playButton.title = @"Play";
        
    }
    
    if (theInterruptionType == AVAudioSessionInterruptionTypeEnded) {
        // make sure to activate the session, it does not get activated for you automatically
        NSError *error = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&error];
        if (nil != error) NSLog(@"AVAudioSession set active failed with error: %@", error);
        
        // perform any other tasks to have the app start up after an interruption
        
         [self toggleFXPlayback:fxSwitch.isOn];
        
        // Synchronize bypass state
        OSStatus result = AudioUnitSetProperty(voiceUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &bypassState, sizeof(bypassState));
        if (result) NSLog(@"Error setting voice unit bypass: %d\n", result);
        
        AudioOutputUnitStart(voiceUnit);
    }
}

// we just print out the results for informational purposes
- (void)handleRouteChange:(NSNotification *)notification
{
    UInt8 reasonValue = [[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue];
    AVAudioSessionRouteDescription *routeDescription = [notification.userInfo valueForKey:AVAudioSessionRouteChangePreviousRouteKey];
    
    NSLog(@"Route change:");
    switch (reasonValue) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"     NewDeviceAvailable");
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            NSLog(@"     OldDeviceUnavailable");
            break;
        case AVAudioSessionRouteChangeReasonCategoryChange:
            NSLog(@"     CategoryChange");
            NSLog(@" New Category: %@", [[AVAudioSession sharedInstance] category]);
            break;
        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"     Override");
            break;
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"     WakeFromSleep");
            break;
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"     NoSuitableRouteForCategory");
            break;
        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
             NSLog(@"    RouteConfigurationChange");
             break;
        case AVAudioSessionRouteChangeReasonUnknown:
            NSLog(@"     Reason Unknown");
            break;
        default:
            NSLog(@"     Reason Really Unknown");
            NSLog(@"           Reason Value %d", reasonValue);
    }
    
    NSLog(@"Previous route:\n");
    NSLog(@"%@", routeDescription);
    
    NSLog(@"Current route:\n");
    NSLog(@"%@", [[AVAudioSession sharedInstance] currentRoute]);
}

// reset the world!
// see https://developer.apple.com/library/content/qa/qa1749/_index.html
- (void)handleMediaServicesWereReset:(NSNotification *)notification
{
    NSLog(@"Media services have reset - ouch!");
    
    [self resetIOUnit];
    [self setupIOUnit];
}

#pragma mark-

- (void)toggleFXPlayback:(BOOL)playbackOn
{
    if (playbackOn) {
        [fxPlayer play];
        [fxMeter setPlayer:fxPlayer];
    } else {
        [fxPlayer pause];
        [fxMeter setPlayer:nil];
    }
}

- (void)toggleSpeechPlayback:(BOOL)speechOn
{
    self.playSpeech = speechOn;
    self.speechMeter.running = speechOn;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupIOUnit];
    
    // add AVAudioSession interruption handlers
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
    
    // we don't do anything special in the route change notification
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:[AVAudioSession sharedInstance]];
    
    // if media services are reset, we need to rebuild our audio chain
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMediaServicesWereReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:[AVAudioSession sharedInstance]];
    
    CFStringRef recordFile = (CFStringRef)[NSTemporaryDirectory() stringByAppendingPathComponent: @"input.caf"];
    fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, recordFile, kCFURLPOSIXPathStyle, false);
    filePlayer = nil;
    
    NSLog(@"record file url: %@", fileURL);
}

- (void)setupIOUnit
{
    // Configure the audio session
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    if (!sessionInstance) NSLog(@"ERROR GETTING SHARED AUDIO SESSION");
    
    // we are going to play and record so we pick that category
    NSError *error = nil;
    [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    if (error) NSLog(@"ERROR SETTING AUDIO CATEGORY: %ld", (long)error.code);
    
    // setting this mode no longer allows AVAudioSessionCategoryOptionDefaultToSpeaker so you would
    // need to use the override in the case you wanted to go to speaker
    /*[sessionInstance setMode:AVAudioSessionModeVoiceChat error:&error];
    if (error) NSLog(@"ERROR MODE: %ld", (long)error.code);*/

    // Setup the sound fx player
    // loops the playing of sound effects
    // this is an AAC, Stereo, 44.100 kHz file
    NSURL *fxURL = [[[NSURL alloc] initFileURLWithPath: [[NSBundle mainBundle] pathForResource:@"fx" ofType:@"caf"]] autorelease];
    
    fxPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fxURL error:nil];
    fxPlayer.numberOfLoops = -1;
    
    // Setup the speech sample file and set the voice processing I/O format
    //
    // There are 4 different speech files at various sample rates to test with - sampleVoice8kHz, sampleVoice16kHz, sampleVoice441kHz and sampleVoice48kHz
    // This "speech" file is meant to simulate a "far-end" talkers telephone conversation
    //
    // Audio data for all three is in the same sample data format - 16-bit Integer (Little Endian), Mono and only the sample rates differ
    //
    // IMPORTANT:
    // We use the file data format and sample rate to set up the VPIO input / output format and use
    // the sample rate to set the hardware preferred sample rate as well - any changes to the speech file will alter these settings
    // so make sure you understand what's being changed!
    
    // The meters and API used for the meters expect 16-bit integer data which we provide in the speech test .wav file (see the meters Process_Int16 function)
    // if you would like to test a different data format and expect the meters to work you will need to modify the code accordingly
    
    AudioStreamBasicDescription speechFileFormat;
    
    // there are a number of sample "speech" files for 8, 16, 44.1 & 48kHz sample rates included named 'sampleVoiceXXXkHz'
    CFURLRef speechFileURL = (CFURLRef)[[NSURL alloc] initFileURLWithPath: [[NSBundle mainBundle] pathForResource:@"sampleVoice8kHz" ofType:@"wav"]];
    LoadVoiceFileDataToMemory(speechFileURL, speechFileFormat, speechDataSize, speechData);
    CFRelease(speechFileURL);
    
    // set up voiceIO AU format using the format of the "speech" file which simulates a far end talking "connection"
    voiceIOFormat = CAStreamBasicDescription(speechFileFormat);
    printf("Voice I/O Format: ");
    voiceIOFormat.Print();
    
    // We need to use this sample rate for the voice unit and speech output metering
    speechMeter.sampleRate = (double)voiceIOFormat.mSampleRate;
    UIColor* speechMeterColor = [[[UIColor alloc] initWithRed:0. green:0. blue:1. alpha:1.] autorelease];
    speechMeter.color = speechMeterColor;
    
    voiceUnitMeter.sampleRate = (double)voiceIOFormat.mSampleRate;
    UIColor* voiceMeterColor = [[[UIColor alloc] initWithRed:1. green:0. blue:0. alpha:1.] autorelease];
    voiceUnitMeter.color = voiceMeterColor;
    
    UIColor* fxMeterColor = [[[UIColor alloc] initWithRed:0. green:1. blue:0. alpha:1.] autorelease];
    fxMeter.color = fxMeterColor;
    
    speechDataOffset = 0;
    playSpeech = NO;
    
    // Now setup the voice unit
    AURenderCallbackStruct renderProc = { ReadVoiceData, self };
    AURenderCallbackStruct inputProc = { MonitorInput, self };
    
    // we will use the same format for playing the sample voice audio and capturing the voice processor input
    OSStatus result = SetupOutputUnit(inputProc, renderProc, voiceUnit, voiceIOFormat);
    if (result) NSLog(@"ERROR SETTING UP VOICE UNIT: %d\n", (int)result);
    
    inputBL = new AUOutputBL(voiceIOFormat, 1024);
    
    // set the captured audio file as signed 16-bit native-endian integers with a sample rate and channel count
    // to what will be provided by the voice processing unit
    fileFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                  sampleRate:(double)voiceIOFormat.mSampleRate
                                                    channels:voiceIOFormat.NumberChannels()
                                                 interleaved:YES];

    NSLog(@"Speech File Audio Format: %@\n", fileFormat.settings);
    
    // set the preferred hardware rate to our simulated voice connection format
    // however, if we don't get this rate it's perfectly fine since the I/O unit performs
    // any required sample rate conversions for us
    [[AVAudioSession sharedInstance] setPreferredSampleRate:voiceIOFormat.mSampleRate error:&error];
    if (error) NSLog(@"ERROR SETTING SESSION SAMPLE RATE! %ld", (long)error.code);

    // activate the audio session
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) NSLog(@"ERROR SETTING SESSION ACTIVE! %ld", (long)error.code);
    
    // print out the hardware sample rate for informational purposes, if it's not the
    // same as our consistently used simulated voice connection sample rate it's perfectly fine
    // since the I/O unit takes care of any sample rate conversions for us
    NSLog(@"Hardware Sample Rate: %f\n", [AVAudioSession sharedInstance].sampleRate);
    
    result = AudioOutputUnitStart(voiceUnit);
    if (result) NSLog(@"ERROR STARTING VOICE UNIT: %ld\n", (long)result);
    
    voiceUnitMeter.running = YES;
    bypassState = 0;
}

// called due to a AVAudioSessionMediaServicesWereResetNotification
// causing us to tear down everything in hopes to set it all up again
-(void) resetIOUnit
{
    voiceUnitMeter.running = NO;
    [bypassSwitch setOn:NO animated:YES];
    
    // turn off the playback elements
    [fxSwitch setOn:NO animated:YES];
    [self toggleFXPlayback:NO];
    
    [voiceSwitch setOn:NO animated:YES];
    [self toggleSpeechPlayback:NO];
    
    playButton.enabled = NO;
    playButton.title = @"Play";
    
    if (fxPlayer) [fxPlayer release], fxPlayer = nil;
    
    if (filePlayer) {
        filePlayer.delegate = nil;
        [filePlayer release];
        filePlayer = nil;
    }
    
    recording = NO;
    recordButton.title = @"Record";
    
    if (fileRef) {
        ExtAudioFileDispose(fileRef);
        fileRef = NULL;
    }
    
    [fileFormat release];
    fileFormat = nil;
    
    AudioComponentInstanceDispose(voiceUnit);
    voiceUnit = NULL;
    
    delete inputBL;
    inputBL = NULL;
    voiceIOFormat = CAStreamBasicDescription::sEmpty;
}

- (IBAction)fxSwitchPressed:(UISwitch*)sender {
    
    [self toggleFXPlayback:sender.on];
}

- (IBAction)voiceSwitchPressed:(UISwitch*)sender {
    
    [self toggleSpeechPlayback:sender.on];
}

- (IBAction)bypassSwitchPressed:(UISwitch*)sender {
    
    bypassState = (sender.on) ? 1 : 0;
    
    OSStatus result = AudioUnitSetProperty(voiceUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &bypassState, sizeof(bypassState));
    if (!result) NSLog(@"Voice Processor %s\n", bypassState ? "Bypassed" : "On"); else NSLog(@"Error setting voice unit bypass: %d\n", result);
}

- (IBAction)playPressed:(UIBarButtonItem*)sender {

    if (nil == filePlayer) {
        NSError *error = nil;
        filePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:(NSURL*)fileURL error:&error];
        if (error) {
            NSLog(@"Error Creating File Player %ld", error.code);
        }
    }
    
    if (filePlayer) {
        if (filePlayer.playing) {
        
            NSLog(@"playPressed: File Player Paused");
            
            [filePlayer pause];
            
            // Synchronize bypass state
            OSStatus result = AudioUnitSetProperty(voiceUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &bypassState, sizeof(bypassState));
            if (result) NSLog(@"Error setting voice unit bypass: %d\n", result);
            
            // Start the voice unit
            result = AudioOutputUnitStart(voiceUnit);
            if (result) NSLog(@"ERROR STARTING VOICE UNIT: %d\n", (int)result);
            
            voiceUnitMeter.running = YES;
            
            sender.title = @"Play";
            
        } else {
        
            NSLog(@"playPressed: File Player Playing");
            
            // Stop the voice unit
            OSStatus result = AudioOutputUnitStop(voiceUnit);
            if (result) NSLog(@"ERROR STOPPING VOICE UNIT: %d\n", (int)result);
            
            voiceUnitMeter.running = NO;
            
            // turn off the playback elements
            [fxSwitch setOn:NO animated:YES];
            [self toggleFXPlayback:NO];
            
            [voiceSwitch setOn:NO animated:YES];
            [self toggleSpeechPlayback:NO];
            
            filePlayer.delegate = self;
            [filePlayer play];
            
            sender.title = @"Stop";
        }
    } else {
        // we don't have a valid file player, so don't allow playback
        NSLog(@"playPressed: No File Player!");
        
        sender.enabled = NO;
    }
}

- (IBAction)recordPressed:(UIBarButtonItem*)sender {
   
    OSStatus result = noErr;
    
    if (recording) {
    
        NSLog(@"recordPressed: Stopped Recording!");
        
        recording = NO;
        
        // close the file just recorded
        result = ExtAudioFileDispose(fileRef);
        if (result) NSLog(@"Error disposing audio file! %d", result);
        
        // log the output file lenght
        UInt64 byteCount;
        UInt32 size =sizeof(byteCount);
        AudioFileID outAudioFile;
        AudioFileOpenURL(fileURL, kAudioFileReadPermission, 0, &outAudioFile);
        AudioFileGetProperty(outAudioFile, kAudioFilePropertyAudioDataByteCount, &size, &byteCount);
        NSLog(@"Time: %f", byteCount / (fileFormat.streamDescription->mSampleRate * fileFormat.streamDescription->mChannelsPerFrame * fileFormat.streamDescription->mBitsPerChannel/8));
        AudioFileClose(outAudioFile);
        
        // dispose of any previous players
        if (nil != filePlayer) {
            filePlayer.delegate = nil;
            [filePlayer release];
            filePlayer = nil;
        }
        
        sender.title = @"Record";
        
        // turn off the playback elements
        [fxSwitch setOn:NO animated:YES];
        [self toggleFXPlayback:NO];
        
        [voiceSwitch setOn:NO animated:YES];
        [self toggleSpeechPlayback:NO];
        
        playButton.enabled = YES;
        
    } else {
        
        NSLog(@"recordPressed: Recording!");
    
        playButton.enabled = NO;
        
        result = ExtAudioFileCreateWithURL(fileURL, kAudioFileCAFType, fileFormat.streamDescription, NULL, kAudioFileFlags_EraseFile, &fileRef);
        if (result) { NSLog(@"ERROR CREATING RECORD FILE: %d", result); return; }
        
        result = ExtAudioFileSetProperty(fileRef, kExtAudioFileProperty_ClientDataFormat, sizeof(voiceIOFormat), &voiceIOFormat);
        if (result) { NSLog(@"ERROR SETTING CLIENT FORMAT: %d", result); return; }
        
        // initialize async writes with 0 number of frames
        result = ExtAudioFileWriteAsync(fileRef, 0, NULL);
        if (result) { NSLog(@"ERROR PRIMING RECORD FILE: %d", result); return; }
        
        sender.title = @"Stop";
        
        recording = YES;
    }
}

- (void)dealloc {
    
    [fxMeter release];
    [speechMeter release];
    [voiceUnitMeter release];
    [fxPlayer release];
    [playButton release];
    
    if (fxPlayer) [fxPlayer release];
    
    if (filePlayer) {
        filePlayer.delegate = nil;
        [filePlayer release];
    }
    
    [fileFormat release];
    
    delete inputBL;
    
    if (fileRef) {
        ExtAudioFileDispose(fileRef);
        fileRef = NULL;
    }
    
    CFRelease(fileURL);
    
    AudioComponentInstanceDispose(voiceUnit);
    
    [bypassSwitch release];
    [recordButton release];
    [super dealloc];
}

#pragma mark AVAudioPlayer delegate methods
// only used by the recorded file player

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)avPlayer successfully:(BOOL)flag
{
    if(avPlayer == filePlayer) {
    
        NSLog(@"           : File Player Stopped Playing");
        
        OSStatus result = AudioOutputUnitStart(voiceUnit);
        if (result) NSLog(@"ERROR STARTING VOICE UNIT: %d\n", (int)result);
        
        voiceUnitMeter.running = YES;
        
        [avPlayer setCurrentTime:0.0];
        
        playButton.title = @"Play";
    }
}

- (void)playerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    NSLog(@"ERROR IN DECODE: %@\n", error); 
}

@end
