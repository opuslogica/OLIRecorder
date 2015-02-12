//
//  AudioStreamingRecorder.m
//  AudioStreaming
//
//  Created by Ed Gamble on 12/5/14.
//  Copyright (c) 2014 Opus Logica Inc. All rights reserved.
//
#import "AudioStreamingRecorder.h"
#import <Accelerate/Accelerate.h>

//
// THESE ARE ALL THE WRONG THING TO DO
//
#define AbortOnError( error, desc ) \
  do {                              \
    if (nil != error) {             \
      NSLog (@"Error: %@", desc);    \
      abort ();                     \
    }                               \
  } while (0)

#define AbortOnStatus( status, desc ) \
  do {                                \
    OSStatus __status = (status);     \
    if (__status) {                   \
      NSLog (@"Status (%d): %@", ((int) __status), desc);    \
      abort ();                       \
    }                                 \
  } while (0)

#define AbortOnNull( val, desc )      \
  do {                                \
    void *__val = (val);              \
    if (NULL == __val) {              \
      NSLog (@"NULL value: %@", desc);\
      abort ();                       \
    }                                 \
  } while (0)


//
// THERE ARE NOT THE WRONG THING
//
#define SkipIfNotPermitted( msg ) \
  do { \
    if (!self.isPermitted) { \
      NSLog (@"Audio not permitted: %@", msg); \
      return; \
    } \
  } while (0)

#define WarnIfNotConfigured( msg, ret ) \
  do { \
    SkipIfNotPermitted (msg); \
    if (nil == self.engine) { \
      NSLog (@"Engine not configure: %@", msg); \
      if (ret) return; \
    } \
  } while (0)


// AAC, 10 seconds ~ 150k bytes
// 44k * 10 * 2 * 2 = 1.6M == 150k

// The following name is poor.
//
// This duration is short; the longest is .93 (translated, somehow, from
// '4096' somethings/fames/packets/somethings).  Either way it doesn't appear
// to relate to an 'Audio Queue Buffer Duration'...
#define AUDIO_BUFFER_DURATION     0.005

// Desired.
#define AUDIO_HW_SAMPLE_RATE      44100.0


// AAC, PCM, IMA4, ULAW, ILBC

// Results of some early testing.  Don't trust this now.
// (YES) caf  :: kAudioFileCAFType
// (NO)  aiff :: kAudioFileAIFFType
// (NO)  aifc :: kAudioFileAIFCType
// (NO)  aac  :: kAudioFileAAC_ADTSType
// (NO)  mp3  :: kAudioFileMP3Type

//
// Forward Declarations
//
@interface AudioStreamingRecorder ()
@property (nonatomic, readwrite) AVAudioSession *session;
@property (nonatomic, readwrite) AVAudioEngine  *engine;

@property (nonatomic, copy) RecordedFileCallback callback;

@property (nonatomic, readwrite) Boolean isPermitted;
@property (nonatomic, readwrite) Boolean isInterrupted;

@property (nonatomic, readwrite) NSTimeInterval recordingInterval;

@property (nonatomic, readwrite) AVAudioEnvironmentNode *environmentNode;

// The current file into which audio is being accumulated.
@property (nonatomic) AVAudioFile *file;

// The time at which the current file's audio recording expires.  Once expired
// the file is closed and passed to the RecordedFileCallback.
@property (nonatomic) NSDate *fileExpiration;

// URL/Folder where the audio filees are stored
@property (nonatomic) NSURL  *fileLocation;

// Unique-ish identifer for a file.  We never want to worry about pre-existing
// files in our fileLocation so we encode the 'init time' into the file name.
// Even that isn't enough if the user creates two or more AudioStreamingRecorders
// back to back as they might get the same timestamp.  See 'instance' below
@property (nonatomic) NSDate *fileIdentifier;

//
@property (nonatomic) unsigned int fileSessionCount;
@property (nonatomic) unsigned int fileBlockCount;

// Audio-Specific Settings.
@property (nonatomic) NSDictionary *fileSettings;

@end


//
// Count for instances.  Used with fileIdentifier to ensure that a filename
// won't ever be repeated.
//
static unsigned int instance = 0;

//
// AudioStreamingRecorder
//
@implementation AudioStreamingRecorder
@dynamic isRecording;
@dynamic inputGain;
@dynamic outputGain;
@dynamic inputPan;

