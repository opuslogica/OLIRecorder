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
@property (strong, nonatomic) IBOutlet UIButton *togglePlayButton;
@property (nonatomic, retain) MPMoviePlayerController *player;
//@property (nonatomic, retain) AVAudioPlayer *player;
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


//
// Play
//
- (NSURL *) createPlaybackUrl {
  return [NSURL URLWithString: @"audio-03.m4a"
                relativeToURL: [StreamPlayViewController documentsDirectory]];
}

- (BOOL) isPlaying {
  if (nil == self.player) return NO;
  
  switch (self.player.playbackState) {
    case MPMoviePlaybackStatePlaying:
    case MPMoviePlaybackStatePaused:
      return YES;
      
    default:
      return NO;
  }
}

-(IBAction)togglePlay:(UIButton *) sender {
  switch (self.player.playbackState) {
    case MPMoviePlaybackStateStopped:
      self.player = [[MPMoviePlayerController alloc] initWithContentURL:
                     [self createPlaybackUrl]];
      
      self.player.shouldAutoplay = YES;
      [self.player play];
      break;
      
    case MPMoviePlaybackStatePlaying:
      [self.player pause];
      break;
      
    case MPMoviePlaybackStatePaused:
      [self.player play];
      break;
      
    default:
      break;
  }
  
  [self.togglePlayButton setTitle: ([self isPlaying] ? @"Pause" : @"Play")
                         forState: UIControlStateNormal];
}

- (void) stopPlay {
  if (nil != self.player) {
    [self.player stop];
    self.player = nil;
    [self.togglePlayButton setTitle: @"Play" forState: UIControlStateNormal];
  }
}

@end
