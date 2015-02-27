//
//  ViewController.m
//  StreamPlay
//
//  Created by Ed Gamble on 2/27/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//

#import "StreamPlayViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@interface StreamPlayViewController ()
@property (nonatomic, readwrite) AVAudioSession *session;
@property (strong, nonatomic) IBOutlet UIButton *playButton;
@property (strong, nonatomic) IBOutlet UIButton *stopButton;
@property (nonatomic, retain) AVAudioPlayer *player;
@end

@implementation StreamPlayViewController

+ (NSURL *) documentsDirectory {
  return [[[NSFileManager defaultManager] URLsForDirectory: NSDocumentDirectory
                                                 inDomains: NSUserDomainMask] lastObject];
}


- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear: animated];
  [self configureSessionIfAppropriate];
}

//
// Play
//
- (NSURL *) createPlaybackUrl {
    return  [[NSBundle mainBundle] URLForResource: @"audio-00"
                                    withExtension: @"m4a"];
}

- (BOOL) isPlaying {
  return nil != self.player && self.player.isPlaying;
}

-(IBAction)togglePlay:(UIButton *) sender {
  NSAssert (nil != self.player, @"missed player");

  if (self.player.isPlaying)
    [self.player pause];
  else
    [self.player play];
  
  [self.playButton setTitle: (self.player.isPlaying ? @"Pause" : @"Play")
                         forState: UIControlStateNormal];
}

-(IBAction)stopPlay:(UIButton *) sender {
  [self.player stop];
  [self.playButton setTitle: @"Play" forState: UIControlStateNormal];
}

- (IBAction)volumeAdjust:(UISlider *)sender {
  self.player.volume = sender.value;
}

- (void) configurePlayer {
  NSError *error = nil;
  self.player = [[AVAudioPlayer alloc] initWithContentsOfURL: [self createPlaybackUrl] error:&error];
  NSLog(@"Player Configured: %@", self.player);
  if (nil != error)
    NSLog (@"PLayer Configured: (Error):\n    %@", error);
}

- (void) configureSession {
  
  //
  // (Re)Configure the AVAudioSession
  //
  self.session = [AVAudioSession sharedInstance];
  
#if 0
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
#endif
  
  // Here the callback is called immediately after the first request.  If the
  // first request, then their will be an 'alert' and a callback - that might
  // be too late.
  [self.session requestRecordPermission:^(BOOL granted) {
    NSLog (@"RecordPermission: %@", (granted ? @"Granted" : @"Denied"));
    
    // Skip out if permission has not been granted.
    if (!granted) return;
    
    
    
    [self configurePlayer];
    self.playButton.enabled = YES;
    self.stopButton.enabled = YES;
  }];
}

- (void) configureSessionIfAppropriate {
  if (nil == self.session)
    [self configureSession];
}
@end
