//
//  ViewController.m
//  AudioStreaming
//
//  Created by Ed Gamble on 12/5/14.
//  Copyright (c) 2014 Opus Logica Inc. All rights reserved.
//
#import "AudioStreamingViewController.h"

//
// AVCaptureAudioDataOutput
//
//
@interface AudioStreamingViewController ()
@property (nonatomic, readwrite) IBOutlet UIButton *resetSessionButton;
@property (nonatomic, readwrite) IBOutlet UIButton *toggleRecordButton;
@property (strong, nonatomic) IBOutlet UISlider *recordVolumnSlider;
@property (strong, nonatomic) IBOutlet UISlider *monitorVolumeSlider;
@property (strong, nonatomic) IBOutlet UILabel *infoLabel;
@property (strong, nonatomic) IBOutlet UIButton *toggleMonitorButton;
@property (strong, nonatomic) IBOutlet UIProgressView *levelLeft;
@property (strong, nonatomic) IBOutlet UIProgressView *levelRight;
@property (strong, nonatomic) IBOutlet UITextField *levelLeftText;
@property (strong, nonatomic) IBOutlet UITextField *levelRightText;

@property (nonatomic, retain) AudioStreamingRecorder *recorder;

@end

@implementation AudioStreamingViewController

- (void)viewDidLoad {
  [super viewDidLoad];
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

- (void) updateRecordButton: (Boolean) recording {
  NSLog (@"Record?: %@", (recording ? @"Yes" : @"No"));

  [self.toggleRecordButton setTitle: (recording ? @"Pause" : @"Record")
                           forState: UIControlStateNormal];

}

- (IBAction)resetSession:(id)sender {
  [self.recorder reset];
  [self updateRecordButton: NO];
  self.infoLabel.text = @"<not recording>";
}


//
// Record
//
- (IBAction) toggleRecord: (UIButton *) sender {
  self.recorder.inputGain = self.recordVolumnSlider.value;
  
  if (self.recorder.isRecording)
    [self.recorder pause];
  else
    [self.recorder record];

  [self updateRecordButton: self.recorder.isRecording];
 }

- (IBAction)recordVolumeChanged:(UISlider *)sender {
  self.recorder.inputGain = sender.value;
}

- (IBAction)inputPanChanged:(UISlider *)sender {
  self.recorder.inputPan = sender.value;
}

//
//
//
- (IBAction)toggleMonitor:(UIButton *)sender {
  self.recorder.enableOutput = !self.recorder.enableOutput;
  
  // Always set the outputGain when enabling output, at least.
  self.recorder.outputGain   = self.monitorVolumeSlider.value;

  self.monitorVolumeSlider.enabled = self.recorder.enableOutput;
  [self monitorVolumeChanged: self.monitorVolumeSlider];
  [self.toggleMonitorButton setTitle: (self.recorder.enableOutput
                                       ? @"Disable Monitor"
                                       : @"Enable Monitor")
                            forState: UIControlStateNormal];
}

- (IBAction)monitorVolumeChanged:(UISlider *)sender {
  self.recorder.outputGain = sender.value;
}

- (IBAction)getMeters:(id)sender {
  AudioQueueLevelMeterState meterLeft  = self.recorder.recordedLevelLeft;
  AudioQueueLevelMeterState meterRight = self.recorder.recordedLevelRight;
  
  NSLog(@"Meter: Lp: %f, Rp: %f",
        meterLeft.mPeakPower,
        meterRight.mPeakPower);

}
- (IBAction)getAllStats:(id)sender {
  [self.recorder reportStatsOfLeftOverAudioFiles];
}

@end