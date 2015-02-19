/*
 
    File: AQRecorder.mm
Abstract: n/a
 Version: 2.4

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
Inc. ("Apple") in consideration of your agreement to the following
terms, and your use, installation, modification or redistribution of
this Apple software constitutes acceptance of these terms.  If you do
not agree with these terms, please do not use, install, modify or
redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may
be used to endorse or promote products derived from the Apple Software
without specific prior written permission from Apple.  Except as
expressly stated in this notice, no other rights or licenses, express or
implied, are granted by Apple herein, including but not limited to any
patent rights that may be infringed by your derivative works or by other
works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2009 Apple Inc. All Rights Reserved.

 
*/

#include "AQRecorder.h"
//#include "lame.h"

// ____________________________________________________________________________________
// Determine the size, in bytes, of a buffer necessary to represent the supplied number
// of seconds of audio data.
int AQRecorder::ComputeRecordBufferSize(const AudioStreamBasicDescription *format, float seconds)
{
	int packets, frames, bytes = 0;
	try {
		frames = (int)ceil(seconds * format->mSampleRate);
		
		if (format->mBytesPerFrame > 0)
			bytes = frames * format->mBytesPerFrame;
		else {
			UInt32 maxPacketSize;
			if (format->mBytesPerPacket > 0)
				maxPacketSize = format->mBytesPerPacket;	// constant packet size
			else {
				UInt32 propertySize = sizeof(maxPacketSize);
				XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize,
												 &propertySize), "couldn't get queue's maximum output packet size");
			}
			if (format->mFramesPerPacket > 0)
				packets = frames / format->mFramesPerPacket;
			else
				packets = frames;	// worst-case scenario: 1 frame in a packet
			if (packets == 0)		// sanity check
				packets = 1;
			bytes = packets * maxPacketSize;
		}
	} catch (CAXException e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		return 0;
	}	
	return bytes;
}

