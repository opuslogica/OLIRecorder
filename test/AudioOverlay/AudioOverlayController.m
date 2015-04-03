//
//  AudioOverlayController.m
//  AudioStreaming
//
//  Created by Ed Gamble on 4/2/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//

#import "AudioOverlayController.h"
#import "AudioStreamingRecorder.h"
#import "AQLevelMeter.h"


@interface AudioOverlayController ()
@property (strong, nonatomic) IBOutlet UIButton *toggleRecordButton;
@property (strong, nonatomic) IBOutlet UIProgressView *levelLeft;
@property (strong, nonatomic) IBOutlet UIProgressView *levelRight;
@property (strong, nonatomic) IBOutlet UILabel *infoLabel;
@property (strong, nonatomic) IBOutlet UILabel *levelLeftText;
@property (strong, nonatomic) IBOutlet UILabel *levelRightText;

@property (strong, nonatomic) IBOutlet AQLevelMeter *leftMeterView;

@property (nonatomic, retain) AudioStreamingRecorder *recorder;
@end

#define kAudioBufferSizeInSeconds 10.0
#define kAudioBufferCount 2


@implementation AudioOverlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
  self.recorder = [[AudioStreamingRecorder alloc] initWithRecordingInterval: kAudioBufferSizeInSeconds];
  
  [self.recorder configureWithCallback: ^(unsigned int session, unsigned int block, NSURL *file) {
    NSLog (@"Callback: %d, %d, %@", session, block, file);
    
    // Do this on the 'main queue' - ensures that the UI is updated.
    dispatch_async(dispatch_get_main_queue(), ^{
      self.infoLabel.text = file.lastPathComponent;
    });
  }];
  
  [self.toggleRecordButton setEnabled: YES];
  // [self toggleMonitor: self.toggleMonitorButton];
  
  self.recorder.meterCallback = ^(AudioQueueLevelMeterState leftMeter,
                                  AudioQueueLevelMeterState rightMeter) {
    dispatch_async(dispatch_get_main_queue(), ^{
      self.levelLeft.progress  = 50 * leftMeter.mAveragePower;
      self.levelRight.progress = 50 * rightMeter.mAveragePower;
      
      self.levelLeftText.text = [NSString stringWithFormat: @"%f",
                                 50 * leftMeter.mAveragePower];
      self.levelRightText.text = [NSString stringWithFormat: @"%f",
                                  50 * rightMeter.mAveragePower];
      //NSLog (@"Left: %.2g", leftMeter.mAveragePower);
    });
  };

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

- (void) updateRecordButton: (Boolean) recording {
  NSLog (@"Record?: %@", (recording ? @"Yes" : @"No"));
  
  [self.toggleRecordButton setTitle: (recording ? @"Pause" : @"Record")
                           forState: UIControlStateNormal];
  
}

- (IBAction)toggleRecord:(UIButton *)sender {
  NSLog (@"Audio: Want to toggle");
  if (self.recorder.isRecording)
    [self.recorder pause];
  else {
    [self.recorder record];
    self.leftMeterView.aq = self.recorder.queue;
  }
  
  [self updateRecordButton: self.recorder.isRecording];
}

@end
