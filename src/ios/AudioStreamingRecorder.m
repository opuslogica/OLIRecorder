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
    void *__val = (__bridge void *) (val); \
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
    if (nil == self.queue) { \
      NSLog (@"Queue not configure: %@", msg); \
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
@property (nonatomic, copy) RecordedFileCallback callback;

@property (nonatomic, readwrite) AVAudioSession *session;
@property (nonatomic, readwrite) Boolean isPermitted;
@property (nonatomic, readwrite) Boolean isInterrupted;

@property (nonatomic) AudioQueueRef queue;
@property (nonatomic) AVAudioFormat *queueFormat;
@property (nonatomic) NSDictionary  *queueSettings;
@property (nonatomic) Boolean        queueIsRunning;

// The current file into which audio is being accumulated.
@property (nonatomic) AudioFileID    file;
@property (nonatomic) NSURL         *fileURL;
@property (nonatomic) AVAudioFormat *fileFormat;
@property (nonatomic) NSDictionary  *fileSettings;
@property (nonatomic) SInt64         filePacket;
@property (nonatomic) SInt64         filePacketLimit;

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

- (void) handleQueueBuffer: (AudioQueueBufferRef) buffer
                      time: (const AudioTimeStamp *) time
                     count: (UInt32) count
                      desc: (const AudioStreamPacketDescription *) desc;
@end


//
// Count for instances.  Used with fileIdentifier to ensure that a filename
// won't ever be repeated.
//
static unsigned int instance = 0;

static void audio_queue_handler (void *data,
                                 AudioQueueRef queue,
                                 AudioQueueBufferRef buffer,
                                 const AudioTimeStamp *time,
                                 UInt32 count,
                                 const AudioStreamPacketDescription *desc) {
  AudioStreamingRecorder *self = (__bridge AudioStreamingRecorder *) data;
  
  // Back into AudioStreamRecorder
  [self handleQueueBuffer:buffer
                     time: time
                    count: count
                     desc: desc];
}

#if 0
block: ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
  buffer.frameLength = 4096;
  
  NSError *error = nil;
  
  // The date, right now.  Has 'interval' (10 seconds) elapsed?
  NSDate  *date  = [NSDate date];
  
  // Allocate a file if we don't have one.  We do this lazily which helps
  // to ensure that we have a file when we actually need one
  AbortOnNull(self.file, @"No file");
  //[self configureFileIfNeeded];
  
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
                            format: nodeFormat];
#endif


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

- (void) reportStatsOfLeftOverAudioFiles {
    for (NSURL *filename in [AudioStreamingRecorder arrayOfLeftOverAudioFiles])
      [self reportFileStats: filename.path message: @"All Stats"];
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

- (void) reportFileStats: (NSString *) path
                 message: (NSString *) msg {
  NSError *error = nil;
  NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath: path error: &error];
  AbortOnError(error, msg);
  
  NSLog (@"%@: File Size: %8llu @ %@", msg, attributes.fileSize, path.lastPathComponent);
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

    self.session = nil;
    
    self.enableOutput = NO;
    
    self.file    = nil;
    
    self.fileIdentifier = [NSDate date];
    self.fileLocation   = [AudioStreamingRecorder documentsDirectory];

    [self fileUpdateSessionCount: YES];
    [self fileUpdateBlockCount: YES];
    
    self.callbackQueue =
      dispatch_get_global_queue (AUDIO_DISPATCH_QUEUE_PRIORITY_DEFAULT,
                                 AUDIO_DISPATCH_QUEUE_FLAGS);
    
    self.meterCallback = nil;

  }
  return self;
}

///
/// Produce a Steady-Stream of AudioFile URLS
///
#pragma mark - Audio File URL Management

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

- (void) cookieToFile {
  UInt32 size;
  OSStatus status = noErr;
  
  // Determine the size of the cookie
  status = AudioQueueGetPropertySize (self.queue, kAudioQueueProperty_MagicCookie,
                                      &size);
  
  // It may be the case that the AudioQueue wants nothing to do with cookies.
  // Alright, we won't push it, happily mind you.
  if (0 == size || noErr != status) return;
  
  // Get some memory for the cookie
  char cookie [size];
  UInt32 eatsCookies = false;
  
  status = AudioQueueGetProperty(self.queue, kAudioQueueProperty_MagicCookie,
                                 cookie, &size);
  AbortOnStatus(status, @"Missed queue cookie get");
  
  // Determine if the file can handle cookies.
  status = AudioFileGetPropertyInfo(self.file, kAudioFilePropertyMagicCookieData,
                                    NULL, &eatsCookies);
  
  // Skip the cookie
  if (0 == eatsCookies || noErr != status) return;
  
  status = AudioFileSetProperty(self.file, kAudioFilePropertyMagicCookieData,
                                size, cookie);
  AbortOnStatus(status, @"missed file cookie set");
}