// ____________________________________________________________________________________
// AudioQueue callback function, called when an input buffers has been filled.
void AQRecorder::MyInputBufferHandler(	void *								inUserData,
										AudioQueueRef						inAQ,
										AudioQueueBufferRef					inBuffer,
										const AudioTimeStamp *				inStartTime,
										UInt32								inNumPackets,
										const AudioStreamPacketDescription*	inPacketDesc)
{
	AQRecorder *aqr = (AQRecorder *)inUserData;
    AudioFileID file;
    SInt64 packet;

	try {
		if (inNumPackets > 0) {
			// write packets to file
            NSLog(@"data size: %ld, %ld",inBuffer->mAudioDataByteSize, inNumPackets);
        
            file = aqr->GetAudioFileID();
            packet = aqr->GetRecordPacket();
            
            
            XThrowIfError(AudioFileWritePackets(file, FALSE, inBuffer->mAudioDataByteSize,
											 inPacketDesc, packet, &inNumPackets, inBuffer->mAudioData),
					   "AudioFileWritePackets failed");
            
            
            if (aqr->whichStream==0) {
                aqr->mRecordPacket1 += inNumPackets;
                
            } else {
                aqr->mRecordPacket2 += inNumPackets;

            }
            
		}
		
		// if we're not stopping, re-enqueue the buffe so that it gets filled again
		if (aqr->IsRunning())
			XThrowIfError(AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL), "AudioQueueEnqueueBuffer failed");

        //frames = (int)ceil(kBufferDurationSeconds * 44100);
        NSLog(@"ffour is %d",aqr->ffournumber);
        NSLog(@"recordpacket1:%lld",aqr->mRecordPacket1);
        NSLog(@"recordpacket2:%lld",aqr->mRecordPacket2);
        
        if (aqr->mRecordPacket1>= aqr->ffournumber) { // started with 435747
            aqr->CopyEncoderCookieToFile();
            aqr->switchNow = YES;
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center postNotificationName:@"BlitRecord" object:nil];
            
            //aqr->ffournumber--;
        } else if (aqr->mRecordPacket2>= aqr->ffournumber) {
            aqr->CopyEncoderCookieToFile();
            aqr->switchNow = YES;
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center postNotificationName:@"BlitRecord" object:nil];

            //aqr->ffournumber--;
        }
        
        
        if (aqr->switchNow) {
           // NSLog(@"packet count is %d",aqr->mRecordPacket1);
            aqr->switchNow = NO;
            if (aqr->whichStream==0) {
                
                // Q: can we switch the other stream to a new file now?
                // A: yes we can.
                aqr->whichStream = 1;
                
// Append some blank data to the end.
//                XThrowIfError(AudioFileWritePackets(file, FALSE, inBuffer->mAudioDataByteSize/3,
//                                                    inPacketDesc, packet, &inNumPackets, inBuffer->mAudioData),
//                              "AudioFileWritePackets failed");
                

                aqr->CopyEncoderCookieToSpecificFile(0);
                AudioFileClose(aqr->mRecordFile1);
                aqr->mRecordPacket1 = 0;
                
                // copy and transmit our file here or something. 
                
                NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                aqr->filenumber++;
                NSString *recordFile1 = [documentsDirectory stringByAppendingPathComponent: [NSString stringWithFormat:@"%d.aac",aqr->filenumber]];
                CFStringRef superURL1 = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,  (CFStringRef)recordFile1, NULL, NULL, kCFStringEncodingUTF8);
                CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault,superURL1, NULL);
                NSLog(@"new url is %@", (__bridge NSURL *) url);
                XThrowIfError(AudioFileCreateWithURL(url, kAudioFileAAC_ADTSType, &aqr->mRecordFormat, kAudioFileFlags_EraseFile, &aqr->mRecordFile1), "AudioFileCreateWithURL failed");
                aqr->CopyEncoderCookieToSpecificFile(0);
                CFRelease(url);

            } else {

                // Q: can we switch the other stream to a new file now?
                // A: yes we can.
                aqr->whichStream = 0;
//                XThrowIfError(AudioFileWritePackets(file, FALSE, inBuffer->mAudioDataByteSize,
//                                                    inPacketDesc, packet, &inNumPackets, inBuffer->mAudioData),
//                              "AudioFileWritePackets failed");
                
                aqr->CopyEncoderCookieToSpecificFile(1);
                AudioFileClose(aqr->mRecordFile2);
                aqr->mRecordPacket2 = 0;
                
                NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                aqr->filenumber++;
                NSString *recordFile1 = [documentsDirectory stringByAppendingPathComponent: [NSString stringWithFormat:@"%d.aac",aqr->filenumber]];
                //                NSString *recordFile1 = [documentsDirectory stringByAppendingPathComponent: (__bridge NSString*)aqr->mFileName2];
                CFStringRef superURL1 = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,  (CFStringRef)recordFile1, NULL, NULL, kCFStringEncodingUTF8);
                CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault,superURL1, NULL);
                NSLog(@"new url is %@", (__bridge NSURL *) url);
                XThrowIfError(AudioFileCreateWithURL(url, kAudioFileAAC_ADTSType, &aqr->mRecordFormat, kAudioFileFlags_EraseFile, &aqr->mRecordFile2), "AudioFileCreateWithURL failed");
                aqr->CopyEncoderCookieToSpecificFile(1);
                CFRelease(url);
            }
        }
        fprintf(stderr,"no problems...");
	} catch (CAXException e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
}

AQRecorder::AQRecorder()
{
	mIsRunning = false;
    whichStream = 0;
	mRecordPacket1 = 0;
	mRecordPacket2 = 0;
    filenumber = 1;
}

AQRecorder::~AQRecorder()
{
	AudioQueueDispose(mQueue, TRUE);
    AudioFileClose(mRecordFile1);
    AudioFileClose(mRecordFile2);
    
	if (mFileName1) CFRelease(mFileName1);
	if (mFileName2) CFRelease(mFileName2);
}

// ____________________________________________________________________________________
// Copy a queue's encoder's magic cookie to an audio file.
void AQRecorder::CopyEncoderCookieToFile()
{
	UInt32 propertySize;
	// get the magic cookie, if any, from the converter
	OSStatus err = AudioQueueGetPropertySize(mQueue, kAudioQueueProperty_MagicCookie, &propertySize);
	
	// we can get a noErr result and also a propertySize == 0
	// -- if the file format does support magic cookies, but this file doesn't have one.
	if (err == noErr && propertySize > 0) {
		Byte *magicCookie = new Byte[propertySize];
		UInt32 magicCookieSize;
		XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize), "get audio converter's magic cookie");
		magicCookieSize = propertySize;	// the converter lies and tell us the wrong size
		
		// now set the magic cookie on the output file
		UInt32 willEatTheCookie = false;
		// the converter wants to give us one; will the file take it?
        err = AudioFileGetPropertyInfo(GetAudioFileID(), kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
        if (err == noErr && willEatTheCookie) {
            err = AudioFileSetProperty(GetAudioFileID(), kAudioFilePropertyMagicCookieData, magicCookieSize, magicCookie);
            XThrowIfError(err, "set audio file's magic cookie");
        }
		delete[] magicCookie;
	}
}

