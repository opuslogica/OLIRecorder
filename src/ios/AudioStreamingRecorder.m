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
      NSLog (@"Error: %@", desc);   \
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

#define AbortOnNullVoid( val, desc )  \
do {                                  \
void *__val = (void *) (val);         \
if (NULL == __val) {                  \
NSLog (@"NULL (void) value: %@", desc);\
abort ();                             \
}                                     \
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
@property (nonatomic, readwrite) AVAudioFormat  *format;

@property (nonatomic, copy) RecordedFileCallback callback;

@property (nonatomic, readwrite) Boolean isPermitted;
@property (nonatomic, readwrite) Boolean isInterrupted;

@property (nonatomic, readwrite) NSTimeInterval recordingInterval;

@property (nonatomic, readwrite) AVAudioEnvironmentNode *environmentNode;

// The current file into which audio is being accumulated.
@property (nonatomic) ExtAudioFileRef file;

// The time at which the current file's audio recording expires.  Once expired
// the file is closed and passed to the RecordedFileCallback.
@property (nonatomic) NSDate *fileExpiration;

// URL/Folder where the audio filees are stored
@property (nonatomic) NSURL  *fileLocation;

@property (nonatomic) NSURL  *fileURL;

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

@property (nonatomic) NSMutableArray *fileDelayQueue;
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

    self.recordingInterval = MAX (interval, AUDIO_MINIMUM_RECORDING_INTERVAL);

    self.session = nil;
    self.engine  = nil;
    
    self.enableOutput = NO;
    
    self.file    = nil;
    
    self.fileIdentifier = [NSDate date];
    self.fileLocation   = [AudioStreamingRecorder documentsDirectory];
    self.fileURL        = nil;
    self.fileDelayQueue = [NSMutableArray arrayWithCapacity: AUDIO_FILE_DELAY_QUEUE_SIZE];

    [self fileUpdateSessionCount: YES];
    [self fileUpdateBlockCount: YES];
    
    self.callbackQueue =
      dispatch_get_global_queue (AUDIO_DISPATCH_QUEUE_PRIORITY_DEFAULT,
                                 AUDIO_DISPATCH_QUEUE_FLAGS);
    
    self.meterCallback = nil;

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

- (void) fileUpdateFileURL: (NSString *) extension {
  self.fileURL = [NSURL URLWithString:
                  [AudioStreamingRecorder createAudioFilename: 0
                                                      seconds: lround (self.fileIdentifier.timeIntervalSinceReferenceDate)
                                                      session: self.fileSessionCount
                                                        block: self.fileBlockCount
                                                    extension: extension]
                        relativeToURL: _fileLocation];
}

/*
void	WriteCookie (AudioConverterRef converter, AudioFileID outfile)
{
  // grab the cookie from the converter and write it to the file
  UInt32 cookieSize = 0;
  OSStatus err = AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookieSize, NULL);
		// if there is an error here, then the format doesn't have a cookie, so on we go
  if (!err && cookieSize) {
    char* cookie = new char [cookieSize];
    
    err = AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookieSize, cookie);
    XThrowIfError (err, "Get Cookie From AudioConverter");
    
    AudioFileSetProperty (outfile, kAudioFilePropertyMagicCookieData, cookieSize, cookie);
    // even though some formats have cookies, some files don't take them, so we ignore the error
    delete [] cookie;
  }
}
 
 #if 0
 - (void) updateAudioFormat (UInt32 inFormatID) {
 
 
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
 #endif

*/

//
// In some cases it appears that a 'Magic Cookie' is needed at the end of the
// file.  We'll write one here.
//
- (void) writeMagicCookie {
  OSStatus err;
  UInt32 size;
  AudioConverterRef converter;
  
  char cookie [44100];
  
  // Get the converter for this file.  The converter is taking the LPCM input
  // and producing AAC (or whatever, as configured) output.  We'll get the
  // magic cookie from the converter.
  
  size = sizeof (converter);
  err = ExtAudioFileGetProperty (self.file, kExtAudioFileProperty_AudioConverter, &size, &converter);
  AbortOnStatus (err, @"ExtAudioFileGetProperty outFile, kExtAudioFileProperty_AudioConverter");

  // Grab the cookie size.  Note: if we had a maximum size for the cookie we
  // could grab the cookie right here.  As it is, we get the size and allocate
  // some memory for the cookie.
  size = sizeof(cookie);
  //  err = AudioConverterGetProperty (converter, kAudioConverterCompressionMagicCookie, &size, NULL);
  //  AbortOnStatus (err, @"AudioConverterGetProperty converter, kAudioConverterCompressionMagicCookie");
  
  // Allocate memory for the cookie, if there is one
  //  if (0 != size) {
  //    char cookie [size]; //

    // Once again, with cookie memory this time
    err = AudioConverterGetProperty (converter, kAudioConverterCompressionMagicCookie, &size, cookie);
    AbortOnStatus (err, @"AudioConverterGetProperty converter, kAudioConverterCompressionMagicCookie");

    // Write it.  Oooops, no interface for ExtAudioFile.... but we can get
    // at a lower level interface.

    AudioFileID fileID;
  
    size = sizeof(fileID);

    err = ExtAudioFileGetProperty(self.file, kExtAudioFileProperty_AudioFile, &size, &fileID);
    AbortOnStatus (err, @"ExtAudioFileGetProperty outFile, kExtAudioFileProperty_AudioFile");
    
    // Now, write the cookie
    err = AudioFileSetProperty(fileID, kAudioFilePropertyMagicCookieData, size, cookie);
    AbortOnStatus(err, @"AudioFileSetProperty fileID kAudioFilePropertyMagicCookieData");
  //  }
}

///
/// Audio File Configuration and Announcement
///
#pragma mark - Audio File Configuration and Announcement

- (void) configureFile {
  OSStatus err = noErr;
  
  NSAssert (nil == self.file, @"Called configureFile w a file?!");

  // Update the block count.
  [self fileUpdateBlockCount: NO];
  
  // Update the URL for the audio data
  [self fileUpdateFileURL: AUDIO_FILE_EXTENSION];

#if 0
  // AVAudioFormat *format = [self.engine.mainMixerNode outputFormatForBus: 0];
  AVAudioFormat *fileFormat = [[AVAudioFormat alloc] initWithSettings: self.fileSettings];
#endif
  
  // The 'original' AQRecorder.mm code set only three fields when
  // creating the AVAudioQueue.  But then, when creating the file, the queue's
  // format was read back in, using GetProperty, and that 'read format' was
  // used to create the file.  We don't have a queue to read and our
  // AVAudioEngine uses LPCM, like by strong default.
  //
  // But, the read back doesn't appear to change the Stream Description so it
  // won't matter.

  AudioStreamBasicDescription description = { 0 };
  description.mSampleRate = AUDIO_HW_SAMPLE_RATE;
  description.mFormatID   = AUDIO_FILE_FORMAT;
  description.mChannelsPerFrame = AUDIO_FILE_CHANNELS;
  description.mFramesPerPacket  = 1024;
  //  description.mBitsPerChannel   = 16;
  //  description.mFormatFlags = (kAudioFormatFlagIsNonInterleaved |
  //                              kAudioFormatFlagIsPacked |
  //                              kAudioFormatFlagIsFloat);
  
  // Actually create the ExtAudioFile
  err = ExtAudioFileCreateWithURL ((__bridge CFURLRef)(self.fileURL),
                                   AUDIO_FILE_TYPE,
                                   &description,
                                   NULL,
                                   kAudioFileFlags_EraseFile,
                                   &_file);
  AbortOnStatus(err, @"ExtAudioFileCreateWithURL");

#if 0
  // At this point, if we needed to, we can prove that self.file is valid.
  // We'll aimlessly read back-in the format; during debugging it can be
  // used to confirm the setup.
  {
    AudioStreamBasicDescription format;
    UInt32 size = sizeof(format);
    err = ExtAudioFileGetProperty(self.file, kExtAudioFileProperty_FileDataFormat, &size, &format);
    AbortOnStatus (err, @"ExtAudioFileGetProperty outFile, kExtAudioFileProperty_FileDataFormat");
  }
#endif
  
  // Tell the ExtAudioFile what the client format is.  The audio file writes
  // occur as a tap on the mainMixerNode - so we'll grab that format.  We expect
  // that format to be stereo, non-interleaved; we further expect that the
  // ExtAudioFile converter will 'do the right thing' for the file result.
  //
  // And yet... there is direct evidence and stackoverflow confirmation that
  // the tap's AVAudioPCMBuffer must have one buffer, even with two channels,
  // and be interleaved.  The ExtAudioFileWrite barfs otherwise.
  //
  // Our confidence in the above is captured in the value of
  //   AUDIO_FILE_ANNOUNCE_CLIENT_FORMAT
#if AUDIO_FILE_ANNOUNCE_CLIENT_FORMAT
  AVAudioFormat *clientFormat = [self.engine.mainMixerNode outputFormatForBus: 0];
  AudioStreamBasicDescription clientDescription = *clientFormat.streamDescription;
  
  err = ExtAudioFileSetProperty(self.file, kExtAudioFileProperty_ClientDataFormat,
                                sizeof (clientDescription),
                                &clientDescription);
  AbortOnStatus(err, @"ExtAudioFileSetProperty self.file kExtAudioFileProperty_ClientDataFormat");
#endif

  // This new file will expire in self.recordingInterval seconds from now.
  self.fileExpiration = [[NSDate date] dateByAddingTimeInterval: 0.95 * self.recordingInterval];
  
  //  [self writeMagicCookie];

}

- (void) configureFileIfNeeded { if (nil == self.file) [self configureFile]; }

- (void) announceFile {
  if (nil != self.file) {

    OSStatus err = noErr;
    // AudioConverterRef ... writeCookie
    
    //    [self writeMagicCookie];

    // Close out the AudioFile; presumably closing fileURL
    err = ExtAudioFileDispose(self.file);
    AbortOnStatus(err, @"Missed Dispose"); 

    // Announce
    NSLog (@"Wrote Audio File: (%10x): %@",
           0xDEADBEEF,
           self.fileURL.lastPathComponent);

    // Queue the URL - avoid this if 'dispose' works.
    [self.fileDelayQueue addObject: self.fileURL];
    
    // To be compatible with exisiting 'configureFile'...
    self.file    = nil;
    self.fileURL = nil;
    self.fileExpiration = nil;
    
    // Get the next file, fileURL, etc
    [self configureFile];

    // If the fileDelayQueue is full, pop and announce.
    if (AUDIO_FILE_DELAY_QUEUE_SIZE == self.fileDelayQueue.count) {
      RecordedFileCallback callback = self.callback;
      
      // Preserve the current 'file' parameters.  They will be modified
      // by the upcomine 'configureFile'
      NSURL *lastURL = (NSURL *) [self.fileDelayQueue objectAtIndex: 0];
      [self.fileDelayQueue removeObjectAtIndex: 0];
    
      // Invoke the callback.  We'll dispatch to some other thread - the file
      // isn't going anywhere and, in fact, it is the responsibility of the
      // callback to discard it.
      if (callback) {
      
        dispatch_async (self.callbackQueue, ^{
          callback (0, 0, lastURL);
        });
      }
    }
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
    
    // These file settings, particularly because of MPEG4AAC (in
    // AUDIO_FILE_FORMAT), will be distinct from the format in the
    // AVAudioEngine; the engine format is LPCM.

    self.fileSettings = @{ AVFormatIDKey                 : @(AUDIO_FILE_FORMAT),
                           AVSampleRateKey               : @(AUDIO_HW_SAMPLE_RATE),
                           AVNumberOfChannelsKey         : @(AUDIO_FILE_CHANNELS),
                           AVEncoderBitRatePerChannelKey : @(16),
                           //AVEncoderAudioQualityKey      : @(AVAudioQualityMedium)
                           };
    
    // Define the format for the two busses: input -> mixer, mixer -> output.
    // The number of channels below must match, is seems, with the above
    // fileSettings.

    // MonoFormat
    AVAudioFormat *monoFormat =
      [[AVAudioFormat alloc] initStandardFormatWithSampleRate: AUDIO_HW_SAMPLE_RATE
                                                     channels: 1];
    
    // StereoFormat
    //
    // It seems this is NOT-INTERLEAVED and must not be interleaved.  If you try
    // initWithCommonFormat:sampleRate:channels:interleaved of YES, then you can
    // create the format w/o a problem, but you'll get a InvalidFormat (-10868)
    // when trying to connect nodes with the interleaved format.
    //
    // Okay, so what?  If you are using stereo and it is not interleaved then
    // the AVAudioPCMBuffer tap will use two non-interleaved buffers to capture
    // the stereo audio.  But, here is the problem, apparently:
    //
    // http://stackoverflow.com/a/9220502/1286639
    // "One thing to check is that ExtAudioFile expects only one buffer. So your
    //  fillBufList->mNumberBuffers should always equal 1, and if you need to do
    //  stereo, you need to interleave the audio data, so that
    //  mBuffers[0].mNumberChannels is equal to 2 for stereo."
    //
    // Thus, apparently, in ExtAudioFileWrite(), the AudioBufferList must have
    // a mNumberBuffers = 1.  But maybe there is a shot at success, an
    // ExtAudioFile has a ClientDataFormat; if we set that to stereo, not
    // interleaved then maybe that input will be recognized.
    //
    AVAudioFormat *stereoFormat =
      [[AVAudioFormat alloc] initStandardFormatWithSampleRate: AUDIO_HW_SAMPLE_RATE
                                                     channels: 2];
    
    // Save, for file use
    self.format = stereoFormat;
    
    // To mix stereo we need an EnvironmentNode (environment because it models
    // the position of a listener - thus left or right of the source.
    self.environmentNode = [[AVAudioEnvironmentNode alloc] init];
    
    // Is this the default?
    self.environmentNode.volume = 1.0;
    
    // This is the default.  Ranges from {-1.0, +1.0}
    self.environmentNode.pan    = 0.0;

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
                  format: stereoFormat];

    // The mainMixer goes to the output
    [self.engine connect: self.engine.mainMixerNode
                      to: self.engine.outputNode
                  format: stereoFormat];
    

    // Don't overdrive the input; using 1.0 seems to.
    self.engine.inputNode.volume = 0.8;

#if USE_INTERLEAVED_CONVERT
    AVAudioFormat *interleavedFormat =
      [[AVAudioFormat alloc] initWithCommonFormat: AVAudioPCMFormatFloat32
                                       sampleRate: AUDIO_HW_SAMPLE_RATE
                                         channels: AUDIO_FILE_CHANNELS
                                      interleaved: YES];
    
    AVAudioPCMBuffer *interleavedBuffer =
      [[AVAudioPCMBuffer alloc] initWithPCMFormat: interleavedFormat
                                    frameCapacity: AUDIO_HW_SAMPLE_RATE];
#endif
    
    // Today, we are getting ~16384 frames per block callback. (4 * 4096)
    [self.engine.mainMixerNode
     installTapOnBus: 0
     
     // This number is ignored... and an Apple bug?
     bufferSize: 4096 * 16

     // Use of 'nil' is quasi-required - based on the documentation - because
     // the mainMixerNode is attached to the outputNode and thus the format
     // of the mainMixerNode is already determined.
     //
     // Don't for one minute think of putting 'interleaved: YES' here...
     format: [self.engine.mainMixerNode outputFormatForBus: 0]
     
     // This 'handler' needs to allocate and initialze an AVAudioFile and to
     // write buffer data to that file.  If this handler is too slow, we
     // perhaps might not actually know but should increase the 'bufferSize'
     // to allow for a greater time between invocation of this handler.  The
     // latter only solves a 'too slow' problem if it is the allocation and
     // initialization of the AVAudioFile that is slow.
     block: ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
       
       OSStatus err = noErr;
       
       // The date, right now.  Has 'interval' (10 seconds) elapsed?
       NSDate  *date  = [NSDate date];
       
       // Allocate a file if we don't have one.  We do this lazily which helps
       // to ensure that we have a file when we actually need one
       AbortOnNullVoid(self.file, @"No file");
       //[self configureFileIfNeeded];
       
       // The AVAudioPCMBuffer is 'specially designed' to easily write to a file
       // and, as part of the write, be converted to the file's format...
       //
       // ... except in virtually every case I've tried.
       //
       // And that means we convert from buffer to interleavedBuffer.

#if USE_INTERLEAVED_CONVERT
       // @property(nonatomic, readonly) float *const *floatChannelData
       // Discussion
       // The floatChannelData property returns pointers to the buffer’s audio
       // samples, if the buffer’s format is 32-bit float. It returns nil if it
       // is another format.
       //
       // The returned pointer is to format.channelCount pointers to float. Each
       // of these pointers is to frameLength valid samples, which are spaced by
       // stride samples.
       //
       // If the format is not interleaved, as with the standard deinterleaved
       // float format, then the pointers will be to separate chunks of memory
       // and the stride property value is 1.
       //
       // If the format is interleaved, then the pointers will refer to the same
       // buffer of interleaved samples, each offset by 1 frame, and the stride
       // property value is the number of interleaved channels.
       interleavedBuffer.frameLength = buffer.frameLength;
       
       for (int channel = 0; channel < AUDIO_FILE_CHANNELS; channel++) {
         float *srcSamples = buffer.floatChannelData[channel];
         float *tgtSamples = interleavedBuffer.floatChannelData[channel];
         
         for (AVAudioFrameCount frame = 0; frame < buffer.frameLength; frame++)
           tgtSamples[interleavedBuffer.stride * frame] = srcSamples[buffer.stride * frame];
         }
       
       err = ExtAudioFileWrite (self.file, interleavedBuffer.frameLength, interleavedBuffer.audioBufferList);
       AbortOnStatus(err, @"File ExtAudioFileWrite");
#else
       err = ExtAudioFileWriteAsync (self.file, buffer.frameLength, buffer.audioBufferList);
       AbortOnStatus(err, @"File ExtAudioFileWrite");
#endif
       
       // Check if 'now' is beyond the pre-computed fileExpiration.  If so, or
       // if we don't have a fileExpiration, announce the file.
       if (nil == self.fileExpiration ||
           [date timeIntervalSinceDate: self.fileExpiration] > 0) {
         [self announceFile];
       }
       
       // Keep the meter up-to-date
       [self updateMeterOfRecordedLevel: buffer
                                 format: stereoFormat];

       // Do last, so as not to upset current handling.  This determines the
       // frequency at which this tap is called; which we use to help with
       // computing the levels.
       //
       // buffer.frameLength = 4096;
     }];
    
    // The AVAudioEngine is configued; the tap is installed
    
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
  return (nil == self.engine ? 0.0 : self.environmentNode.pan);
}

- (void) setInputPan:(float)inputPan {
  if (nil != self.engine)
    self.environmentNode.pan = MAX (-1.0, MIN (+1.0, inputPan));
}

///
/// Audio Output Gain
///
#pragma mark - Audio Output Gain

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
    [self configureFileIfNeeded];
    [self.engine startAndReturnError: &error];
    AbortOnError(error, @"record");
  }
}

- (void) reset {
  WarnIfNotConfigured(@"Reset", YES);
  
  // Update our session count.
  [self fileUpdateSessionCount: NO];

  // If recording, our 'pause' will invoke announceFile.
  [self pause];
  
  // Stop and Reset the AVAudio Engine
  [self.engine stop];
  [self.engine reset];
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