//
// Officially sanctioned place for App files - audio files in our case.
//
+ (NSURL *) documentsDirectory {
  return [[[NSFileManager defaultManager] URLsForDirectory: NSDocumentDirectory
                                                 inDomains: NSUserDomainMask] lastObject];
}

+ (void) expungeLeftOverAudioFile: (NSString *) fileURLAsString {
  [[NSFileManager defaultManager] removeItemAtPath: fileURLAsString
                                             error: NULL];
}

//
//
//
+ (void) expungeLeftOverAudioFiles {
  [[self arrayOfLeftOverAudioFiles] enumerateObjectsUsingBlock: ^ (NSURL *obj, NSUInteger idx, BOOL *stop) {
    [[NSFileManager defaultManager] removeItemAtURL: obj error: NULL];
  }];
}

//
//
//
+ (NSArray *) arrayOfLeftOverAudioFiles {
  NSError *error = NULL;
  NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL: [self documentsDirectory]
                                                 includingPropertiesForKeys: @[]
                                                                    options: 0
                                                                      error: &error];
  AbortOnError(error, @"could get left-over audio files");
  return files;
}

//
// Encode various parameters into a filename
//
+ (NSString *) createAudioFilename: (unsigned int)  instance
                           seconds: (unsigned long) seconds
                           session: (unsigned int)  session
                             block: (unsigned int)  block
                         extension: (NSString *) extension {
  return [NSString stringWithFormat: @"audio-%ld-%d-%05d-%05d.%@",
          seconds, instance, session, block, extension];
}

//
// Extract various parameters encoded into the filename
//
+ (Boolean) parseAudioFilename: (NSURL *) file
                      instance: (unsigned int  *) instance
                       seconds: (unsigned long *) seconds
                       session: (unsigned int  *) session
                         block: (unsigned int  *) block
                     extension: (NSString **) extension {
  NSString *filename = file.lastPathComponent;
  char ext[128];
  
  int matched = sscanf([filename  fileSystemRepresentation], "audio-%ld-%d-%d-%d.%s",
                       seconds, instance, session, block, ext);

  if (NULL != extension)
    *extension = [NSString stringWithUTF8String: ext];

  return 5 == matched;
}


//
//
//
- (AudioStreamingRecorder *) initWithRecordingInterval: (NSTimeInterval) interval {
  
  if (self = [super init])
  {
    instance++;
    
    self.isPermitted = NO;
    self.isInterrupted = NO;

    self.recordingInterval = MAX (interval, AUDIO_MINIMUM_RECORDING_INTERVAL);

    self.session = nil;
    self.engine  = nil;
    
    self.enableOutput = NO;
    
    self.file    = nil;
    
    self.fileIdentifier = [NSDate date];
    self.fileLocation  = [AudioStreamingRecorder documentsDirectory];
    
    [self fileUpdateSessionCount: YES];
    [self fileUpdateBlockCount: YES];
    
    self.callbackQueue =
      dispatch_get_global_queue (AUDIO_DISPATCH_QUEUE_PRIORITY_DEFAULT,
                                 AUDIO_DISPATCH_QUEUE_FLAGS);

  }
  return self;
}

- (void) fileUpdateSessionCount: (Boolean) reset {
  if (reset) self.fileSessionCount = 0;
  else self.fileSessionCount++;
  [self fileUpdateBlockCount: YES];
}

- (void) fileUpdateBlockCount: (Boolean) reset {
  if (reset) self.fileBlockCount = -1;   // Incremented before use.
  else self.fileBlockCount++;
}

- (NSURL *) fileURLForAudioData: (NSString *) extension {
  return [NSURL URLWithString:
          [AudioStreamingRecorder createAudioFilename: 0
                                              seconds: lround (self.fileIdentifier.timeIntervalSinceReferenceDate)
                                              session: self.fileSessionCount
                                                block: self.fileBlockCount
                                            extension: extension]
                relativeToURL: _fileLocation];
}

///
/// Audio File Configuration and Announcement
///
#pragma mark - Audio File Configuration and Announcement

- (void) configureFile {
  NSError *error = nil;
  
  NSAssert (nil == self.file, @"Called configureFile w/o a file?!");

  // Update the block count for the NEXT invocation.
  [self fileUpdateBlockCount: NO];

  // Move to the next file but with an updated 'block' count.
  self.file = [[AVAudioFile alloc] initForWriting: [self fileURLForAudioData: AUDIO_FILE_EXTENSION]
                                         settings: self.fileSettings
                                            error: &error];
  AbortOnNull(((__bridge void *)self.file), @"AVAudioFile initForWriting");
  
  // This new file will expire in self.recordingInterval seconds from now.
  self.fileExpiration = [[NSDate date] dateByAddingTimeInterval: 0.95 * self.recordingInterval];
}