void AQRecorder::CopyEncoderCookieToSpecificFile(int which)
{
	UInt32 propertySize;
	// get the magic cookie, if any, from the converter
	OSStatus err = AudioQueueGetPropertySize(mQueue, kAudioQueueProperty_MagicCookie, &propertySize);
	
	// we can get a noErr result and also a propertySize == 0
	// -- if the file format does support magic cookies, but this file doesn't have one.
	if (err == noErr && propertySize > 0) {
		Byte *magicCookie = new Byte[propertySize];
		UInt32 magicCookieSize;
		XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize), "get audio converter's magic cookie");
		magicCookieSize = propertySize;	// the converter lies and tell us the wrong size
		
		// now set the magic cookie on the output file
		UInt32 willEatTheCookie = false;
		// the converter wants to give us one; will the file take it?
        if (which==0) {
            err = AudioFileGetPropertyInfo(mRecordFile1, kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
        } else {
            err = AudioFileGetPropertyInfo(mRecordFile2, kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
        }
        
        if (err == noErr && willEatTheCookie) {
            if (which==0) {
                err = AudioFileSetProperty(mRecordFile1, kAudioFilePropertyMagicCookieData, magicCookieSize, magicCookie);
            } else {
                err = AudioFileSetProperty(mRecordFile2, kAudioFilePropertyMagicCookieData, magicCookieSize, magicCookie);
            }
            XThrowIfError(err, "set audio file's magic cookie");
        }
		delete[] magicCookie;
	}
}

void AQRecorder::SetupAudioFormat(UInt32 inFormatID)
{
	memset(&mRecordFormat, 0, sizeof(mRecordFormat));

	UInt32 size = sizeof(mRecordFormat.mSampleRate);
	XThrowIfError(AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareSampleRate,
										&size, 
										&mRecordFormat.mSampleRate), "couldn't get hardware sample rate");

	size = sizeof(mRecordFormat.mChannelsPerFrame);
	XThrowIfError(AudioSessionGetProperty(	kAudioSessionProperty_CurrentHardwareInputNumberChannels, 
										&size, 
										&mRecordFormat.mChannelsPerFrame), "couldn't get input channel count");
			
	mRecordFormat.mFormatID = inFormatID;
	if (inFormatID == kAudioFormatLinearPCM)
	{
		// if we want pcm, default to signed 16-bit little-endian
		mRecordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
		mRecordFormat.mBitsPerChannel = 16;
		mRecordFormat.mBytesPerPacket = mRecordFormat.mBytesPerFrame = (mRecordFormat.mBitsPerChannel / 8) * mRecordFormat.mChannelsPerFrame;
		mRecordFormat.mFramesPerPacket = 1;
	}
}



