//
//  AudioStreamingRecorder.h
//  AudioStreaming
//
//  Created by Ed Gamble on 12/5/14.
//  Copyright (c) 2014 Opus Logica Inc. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>

// Don't touch this
#define FOR_AAC 1
#define FOR_M4A 2
#define FOR_MP3 3

// Touch this
#if ! defined (USE_FORMAT)
#define USE_FORMAT FOR_AAC
#endif

// AUDIO_FILE_EXTENSION
//
// The extension to use when creating audio files

// AUDIO_FILE_TYPE
//
// For lower-level file protocols, the file type is NOT derived from the file
// extension.  So we are forced to set it and hope, desperately, that we got
// lucky and choose something consistent with the extension.  Or maybe we should
// just challenge audio file processor by putting a '.scm' or '.sh' or '.o'
// extension?

// AUDIO_FILE_FORMAT
//
// Call it a guess; call it a chimp's random search

#if FOR_AAC == USE_FORMAT
#define AUDIO_FILE_EXTENSION  @"aac"
#define AUDIO_FILE_TYPE kAudioFileAAC_ADTSType
#define AUDIO_FILE_FORMAT kAudioFormatMPEG4AAC

#elif FOR_M4A == USE_FORMAT
#define AUDIO_FILE_EXTENSION  @"m4a"
#define AUDIO_FILE_TYPE kAudioFileM4AType
#define AUDIO_FILE_FORMAT kAudioFormatMPEG4AAC // ??

#elif FOR_MP3 == USE_FORMAT
#define AUDIO_FILE_EXTENSION  @"mp3"
#define AUDIO_FILE_TYPE kAudioFileMP3Type
#define AUDIO_FILE_FORMAT kAudioFormatMPEGLayer3

#else
#error "Unknown format"
#endif

// The number of channels written to file
#define AUDIO_FILE_CHANNELS 2

// Do we tell the ExtAudioFile to provide a clientFormat hint?  If we do,
// we fail.  Go figure.
#define AUDIO_FILE_ANNOUNCE_CLIENT_FORMAT 0

#define USE_INTERLEAVED_CONVERT 0 // 2 == AUDIO_FILE_CHANNELS
//
#define AUDIO_MINIMUM_RECORDING_INTERVAL 2.5 // seconds

#if ! defined (AUDIO_DISPATCH_QUEUE_PRIORITY_DEFAULT)
#define AUDIO_DISPATCH_QUEUE_PRIORITY_DEFAULT DISPATCH_QUEUE_PRIORITY_DEFAULT
#endif

#if ! defined (AUDIO_DISPATCH_QUEUE_FLAGS)
#define AUDIO_DISPATCH_QUEUE_FLAGS 0
#endif

#define AUDIO_FILE_DELAY_QUEUE_SIZE 2

//
//
//
@interface AudioStreamingRecorder : NSObject

// YES if granted permission; NO otherwise.  Nothing happens unless permission
// has been granted.
@property (nonatomic, readonly) Boolean isPermitted;

// YES if recording; NO otherwise.
@property (nonatomic, readonly) Boolean isRecording;

// YES if interrupted (by a phone call for example); NO otherwise.
@property (nonatomic, readonly) Boolean isInterrupted;

// Time interval between audio files
@property (nonatomic, readonly) NSTimeInterval recordingInterval;

// Gain for the microphone.  Set/Get the gain in {0.0, 1.0}.  If 'self' has not
// been configured, then -1.0 is returned!
@property (nonatomic, readwrite) float inputGain;

@property (nonatomic, readwrite) float inputPan;

@property (nonatomic) AudioQueueLevelMeterState recordedLevelLeft;
@property (nonatomic) AudioQueueLevelMeterState recordedLevelRight;

// Gain for the speaker.  See above.
// Not implemented... requires mixerNode...
@property (nonatomic, readwrite) float outputGain;

@property (nonatomic, readwrite) Boolean enableOutput;

// Designated initializer for AudioStreamingRecorder.  This won't actually
// start the stream - you'll need 'configureWithCallback:' and then 'record' to
// get actual audio flowing.
- (AudioStreamingRecorder *) initWithRecordingInterval: (NSTimeInterval) interval;

// Start recording.  If a 'recording session' is not in progress start one and
// begin actually recording; if paused, resume.
- (void) record;

// If recording, pause.
- (void) pause;

// If a 'recording session' is in progress, end it.  Using 'record' will start
// another session.  NOTE: Our 'recording session' is distinch from an
// AVAudioSession.
- (void) reset;

// When a file has been recorded, every 'recordingInterval' seconds, a callback
// with this signature will be invoked.
typedef void (^RecordedFileCallback) (unsigned int session,
                                      unsigned int block,
                                      NSURL *file);

// Request permission to RecordAndPlay (using 'play' allows for monitoring) and
// configure/create the AVAudioEngine that connects inputs to outputs (file and
// speaker if monitoring).
- (void) configureWithCallback: (RecordedFileCallback) callback;

// Queue to use for the callback.  A default queue is created, based on
// the above declarations for AUDIO_DISPATCH_QUEUE_*.
@property (nonatomic, readwrite) dispatch_queue_t callbackQueue;

// Learn about changes
typedef void (^RouteChangeCallback) (NSString *placeholder);

@property (nonatomic, copy) RouteChangeCallback routeCallback;

// Learn about meter levels
typedef void (^MeterCallback) (AudioQueueLevelMeterState leftMeter,
                               AudioQueueLevelMeterState rightMeter);

@property (nonatomic, copy) MeterCallback meterCallback;

//
// Class Methods
//

//
// Expunge (aka 'rm') the file - it is 'left over' because it is assumed that
// the file has already been handled/downlinked.
+ (void) expungeLeftOverAudioFile: (NSString *) fileURLAsString;

//
// Expunge any and all left over audio files.  Any audio files remaining in
// the App's folder are considered 'left over' - because the expectation is
// that the RecordedFileCallback will delete audio files have they have been
// delivered and then processed.  However, in fact, some users may leave all
// the audio files on the device and (re)process them after the fact.
//
+ (void) expungeLeftOverAudioFiles;

//
// Returns an array of NSURL; one for each 'left over' audio file (see above).
//
+ (NSArray *) arrayOfLeftOverAudioFiles;

//
// Encode various parameters into a filename
//
+ (NSString *) createAudioFilename: (unsigned int)  instance
                           seconds: (unsigned long) seconds
                           session: (unsigned int)  session
                             block: (unsigned int)  block
                         extension: (NSString *) extension;

//
// Extract various parameters encoded into the filename
//
+ (Boolean) parseAudioFilename: (NSURL *) file
                      instance: (unsigned int  *) instance
                       seconds: (unsigned long *) seconds
                       session: (unsigned int  *) session
                         block: (unsigned int  *) block
                     extension: (NSString **) extension;

- (void) reportStatsOfLeftOverAudioFiles;

@end

//
// Perhaps useful
//
@interface NSURLRequest (NSURLRequestPost)
+ (NSURLRequest *) requestPostWithURL: (NSURL *) baseURL
                           parameters: (NSDictionary *) parameters
                          cachePolicy: (NSURLRequestCachePolicy) cachePolicy
                      timeoutInterval: (NSTimeInterval) timeoutInterval;
@end

