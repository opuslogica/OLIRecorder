/* OLIRecorder.h -*- ObjC -*- code to play HLS (m3u8 playlist) files. */
/* Starter version created by Jaime Caicedo on Feb 3rd, 2014 */
/* Subsequent code and modifications by Edward B. Gamble, Jr., Brian J. Fox,
   and others, of Opus Logica, Inc. */

#import <UIKit/UIKit.h>
#if defined (ED_STANDALONE)
#import "CDVPlugin.h"
#else
#import <Cordova/CDVPlugin.h>
#endif
#import "AudioStreamingRecorder.h"
#import "AQLevelMeter.h"


#define OLIRECORDER_DEFAULT_RECORDING_INTERVAL  10.0 /* seconds */

@interface OLIRecorder : CDVPlugin

// CDVPlugin Framework (apparently)
@property(nonatomic, retain) NSString* mediaId;

// OLIRecorder Specific
@property(strong, nonatomic, readonly) AudioStreamingRecorder *audioRecorder;
@property(strong, nonatomic, readonly) AQLevelMeter *audioMeter;

//
- (void)create:(CDVInvokedUrlCommand*)command;
- (void)startSession:(CDVInvokedUrlCommand*)command;
- (void)pauseSession:(CDVInvokedUrlCommand*)command;
- (void)stopSession:(CDVInvokedUrlCommand*)command;

- (void)getInputGain:(CDVInvokedUrlCommand*)command;
- (void)setInputGain:(CDVInvokedUrlCommand*)command;

- (void)releaseRecorder:(CDVInvokedUrlCommand*)command;

- (void) createMeter:(CDVInvokedUrlCommand*)command;
@end
