//
//  ViewController.m
//  PhromPhoncert
//
//  Created by Ed Gamble on 2/18/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//

#import "ViewController.h"
#import "AVFoundation/AVFoundation.h"
#import "AQRecorder.h"

#define AbortOnError( error, desc ) \
do {                              \
if (nil != error) {             \
NSLog (@"Error: %@", desc);    \
abort ();                     \
}                               \
} while (0)

#define AUDIO_BUFFER_DURATION 0.2
#define AUDIO_HW_SAMPLE_RATE  44100


@interface ViewController ()
@property (nonatomic) AVAudioSession *session;
@end

static AQRecorder recorder = AQRecorder();

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}


- (IBAction)toggleRecord:(id)sender {
  NSError *error = nil;
  
  if (nil == self.session) {
    
    AVAudioSession *sesson;
    
    self.session = [AVAudioSession sharedInstance];
    
    [self.session setCategory: AVAudioSessionCategoryPlayAndRecord error: &error];
    AbortOnError(error, @"missed audio category");
    
    [self.session setMode: AVAudioSessionModeDefault error: &error];
    AbortOnError(error, @"missed audio mode");
    
    [self.session setActive:YES error: &error];
    AbortOnError(error, @"missed active");
    
    [self.session setPreferredIOBufferDuration: AUDIO_BUFFER_DURATION error: &error];
    AbortOnError(error, @"missed IOBufferDuration");
    
    [self.session setPreferredSampleRate: AUDIO_HW_SAMPLE_RATE error: &error];
    AbortOnError(error, @"missed SampleRate");
    
    [self.session setPreferredInputNumberOfChannels: (NSInteger) 1 error: &error];
    AbortOnError(error, @"setPreferredInputNumberOfChannels");
    
    
    // We request permission to record.  The very first time the app is launch the
    // User will be prompted to allow recording and then the below callback will
    // be invoked.  After that very first time, the callback is simply invoked
    // immediately.
    
    [self.session requestRecordPermission:^(BOOL granted) {
      AQRecorder *recorder = new AQRecorder ();
      
      NSString *s1 = @"audio1.aac";
      NSString *s2 = @"audio2.aac";
      
      recorder->StartRecord ((__bridge CFStringRef) s1,
                             (__bridge CFStringRef) s2);
    }];
  }
}

@end
