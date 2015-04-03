//
//  ViewController.m
//  AudioOverlay
//
//  Created by Ed Gamble on 4/2/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//

#import "ViewController.h"
#import "AudioStreamingRecorder.h"
#import "AQLevelMeter.h"

@interface ViewController ()
@property (strong, nonatomic) IBOutlet UIWebView *webView;
@property (strong, nonatomic) IBOutlet UIButton *buttonToggleRecord;

@property AudioStreamingRecorder *audioRecorder;
@property AQLevelMeter *audioMeter;

@end

@implementation ViewController

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
  self.webView.scalesPageToFit = false;
  [self.webView loadRequest:
   [NSURLRequest requestWithURL:
    [NSURL URLWithString: @"https://imgur.com/gallery/7bp3Zd2"]]];
}

- (IBAction)toggleRecord:(id)sender {
  if (nil == self.audioRecorder) {
    self.audioRecorder = [[AudioStreamingRecorder alloc] initWithRecordingInterval: 10.0];
    [self.audioRecorder configureWithCallback: ^(unsigned int session, unsigned int block, NSURL *file) {
      NSLog (@"Callback: %d, %d, %@", session, block, file);
    }];
  }
  
  if (self.audioRecorder.isRecording) {
    [self.audioRecorder pause];
    [self.audioMeter removeFromSuperview];
    self.audioMeter = nil;
  }
  else {
    [self.audioRecorder record];
    self.audioMeter = [[AQLevelMeter alloc] initWithFrame:
                       CGRectMake(20, 200, 320, 50)];
    
    self.audioMeter.aq = self.audioRecorder.queue;
    
    [self.webView addSubview: self.audioMeter];
  }
  
  self.buttonToggleRecord.titleLabel.text =
  (self.audioRecorder.isRecording ? @"Pause" : @"Record");
}

@end
