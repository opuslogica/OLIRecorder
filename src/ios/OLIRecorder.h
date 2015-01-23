/* HLSPlayerPlugin.m -*- ObjC -*- code to play HLS (m3u8 playlist) files. */
/* Starter version created by Jaime Caicedo on Feb 3rd, 2014 */
/* Subsequent code and modifications by Edward B. Gamble, Jr., Brian J. Fox,
   and others, of Opus Logica, Inc. */

#import <UIKit/UIKit.h>
#import <Cordova/CDVPlugin.h>
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface HLSPlugin : CDVPlugin {
}

@property(nonatomic, retain) NSString* mediaId;
@property(nonatomic, retain) NSString* resourcePath;

- (void)create:(CDVInvokedUrlCommand*)command;
- (void)getCurrentPositionAudio:(CDVInvokedUrlCommand*)command;
- (void)getDurationAudio:(CDVInvokedUrlCommand*)command;
- (void)startPlayingAudio:(CDVInvokedUrlCommand*)command;
- (void)pausePlayingAudio: (CDVInvokedUrlCommand*)command;
- (void)stopPlayingAudio:(CDVInvokedUrlCommand*)command;
- (void)releaseAudiPlayer:(CDVInvokedUrlCommand*)command;
- (void)setVolume:(CDVInvokedUrlCommand*)command;
- (void)seekToAudio: (CDVInvokedUrlCommand*)command;

@property(strong, nonatomic) MPMoviePlayerController *moviePlayer;

@end
