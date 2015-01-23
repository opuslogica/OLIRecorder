/* OLIRecorder.h -*- ObjC -*- code to play HLS (m3u8 playlist) files. */
/* Starter version created by Jaime Caicedo on Feb 3rd, 2014 */
/* Subsequent code and modifications by Edward B. Gamble, Jr., Brian J. Fox,
   and others, of Opus Logica, Inc. */

#import <UIKit/UIKit.h>
/*
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
*/

#import "CDVPlugin.h"
#import "AudioStreamingRecorder.h"

#define OLIRECORDER_DEFAULT_RECORDING_INTERVAL  10.0 /* seconds */

@interface OLIRecorder : CDVPlugin {
}

// CDVPlugin Framework (apparently)
@property(nonatomic, retain) NSString* mediaId;
@property(nonatomic, retain) NSString* resourcePath;

// OLIRecorder Specific
@property(strong, nonatomic, readonly) AudioStreamingRecorder *audioRecorder;

/*
- (void)startPlayingAudio:(CDVInvokedUrlCommand*)command;
- (void)pausePlayingAudio: (CDVInvokedUrlCommand*)command;
- (void)stopPlayingAudio:(CDVInvokedUrlCommand*)command;
- (void)releaseAudiPlayer:(CDVInvokedUrlCommand*)command;
- (void)seekToAudio: (CDVInvokedUrlCommand*)command;
*/

// Examples
- (void)getCurrentPositionAudio:(CDVInvokedUrlCommand*)command;
- (void)getDurationAudio:(CDVInvokedUrlCommand*)command;
- (void)setVolume:(CDVInvokedUrlCommand*)command;

//
- (void)create:(CDVInvokedUrlCommand*)command;
- (void)startSession:(CDVInvokedUrlCommand*)command;
- (void)pauseSession:(CDVInvokedUrlCommand*)command;
- (void)stopSession:(CDVInvokedUrlCommand*)command;

- (void)releaseRecorder:(CDVInvokedUrlCommand*)command;



@end
