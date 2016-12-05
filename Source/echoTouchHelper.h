/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Basic Utility Functions
*/

#include <AudioToolbox/AudioToolbox.h>

void LoadVoiceFileDataToMemory(CFURLRef inURL,
                               AudioStreamBasicDescription &outFileDesc,
                               UInt64 &outFileSize,
                               void* &outFileData);

OSStatus SetupOutputUnit(AURenderCallbackStruct inInputProc,
                         AURenderCallbackStruct inRenderProc,
                         AudioUnit &outUnit,
                         const AudioStreamBasicDescription &voiceFormat);