- (void) configureFileIfNeeded { if (nil == self.file) [self configureFile]; }

- (void) announceFile {
  if (nil != self.file) {
    // Immediately invoke the callback.  We'll dispatch to some other
    // thread - the file isn't going any where and, in fact, is the
    // responsibility of the callback to discard it.
    if (self.callback) {
      
      // These MUST be cached... otherwise they will be lost by the time
      // the asynchronous callback is invoked.
      RecordedFileCallback callback = self.callback;
      AVAudioFile *lastFile = self.file;
      unsigned int lastBlockCount   = self.fileBlockCount;
      unsigned int lastSessionCount = self.fileSessionCount;

      dispatch_async (self.callbackQueue, ^{
        callback (lastSessionCount, lastBlockCount, lastFile.url);
      });
    }
    NSLog (@"Wrote Audio File: (%10lld): %@",
           self.file.length,
           self.file.url.lastPathComponent);
    
    // Clear out the file; setup for our 'lazy' alloc and init.
    self.file = nil;
    self.fileExpiration = nil;
  }
}

//
//
//
- (void) configureWithCallback: (RecordedFileCallback) callback {
  NSError *error = nil;
  
  self.callback = callback;
  self.isPermitted = NO;
  
  //
  // (Re)Configure the AVAudioSession
  //
  self.session = [AVAudioSession sharedInstance];
  
  [self.session setCategory: AVAudioSessionCategoryPlayAndRecord error: &error];
  AbortOnError(error, @"missed audio category");
  
  [self.session setPreferredIOBufferDuration: AUDIO_BUFFER_DURATION error: &error];
  AbortOnError(error, @"missed IOBufferDuration");
  
  [self.session setPreferredSampleRate: AUDIO_HW_SAMPLE_RATE error: &error];
  AbortOnError(error, @"missed SampleRate");
  
  // add interruption handler
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector (handleInterruption:)
                                               name: AVAudioSessionInterruptionNotification
                                             object: self.session];
  
  // We don't do anything special in the route change notification
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector (handleRouteChange:)
                                               name: AVAudioSessionRouteChangeNotification
                                             object: self.session];
  
  // Here the callback is called immediately after the first request.  If the
  // first request, then their will be an 'alert' and a callback - that might
  // be too late.
  [self.session requestRecordPermission:^(BOOL granted) {
    NSLog (@"RecordPermission: %@", (granted ? @"Granted" : @"Denied"));
    
    // Skip out if permission has not been granted.
    if (!granted) return;

    //
    // Configure the AVAudioEngine
    //
    self.engine = [[AVAudioEngine alloc] init];
    self.fileSettings = @{ AVFormatIDKey                 : @(kAudioFormatMPEG4AAC),
                           AVSampleRateKey               : @(44100.0),
                           AVNumberOfChannelsKey         : @(AUDIO_FILE_CHANNELS),
                           AVEncoderBitRatePerChannelKey : @(16),
                           //AVEncoderAudioQualityKey      : @(AVAudioQualityMedium)
                           };
    
    // Define the format for the two busses: input -> mixer, mixer -> output.
    // The number of channels below must match, is seems, with the above
    // fileSettings
    AVAudioFormat *stereoFormat =
      [[AVAudioFormat alloc] initStandardFormatWithSampleRate: 44100.0
                                                     channels: 2];

    AVAudioFormat *monoFormat =
    [[AVAudioFormat alloc] initStandardFormatWithSampleRate: 44100.0
                                                   channels: 1];
    
    AVAudioFormat *nodeFormat = (1 == AUDIO_NODE_CHANNELS
                                 ? monoFormat
                                 : stereoFormat);
    
    // To mix stereo we need an EnvironmentNode (environment because it models
    // the position of a listener.
    self.environmentNode = [[AVAudioEnvironmentNode alloc] init];

    [self.engine attachNode: self.environmentNode];
    
    // Apparently the mainMixerNode is connected to the outputNode by default
    // but only if the inputNode is connected to the mainMixerNode.
    
    // We are going to connect inputNode -> envNode -> mainMixerNode ->
    // outputNode.  We'll do it explicitly.  Then we will enable/disable
    // monitoring just by changing the volume of the main mixer node.  We should
    // get stereo panning of the inputNode too.

    [self.engine connect: self.engine.inputNode
                      to: self.environmentNode
                  format: monoFormat];
    
    // The mainMixer node is tapped to record audio to file.
    [self.engine connect: self.environmentNode
                      to: self.engine.mainMixerNode
                  format: nodeFormat];
    
    // The output node is used for monitoring the recorded audio.
    [self.engine connect: self.engine.mainMixerNode
                      to: self.engine.outputNode
                  format: nodeFormat];

    // This is the default.  Ranges from {-1.0, +1.0}
    self.engine.inputNode.pan = 0.0;
    
    // Don't overdrive the input; using 1.0 seems to.
    self.engine.inputNode.volume = 0.8;
    
    // Today, we are getting ~16384 frames per block callback. (4 * 4096)
    [self.engine.mainMixerNode
     installTapOnBus: 0
     
     // This number is ignored... and an Apple bug?
     bufferSize: 4096 * 16

     // Use of 'nil' is quasi-required - based on the documentation - because
     // the mainMixerNode is attached to the outputNode and thus the format
     // of the mainMixerNode is already determined.
     format: nil
     
     // This 'handler' needs to allocate and initialze an AVAudioFile and to
     // write buffer data to that file.  If this handler is too slow, we
     // perhaps might not actually know but should increase the 'bufferSize'
     // to allow for a greater time between invocation of this handler.  The
     // latter only solves a 'too slow' problem if it is the allocation and
     // initialization of the AVAudioFile that is slow.
     block: ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
       NSError *error = nil;
       
       // The date, right now.  Has 'interval' (10 seconds) elapsed?
       NSDate  *date  = [NSDate date];
       
       // Allocate a file if we don't have one.  We do this lazily which helps
       // to ensure that we have a file when we actually need one
       [self configureFileIfNeeded];
       
       // The AVAudioPCMBuffer is 'specially designed' to easily write to a file
       // and, as part of the write, be converted to the file's format.  The
       // writeFromBuffer will open if needed and appends by default.
       [self.file writeFromBuffer: buffer error: &error];
       AbortOnError(error, @"File writeFromBuffer");
       
       // Check if 'now' is beyond the pre-computed fileExpiration.  If so, or
       // if we don't have a fileExperation, announce the file.
       if (nil == self.fileExpiration ||
           [date timeIntervalSinceDate: self.fileExpiration] > 0) {
         [self announceFile];
       }
       
       [self updateMeterOfRecordedLevel: buffer
                                 format: [self.engine.inputNode inputFormatForBus: 0]];
     }];
    
    self.isPermitted = granted;
 
    self.enableOutput = NO;
  }];
}