//
//
//
- (void) configureFile {
  OSStatus status = noErr;
  
  NSAssert (nil == self.file, @"Called configureFile w/a file?!");

  // Update the block count for the NEXT invocation.
  [self fileUpdateBlockCount: NO];

  // Move to the next file but with an updated 'block' count.
  self.fileURL = [self fileURLForAudioData: AUDIO_FILE_EXTENSION];
  
  // Create the actual AudioFileID
  status = AudioFileCreateWithURL ((__bridge CFURLRef)(self.fileURL),
                                   kAudioFileAAC_ADTSType,
                                   self.fileFormat.streamDescription,
                                   kAudioFileFlags_EraseFile,
                                   &_file);
  AbortOnStatus(status, @"AVAudioFile initForWriting");

  // Encoder Cookie
  [self cookieToFile];
}

//
//
//
- (void) configureFileIfNeeded { if (nil == self.file) [self configureFile]; }

//
// CAREFUL - Next queue is moving on.  Better have the next file open, ready.
//
- (void) announceFile {
  if (nil != self.file) {

    NSLog (@"Wrote Audio File: %@", self.fileURL.lastPathComponent);

    // Copy Encoder cookie
    [self cookieToFile];
    
    // Copy Encoder cookie again
    [self cookieToFile];
    
    AudioFileClose(self.file);
    
    if (self.callback) {
      
      // Preserve the fileURL and callback.  We can't just reference them
      // directly in the dispatch_async because the URL may have moved on to
      // other values, like the next fileURL

      NSURL *url = self.fileURL;
      RecordedFileCallback callback = self.callback;
      
      dispatch_async (self.callbackQueue, ^{
        callback (0, 0, url);
      });
    }
    
    // To be compatible with exisiting 'configureFile'...
    self.file = nil;
    self.fileURL = nil;
    self.filePacket = 0;
    [self configureFile];
  }
}

//
//
//
- (void) configureWithCallback: (RecordedFileCallback) callback {
  NSError *error  = nil;
  
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
  
  // We request permission to record.  The very first time the app is launch the
  // User will be prompted to allow recording and then the below callback will
  // be invoked.  After that very first time, the callback is simply invoked
  // immediately.

  [self.session requestRecordPermission:^(BOOL granted) {
    UInt32 size;
    OSStatus status;
    NSLog (@"RecordPermission: %@", (granted ? @"Granted" : @"Denied"));
    
    // Skip out if permission has not been granted.
    if (!granted) return;

    //
    // Configure the Audio Queue
    //

    // The Audio Queue will use MPEG4AAC,
    self.queueSettings = @{ AVFormatIDKey                 : @(kAudioFormatMPEG4AAC),
                            AVSampleRateKey               : @(AUDIO_HW_SAMPLE_RATE),
                            AVNumberOfChannelsKey         : @(AUDIO_FILE_CHANNELS),
                            AVEncoderBitRatePerChannelKey : @(16),
                            //AVEncoderAudioQualityKey      : @(AVAudioQualityMedium)
                            };

    // The AVAudioFormat is based on the queueSettings and provides a
    // StreamBasicDescription for the queue
    self.queueFormat = [[AVAudioFormat alloc] initWithSettings: self.fileSettings];

    // The AudioQueue is defined from the description and provided with
    // a callback handler.
    status = AudioQueueNewInput(self.queueFormat.streamDescription,
                                audio_queue_handler,
                                (__bridge void *)(self),
                                NULL, 0,
                                0, &_queue);
    
    // The AudioQueue, just created, might have augmented the streamDescription
    // so we'll get the definitive one.
    {
      AudioStreamBasicDescription description = { 0 };
      size = sizeof (description);
      
      status = AudioQueueGetProperty(self.queue,
                                     kAudioQueueProperty_StreamDescription,
                                     &description,
                                     &size);
      
      self.queueFormat =
        [[AVAudioFormat alloc] initWithStreamDescription: &description];
    }
    
    // The fileFormat will be identical to the queueFormat.  We are recording
    // compressed MPEG4AAC via the queue; lucky us that the queue does the
    // conversion from whatever native format (LPCM) is used on the microphone.
    self.fileFormat = self.queueFormat;

    // Actually create an audio file.
    [self configureFileIfNeeded];

    // Allocate and Enqueue Buffers

    
    self.isPermitted = granted;
 
    self.enableOutput = NO;
  }];
}

