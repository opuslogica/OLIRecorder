//
//  ViewController.m
//  AudioOverlay
//
//  Created by Ed Gamble on 4/2/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()
@property (strong, nonatomic) IBOutlet UIWebView *webView;
@property (strong, nonatomic) IBOutlet UIButton *buttonToggleAudioOverlay;
@property (strong, nonatomic) IBOutlet UIView *audioOverlayContainer;

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
  self.webView.scalesPageToFit = true;
  [self.webView loadRequest:
   [NSURLRequest requestWithURL:
    [NSURL URLWithString: @"https://imgur.com/gallery/7bp3Zd2"]]];
}

- (IBAction)toggleOverlay:(id)sender {
  self.audioOverlayContainer.hidden = !self.audioOverlayContainer.hidden;
}

@end