///
/// Input Gain and Level (what is going to file)
///
#pragma mark - Audio Input Gain and Level

// It seems we can't actually change the input gain.  Don't freaking ask.
- (float) inputGain {
  return (nil == self.engine ? 0.0 : self.engine.inputNode.volume);
}

- (void) setInputGain:(float) inputGain {
  if (nil != self.engine) {
    self.engine.inputNode.volume = inputGain;
  }
}

///
/// Audio Input Pan
///
#pragma mark - Audio Input Pan

- (float) inputPan {
  return (nil == self.engine ? 0.0 : self.engine.inputNode.pan);
}

- (void) setInputPan:(float)inputPan {
  if (nil != self.engine)
    self.engine.inputNode.pan = MAX (-1.0, MIN (+1.0, inputPan));
}

///
/// Audio Output Gain
///
#pragma mark - Audio Output Gain

// It seems the outputGain is the inputNode's volume.  Don't freaking ask.  I
// thought the mainMixerNode had a volume to adjust...
- (float) outputGain {
  return (nil == self.engine ? 0.0 : self.engine.mainMixerNode.volume);
}

- (void) setOutputGain:(float) outputGain {
  if (nil != self.engine)
    self.engine.mainMixerNode.volume = (self.enableOutput ? outputGain : 0.0);
}

//
// setEnableOutput
//
// When enabled will connect the mainMixerNode to the outputNode; when disabled
// will disconnect these two.
//
- (void) setEnableOutput:(Boolean)enableOutput {
  if (nil == self.engine) {
    _enableOutput = NO;
    return;
  }

  _enableOutput = enableOutput;
  if (!enableOutput)
    self.engine.mainMixerNode.volume = 0.0;
}

///
/// Pause, Record and Reset
///
#pragma mark - Audio isRecording, Pause, Record and Reset

- (Boolean) isRecording {
  return self.engine.running;
}