void AQRecorder::StartRecord(CFStringRef inRecordFile1, CFStringRef inRecordFile2 )
{
	int i, bufferByteSize;
	UInt32 size;
	CFURLRef url;
	ffournumber = 450;
	try {

		
        
        mFileName1 = CFStringCreateCopy(kCFAllocatorDefault, inRecordFile1);
        mFileName2 = CFStringCreateCopy(kCFAllocatorDefault, inRecordFile2);

		// specify the recording format
		SetupAudioFormat(kAudioFormatMPEG4AAC);
		
		// create the queue
		XThrowIfError(AudioQueueNewInput(
									  &mRecordFormat,
									  MyInputBufferHandler,
									  this /* userData */,
									  NULL /* run loop */, NULL /* run loop mode */,
									  0 /* flags */, &mQueue), "AudioQueueNewInput failed");
		
		// get the record format back from the queue's audio converter --
		// the file may require a more specific stream description than was necessary to create the encoder.
		mRecordPacket1 = 0;
		mRecordPacket2 = 0;

		size = sizeof(mRecordFormat);
		XThrowIfError(AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,	
										 &mRecordFormat, &size), "couldn't get queue's format");
			
        NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
		NSString *recordFile1 = [documentsDirectory stringByAppendingPathComponent: (__bridge NSString*)inRecordFile1];
		NSString *recordFile2 = [documentsDirectory stringByAppendingPathComponent: (__bridge NSString*)inRecordFile2];
        
        CFStringRef superURL1 = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,  (CFStringRef)recordFile1, NULL, NULL, kCFStringEncodingUTF8);
        CFStringRef superURL2 = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,  (CFStringRef)recordFile2, NULL, NULL, kCFStringEncodingUTF8);
		url = CFURLCreateWithString(kCFAllocatorDefault,superURL1, NULL);
		
		// create the audio file
		XThrowIfError(AudioFileCreateWithURL(url, kAudioFileAAC_ADTSType, &mRecordFormat, kAudioFileFlags_EraseFile, &mRecordFile1), "AudioFileCreateWithURL failed");
		CFRelease(url);

		url = CFURLCreateWithString(kCFAllocatorDefault,superURL2, NULL);
		XThrowIfError(AudioFileCreateWithURL(url, kAudioFileAAC_ADTSType, &mRecordFormat, kAudioFileFlags_EraseFile, &mRecordFile2), "AudioFileCreateWithURL failed");
		CFRelease(url);
        

        
        //NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"karza1" ofType:@"jpg"];
        //NSData *data = [NSData dataWithContentsOfFile:iconPath];
        
        
		
		// copy the cookie first to give the file object as much info as we can about the data going in
		// not necessary for pcm, but required for some compressed audio
		CopyEncoderCookieToFile();
		
		// allocate and enqueue buffers
		bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);	// enough bytes for half a second
		for (i = 0; i < kNumberRecordBuffers; ++i) {
			XThrowIfError(AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]),
					   "AudioQueueAllocateBuffer failed");
			XThrowIfError(AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL),
					   "AudioQueueEnqueueBuffer failed");
		}
		// start the queue
		mIsRunning = true;
		XThrowIfError(AudioQueueStart(mQueue, NULL), "AudioQueueStart failed");
	}
	catch (CAXException &e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
	catch (...) {
		fprintf(stderr, "An unknown error occurred\n");
	}	

}

// -1 see if removing mIsRunning affects anything.
// 0) see if dup data works.
// 1) see if CopyEncoderCookieToFile is necessary.
// 2) See if we can just change the rest. 

//void AQRecorder::BlitRecord(int fileID)
//{
//
////    AudioQueueRef   queue2 = mQueue;
////    AudioFileID     recordFile2 = mRecordFile;
////    CFStringRef     mFileName2 = mFileName;
////
////    
////    // end recording
////	mIsRunning = false;
////
////    NSString *s = [NSString stringWithFormat:@"%d.caf", fileID+1];
////    StartRecord( (__bridge CFStringRef) s );
////	
////    XThrowIfError(AudioQueueStop(queue2, true), "AudioQueueStop failed");
////	//CopyEncoderCookieToFile(); // does it?
////	if (mFileName2)
////	{
////		CFRelease(mFileName2);
////		mFileName2 = NULL;
////	}
////	AudioQueueDispose(queue2, true);
////	AudioFileClose(recordFile2);
////    
//// -------------- old code after this...
//
//    
//}




void AQRecorder::BlitRecord(int fileID)
{
	// end recording
//	mIsRunning = false;
//	XThrowIfError(AudioQueueStop(mQueue, true), "AudioQueueStop failed");
	// a codec may update its cookie at the end of an encoding session, so reapply it to the file now
//	CopyEncoderCookieToFile();
    

    //switchNow = YES;
    
    //	if (mFileName1)
//	{
//		CFRelease(mFileName1);
//		mFileName1 = NULL;
//	}
//
//    if (mFileName2)
//	{
//		CFRelease(mFileName2);
//		mFileName2 = NULL;
//	}
//
//	AudioQueueDispose(mQueue, true);
//	AudioFileClose(mRecordFile1);
//	AudioFileClose(mRecordFile2);
//    
//    NSString *s = [NSString stringWithFormat:@"%d.caf", fileID+1];
//    NSString *s2 = [NSString stringWithFormat:@"%d.caf", fileID+2];
//    StartRecord( (__bridge CFStringRef) s,  (__bridge CFStringRef) s2 );
    
    
}



void AQRecorder::StopRecord()
{
	// end recording
	mIsRunning = false;
	XThrowIfError(AudioQueueStop(mQueue, true), "AudioQueueStop failed");	
	// a codec may update its cookie at the end of an encoding session, so reapply it to the file now
	CopyEncoderCookieToFile();
	if (mFileName1)
	{
		CFRelease(mFileName1);
		mFileName1 = NULL;
	}

    if (mFileName2)
	{
		CFRelease(mFileName2);
		mFileName2 = NULL;
	}

    AudioQueueDispose(mQueue, true);
	AudioFileClose(mRecordFile1);
	AudioFileClose(mRecordFile2);
    
    
}
