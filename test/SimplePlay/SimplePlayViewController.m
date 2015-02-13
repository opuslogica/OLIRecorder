//
//  ViewController.m
//  SimplePlay
//
//  Created by Ed Gamble on 1/2/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//
#import "SimplePlayViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface SimplePlayViewController ()
@property (nonatomic, readwrite) AVAudioSession *session;
@property (nonatomic, readwrite) AVAudioEngine  *engine;
@property (nonatomic, readwrite) AVAudioPlayerNode *player;
@property (nonatomic, readwrite) AVAudioFile *file;
@property (strong, nonatomic) IBOutlet UIButton *playButton;
@property (strong, nonatomic) IBOutlet UIButton *setupButton;
@property (strong, nonatomic) IBOutlet UISlider *volumeSlider;
@end

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

#define AUDIO_BUFFER_DURATION     0.005
#define AUDIO_HW_SAMPLE_RATE      44100.0


@implementation SimplePlayViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
  

}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

- (void) setup {
  NSError *error = nil;
  
  self.session = [AVAudioSession sharedInstance];
  
  [self.session setCategory: AVAudioSessionCategoryPlayAndRecord error: &error];
  AbortOnError(error, @"missed audio category");
#if 1
  [self.session setPreferredIOBufferDuration: AUDIO_BUFFER_DURATION error: &error];
  AbortOnError(error, @"missed IOBufferDuration");
  
  [self.session setPreferredSampleRate: AUDIO_HW_SAMPLE_RATE error: &error];
  AbortOnError(error, @"missed SampleRate");
#endif
  
  
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
  

  [self.session requestRecordPermission:^(BOOL granted) {
    NSError *error = nil;
    NSLog (@"RecordPermission: %@", (granted ? @"Granted" : @"Denied"));
    
    // Skip out if permission has not been granted.
    if (!granted) return;
    
    self.engine = [[AVAudioEngine alloc] init];
    self.player = [[AVAudioPlayerNode alloc] init];
    
    [self.engine attachNode: self.player];

    for (int dex = 0; dex <= 3; dex++) {
      NSURL *url = [[NSBundle mainBundle] URLForResource:
                    [NSString stringWithFormat: @"audio-%02d", dex]
                                           withExtension: @"m4a"];
      if (!url) {
        NSLog (@"missed %d", dex);
        return;
      }
      
      [self.player scheduleFile: [[AVAudioFile alloc] initForReading: url error: &error]
                         atTime: nil
              completionHandler: ^{
                NSLog (@"File Done: %@", url.absoluteString);
              }];
    }

    [self.engine connect: self.player
                      to: self.engine.mainMixerNode
                  format: self.file.processingFormat];
    
    [self.engine connect: self.engine.mainMixerNode
                      to: self.engine.outputNode
                  format: self.file.processingFormat];
    
    self.player.volume = 1.0;
    self.engine.mainMixerNode.volume = 1.0;
    
    [self.engine startAndReturnError: &error];
    AbortOnError(error, @"missed file");
    NSLog (@"Engine Started");
  }];
}

- (IBAction)handleSetup:(id)sender {
  if (!self.engine.running) [self setup];
  self.playButton.enabled = YES;
  self.volumeSlider.value = 1.0;
}
   
- (IBAction) play: (UIButton *) sender {

  if (!self.engine.running) {
    NSLog (@"Not enabled?!");
    return;
  }

  NSLog(@"Play!");
  [self.player play];
}

- (IBAction)handleVolume:(UISlider *)sender {
  if (!self.engine.running) {
    NSLog (@"Not enabled?!");
    return;
  }
  
  //self.engine.mainMixerNode.volume = sender.value;
  //
  self.player.volume = sender.value;
}

#pragma mark - Audio Session Interruption Notification

- (void)handleInterruption:(NSNotification *)notification
{
  AVAudioSessionInterruptionType theInterruptionType =
  (AVAudioSessionInterruptionType) [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
  
  NSLog(@"Session interrupted > --- %s ---\n", theInterruptionType == AVAudioSessionInterruptionTypeBegan ? "Begin Interruption" : "End Interruption");
  
  switch (theInterruptionType)
  {
    case AVAudioSessionInterruptionTypeBegan:
      //      self.isInterrupted = YES;
      // pause, if recording
      break;
      
    case AVAudioSessionInterruptionTypeEnded:
      //      self.isInterrupted = NO;
      // resume, if paused from recording
      break;
  }
}

#pragma mark -Audio Session Route Change Notification

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
}



@end