- (void) handleQueueBuffer: (AudioQueueBufferRef) buffer
                      time: (const AudioTimeStamp *) time
                     count: (UInt32) count
                      desc: (const AudioStreamPacketDescription *) desc {
  
  OSStatus status = noErr;
  
  if (count > 0) {

    // Write the buffer to file starting from the current packet
    status = AudioFileWritePackets (self.file, false,
                                    buffer->mAudioDataByteSize,
                                    desc,
                                    self.filePacket,
                                    &count,
                                    buffer->mAudioData);

    // count is updated; advance the filePacket
    self.filePacket += count;
  }
  
  if (self.queueIsRunning) {
    status = AudioQueueEnqueueBuffer(self.queue, buffer, 0, NULL);
    AbortOnStatus(status, @"Missed (re)enqueue buffer");
  }
  
  if (self.filePacket >= self.filePacketLimit) {
    [self announceFile];
  }
}

///
/// Pause, Record and Reset
///
#pragma mark - Audio isRecording, Pause, Record and Reset

//
//
//
- (void) pause {
  WarnIfNotConfigured (@"Pause", YES);
  
  if (self.queueIsRunning) {
    // No longer running; race condition right here.
    self.queueIsRunning = false;

    // Stop the queue immediately.
    AudioQueueStop(self.queue, true);
    
    // Write an encoder cookie to file.
    void;
    
    // Dispose of the queue?  NO.
    
    // Announce the file
    [self announceFile];
  }
}

//
//
//
- (void) record {
  WarnIfNotConfigured (@"Record", YES);

  if (!self.queueIsRunning) {
    // Start running; race condition right here.
    self.queueIsRunning = true;
    
    [self configureFileIfNeeded];
    AudioQueueStart(self.queue, NULL);
  }
}

//
//
//
- (void) reset {
  WarnIfNotConfigured(@"Reset", YES);
  
  // Update our session count.
  [self fileUpdateSessionCount: NO];

  // If recording, our 'pause' will invoke announceFile.
  [self pause];
  
  // Stop and Reset the AVAudio Engine
  void;
  //  [self.engine stop];
  //  [self.engine reset];
}


///
/// Input Gain and Level (what is going to file)
///
#pragma mark - Audio Input Gain and Level
#if 0
// It seems we can't actually change the input gain.  Don't freaking ask.
- (float) inputGain {
  return (nil == self.engine ? 0.0 : self.engine.inputNode.volume);
}

- (void) setInputGain:(float) inputGain {
  if (nil != self.engine) {
    self.engine.inputNode.volume = inputGain;
  }
}
#endif

///
/// Audio Input Pan
///
#pragma mark - Audio Input Pan
#if 0
- (float) inputPan {
  return (nil == self.engine ? 0.0 : self.environmentNode.pan);
}

- (void) setInputPan:(float)inputPan {
  if (nil != self.engine)
    self.environmentNode.pan = MAX (-1.0, MIN (+1.0, inputPan));
}
#endif

///
/// Audio Output Gain
///
#pragma mark - Audio Output Gain
#if 0
// It seems the outputGain is the inputNode's volume.  Don't freaking ask.  I
// thought the mainMixerNode had a volume to adjust...
- (float) outputGain {
  return (nil == self.engine ? -1.0 : self.engine.mainMixerNode.volume);
}

- (void) setOutputGain:(float) outputGain {
  if (nil != self.engine)
    self.engine.mainMixerNode.volume = (self.enableOutput ? outputGain : 0.0);
  
  // NSLog (@"OutputGain (%d), %f => %f", self.enableOutput, outputGain, self.engine.mainMixerNode.volume);
}
#endif

//
// setEnableOutput
//
// When enabled will connect the mainMixerNode to the outputNode; when disabled
// will disconnect these two.
//
#if 0
- (void) setEnableOutput:(Boolean)enableOutput {
  if (nil == self.engine) {
    _enableOutput = NO;
    return;
  }
  
  _enableOutput = enableOutput;
  if (!enableOutput)
    self.engine.mainMixerNode.volume = 0.0;
}
#endif


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

    // Apparent range is {0.0, 1.0}
    
    switch (channel) {
      case 0: self.recordedLevelLeft  = meter; break;
      case 1: self.recordedLevelRight = meter; break;
      default: break;
    }
    
    // NSLog (@"Meter (%d): p:%f, a:%f", channel, meter.mPeakPower, meter.mAveragePower);
  }
  
  if (nil != self.meterCallback)
    self.meterCallback (self.recordedLevelLeft, self.recordedLevelRight);
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