- (void) pause {
  WarnIfNotConfigured (@"Pause", YES);
  
  if (self.isRecording) {
    
    // We'll pause which prevents the 'tap' from being called, it seems.
    [self.engine pause];

    // We'll reset which, presumably, drops any partial 'tap' buffer.  We'd
    // prefer not to loose that but it would be worse if the buffer hung around
    // until we restarted.
    [self.engine reset];
    
    // Now, close off the current file.
    [self announceFile];
  }
}
   
- (void) record {
  WarnIfNotConfigured (@"Record", YES);

  if (!self.isRecording) {
    NSError *error;
    [self.engine startAndReturnError: &error];
    AbortOnError(error, @"record");
  }
}

- (void) reset {
  WarnIfNotConfigured(@"Reset", YES);

  // If recording, our 'pause' will invoke announceFile.
  [self pause];
  
  // Stop and Reset the AVAudio Engine
  [self.engine stop];
  [self.engine reset];
  
  // Update our session count.
  [self fileUpdateSessionCount: NO];
}

///
/// Audio Session Notifications
///
#pragma mark - Audio Session Notifications

- (void)handleInterruption:(NSNotification *)notification
{
  AVAudioSessionInterruptionType theInterruptionType =
    (AVAudioSessionInterruptionType) [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
  
  NSLog(@"Session interrupted > --- %s ---\n", theInterruptionType == AVAudioSessionInterruptionTypeBegan ? "Begin Interruption" : "End Interruption");
 
  switch (theInterruptionType)
  {
    case AVAudioSessionInterruptionTypeBegan:
      if (self.isInterrupted) {
        NSLog (@"Interrupted while interrupted; this possbility was not accounted for (fully :-)");
        break;
      }

      // Pause, if recording.
      if (self.isRecording)
        [self pause];

      // Mark as isInterrupted if isRecording (not a real interrupt otherwise)
      self.isInterrupted = self.isRecording;
      break;
      
    case AVAudioSessionInterruptionTypeEnded:
      // Resume recording, if interrupted, now that the interruption has ended.
      if (self.isInterrupted)
        [self record];

      self.isInterrupted = NO;
      break;
  }
}

- (void)handleRouteChange:(NSNotification *)notification
{
  UInt8 reasonValue = [[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue];
  
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
      NSLog(@"     Category: %@", [[AVAudioSession sharedInstance] category]);
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
    default:
      NSLog(@"     ReasonUnknown");
  }
  
  NSLog(@"     Description: %@\n\n", self.session.currentRoute);

  if (self.routeCallback) {
    NSMutableArray *iNames = [NSMutableArray array];
    NSMutableArray *oNames = [NSMutableArray array];
    
    [self.session.currentRoute.inputs enumerateObjectsUsingBlock:
     ^(AVAudioSessionPortDescription *obj, NSUInteger idx, BOOL *stop) {
       [iNames addObject: obj.portName];
     }];
    
    [self.session.currentRoute.outputs enumerateObjectsUsingBlock:
     ^(AVAudioSessionPortDescription *obj, NSUInteger idx, BOOL *stop) {
       [oNames addObject: obj.portName];
     }];

    self.routeCallback ([NSString stringWithFormat:@"Route Inputs %lu Outputs %lu",
                         (unsigned long)iNames.count,
                         (unsigned long)oNames.count]);
  }
}

- (void) updateMeterOfRecordedLevel: (AVAudioPCMBuffer *) buffer
                             format: (AVAudioFormat *) format {
  AVAudioFrameCount   frameCount   = buffer.frameLength;
  AVAudioChannelCount channelCount = format.channelCount;
  
  AudioQueueLevelMeterState meter;
  
  float * const *channelData = buffer.floatChannelData;
  
  for (int channel = 0; channel < channelCount; channel++) {
    // Freaking point-to-point-of-pointers-to-N-values documentation.
    //   struct {
    //     float channelOne[number_of_values];
    //     float channelTwo[number_of_values]
    //  } channelData?
    //
    // The following: Maybe?  Probably wrong
    float *data = *channelData + channel * frameCount;
    
    vDSP_rmsqv (data, (vDSP_Stride) 1, &(meter.mAveragePower), (vDSP_Length) frameCount);
    vDSP_maxv  (data, (vDSP_Stride) 1, &(meter.mPeakPower),    (vDSP_Length) frameCount);

    // The level meters should be in dBs and thus need to use log10f() ?
    
    switch (channel) {
      case 0: self.recordedLevelLeft  = meter; break;
      case 1: self.recordedLevelRight = meter; break;
      default: break;
    }
  }
}

#if 0
private func calculateMeterOutputFromAudioPCMBuffer(audioPCMBuffer : AVAudioPCMBuffer, channelCount : AVAudioChannelCount, levelMeterDelegate : ((LTChannelLevels, LTChannelLevels) -> Void)) {
  
  let sampleCount = Int(audioPCMBuffer.frameLength)
  let sampleLength = sampleCount // ceil
  let floatChannelData = audioPCMBuffer.floatChannelData.memory;

  var rms : Float = 0
  var maxSample : Float = 0

  var channelLevelPeak = LTChannelLevels(leftChannel: 0, rightChannel: 0)
  var channelLevelAverage = LTChannelLevels(leftChannel: 0, rightChannel: 0)
  
  vDSP_rmsqv(floatChannelData, vDSP_Stride(1), &rms, vDSP_Length(sampleLength))
  var dbAverage : Float = 20.0 * log10f( rms )
  channelLevelPeak.leftChannel = dbAverage
  
  // If stereo, calculate the second half of the array
  if channelCount > 1 {
    vDSP_rmsqv(floatChannelData + sampleLength, vDSP_Stride(1), &rms, vDSP_Length(sampleLength))
    var dbAverage : Float = 20.0 * log10f( rms )
    
    channelLevelPeak.rightChannel = dbAverage
  }
  
  vDSP_maxv(floatChannelData, vDSP_Stride(1), &maxSample, vDSP_Length(sampleLength))
  var dbPeak : Float = 20.0 * log10f( maxSample )
  channelLevelAverage.leftChannel = dbPeak
  
  // If stereo, calculate the second half of the array
  if channelCount > 1 {
    vDSP_maxv(floatChannelData + sampleLength, vDSP_Stride(1), &maxSample, vDSP_Length(sampleLength))
    var dbPeak : Float = 20.0 * log10f( maxSample )
    
    channelLevelAverage.rightChannel = dbAverage
  }
  
  levelMeterDelegate(channelLevelAverage, channelLevelPeak)
}
#endif
@end


#pragma mark - NSURLRequest Extension
///
///
///
@implementation NSURLRequest (NSURLRequestPost)

+ (NSURLRequest *) requestPostWithURL: (NSURL *) baseURL
                           parameters: (NSDictionary *) parameters
                          cachePolicy: (NSURLRequestCachePolicy) cachePolicy
                      timeoutInterval: (NSTimeInterval) timeoutInterval {

  NSString            *boundary = [NSString stringWithFormat:@"---------------------------%08X%08X",
                                   rand(), rand()];
  NSMutableData       *body     = [NSMutableData data];
  NSMutableURLRequest *request  = [NSMutableURLRequest requestWithURL: baseURL
                                                          cachePolicy: cachePolicy
                                                      timeoutInterval: timeoutInterval];

  [request    setValue: [NSString stringWithFormat: @"multipart/form-data; boundary=%@", boundary]
    forHTTPHeaderField: @"Content-type"];
    
  NSString *str_tail = [NSString stringWithFormat: @"--%@--\r\n", boundary];
  NSString *fmt_body = @"\r\n%@\r\n";
  NSString *fmt_head = [NSString stringWithFormat:
                        @"--%@\r\nContent-Disposition: form-data; name=\"%%@\"\r\n",
                        boundary];
    
  for (NSString *key in parameters) {
    NSObject *val      = [parameters objectForKey: key];
    NSString *str_head = [NSString stringWithFormat: fmt_head,
                          [key stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    [body appendData: [str_head dataUsingEncoding: NSUTF8StringEncoding]];
      
    if (![val isKindOfClass: [NSData class]]) {
      NSString *str_body = [NSString stringWithFormat: fmt_body, val];
      [body appendData: [str_body dataUsingEncoding: NSUTF8StringEncoding]];
    }
    else {
      NSString *str_desc = @"Content-Type: application/octet-stream\r\n\r\n";
      [body appendData: [str_desc dataUsingEncoding: NSUTF8StringEncoding]];
      [body appendData: (NSData *) val];
      [body appendData: [@"\r\n"  dataUsingEncoding: NSUTF8StringEncoding]];
    }
  }
  [body appendData: [str_tail dataUsingEncoding: NSUTF8StringEncoding]];
    
  [request setHTTPBody:   body];
  [request setHTTPMethod: @"POST"];
    
  return request;
}
@end
