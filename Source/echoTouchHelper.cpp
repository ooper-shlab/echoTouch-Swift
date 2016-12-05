/*
 </samplecode>
*/

#include "echoTouchHelper.h"

void LoadVoiceFileDataToMemory(CFURLRef inURL,
                               AudioStreamBasicDescription &outFileDesc,
                               UInt64 &outFileSize,
                               void* &outFileData)
{
	outFileData = NULL;
	AudioFileID afid = 0;
	UInt32 propSize;
	 
	OSStatus result = AudioFileOpenURL(inURL, kAudioFileReadPermission, 0, &afid);
	
	if (result) {
		printf("ERROR LOADING FILE: %d\n", (int)result);
		goto fail;
	}
	
	propSize = sizeof(outFileSize);
	result = AudioFileGetProperty(afid, kAudioFilePropertyAudioDataByteCount, &propSize, &outFileSize);
	if (result) {
		printf("ERROR GETTING FILE SIZE: %d\n", (int)result);
		goto fail;
	}

	propSize = sizeof(outFileDesc);
	result = AudioFileGetProperty(afid, kAudioFilePropertyDataFormat, &propSize, &outFileDesc);
	if (result) {
		printf("ERROR GETTING FILE STREAM DESCRIPTION: %d\n", (int)result);
		goto fail;
	}
	
	outFileData = malloc(outFileSize);
	
	UInt32 bytesToRead;
    
    bytesToRead = (UInt32)outFileSize;
	result = AudioFileReadBytes(afid, false, 0, &bytesToRead, outFileData);
	if (result || (bytesToRead != outFileSize)) {
		printf("ERROR READING FILE AUDIO DATA: %d\n", (int)result);
		goto fail;
	}

	result = AudioFileClose(afid);
	if (result) printf("ERROR CLOSING FILE: %d\n", (int)result);
	
	return;
    
fail:
	if (outFileData) free(outFileData);
	if (afid) AudioFileClose(afid);
	outFileSize = 0;
	outFileData = NULL;
    
	return;
}

OSStatus SetupOutputUnit(AURenderCallbackStruct inInputProc, 
						 AURenderCallbackStruct inRenderProc,
                         AudioUnit &outUnit,
						 const AudioStreamBasicDescription &voiceIOFormat)
{
	OSStatus result = noErr;
	
	// Open the output unit
    AudioComponentDescription desc = { kAudioUnitType_Output,               // type
                                       kAudioUnitSubType_VoiceProcessingIO, // subType
                                       kAudioUnitManufacturer_Apple,        // manufacturer
                                       0, 0 };                              // flags
        
	AudioComponent comp = AudioComponentFindNext(NULL, &desc);
	
	result = AudioComponentInstanceNew(comp, &outUnit);
	if (result) {
		printf("couldn't open the audio unit: %d", (int)result);
		goto end;
	}

	UInt32 one; one = 1;
	result = AudioUnitSetProperty(outUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, sizeof(one));
	if (result) {
		printf("couldn't enable input on the audio unit");
		goto end;
	}
	
	result = AudioUnitSetProperty(outUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &inInputProc, sizeof(inInputProc));
	if (result) {
		printf("couldn't set audio unit input proc");
		goto end;
	}

	result = AudioUnitSetProperty(outUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &inRenderProc, sizeof(inRenderProc));
	if (result) {
		printf("couldn't set audio render callback");
		goto end;
	}

	result = AudioUnitSetProperty(outUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &voiceIOFormat, sizeof(voiceIOFormat));
	if (result) {
		printf("couldn't set the audio unit's output format");
		goto end;
	}
	
	result = AudioUnitSetProperty(outUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &voiceIOFormat, sizeof(voiceIOFormat));
	if (result) {
		printf("couldn't set the audio unit's input client format");
		goto end;
	}
	
	result = AudioUnitInitialize(outUnit);
	if (result) {
		printf("couldn't initialize the audio unit");
		goto end;
	}
                                   
end:
	return result;
}
