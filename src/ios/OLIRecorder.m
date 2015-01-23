/* OLIRecorder.h -*- ObjC -*- code to play HLS (m3u8 playlist) files. */
/* Starter version created by Jaime Caicedo on Feb 3rd, 2014 */
/* Subsequent code and modifications by Edward B. Gamble, Jr., Brian J. Fox,
   and others, of Opus Logica, Inc. */

#import "OLIRecorder.h"

static AudioStreamingRecorder *theAudioRecorder = nil;

@implementation OLIRecorder
@synthesize audioRecorder;

- (AudioStreamingRecorder *) audioRecorder {
  return theAudioRecorder;
}

//
// Recorder Create
//
- (void) create: (CDVInvokedUrlCommand*) command {

  self.mediaId      = [command.arguments objectAtIndex:0];
  self.resourcePath = [command.arguments objectAtIndex:1];

  NSLog (@"OLIRecorder created path-> %@    id-> %@",
         self.resourcePath, self.mediaId);

  theAudioRecorder =
    [[AudioStreamingRecorder alloc]
     initWithRecordingInterval: OLIRECORDER_DEFAULT_RECORDING_INTERVAL];

  NSLog (@"OLIRecorder: initialized theAudioRecorder: %@", theAudioRecorder);
  
  if (nil != theAudioRecorder) {

    // @synchronized(self) {
    
    
    // This configures the whole sheband which includes: a) asking for
    // permission to access the audio devices; b) linking (default) audio input
    // to (default) audio output; and c) tapping into the audio input to
    // record the audio data.  The only thing left to do is start the flow
    // of audio data.
    [theAudioRecorder configureWithCallback: ^(unsigned int session,
                                               unsigned int block,
                                               NSURL *file) {

      NSLog (@"Callback: %d, %d, %@", session, block, file);
    
      // Do this on the 'main queue' - ensures that the UI is updated.
      dispatch_async (dispatch_get_global_queue
                      (DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                        // handle file
                        
                      });
    }];
    // } /* @synchronized */
  }

  CDVCommandStatus status = (nil == theAudioRecorder
                             ? CDVCommandStatus_ERROR
                             : CDVCommandStatus_OK);
  
  [self.commandDelegate sendPluginResult: [CDVPluginResult resultWithStatus: status]
                              callbackId: command.callbackId];
}

//
// Recorder Start, Pause, Stop
//

- (void) startSession: (CDVInvokedUrlCommand*) command {
  NSLog (@"OLIRecorder: startSession");
  
  if (nil != theAudioRecorder && !theAudioRecorder.isRecording) {
    [theAudioRecorder record];
  }
  
  [self.commandDelegate
   sendPluginResult: [CDVPluginResult resultWithStatus: CDVCommandStatus_OK]
        callbackId: command.callbackId];
}

- (void) pauseSession: (CDVInvokedUrlCommand*) command {
  NSLog (@"OLIRecorder: pauseSession");
  if (nil != theAudioRecorder && theAudioRecorder.isRecording) {
    [theAudioRecorder pause];
  }
  
  [self.commandDelegate
   sendPluginResult: [CDVPluginResult resultWithStatus: CDVCommandStatus_OK]
        callbackId: command.callbackId];
}

- (void) stopSession: (CDVInvokedUrlCommand*) command {
  NSLog(@"OLIRecorder: stopSession");
  
  if (nil != theAudioRecorder) {
    [theAudioRecorder reset];
  }
  
  [self.commandDelegate
   sendPluginResult: [CDVPluginResult resultWithStatus: CDVCommandStatus_OK]
          callbackId: command.callbackId];
}


//
// Input Gain
//

- (void) getInputGain: (CDVInvokedUrlCommand*) command {
  NSLog(@"OLIRecorder: getInputGain");

  [self.commandDelegate
      sendPluginResult: [CDVPluginResult resultWithStatus: CDVCommandStatus_OK
					  messageAsDouble: theAudioRecorder.inputGain]
      callbackId: command.callbackId];
}

- (void) setInputGain: (CDVInvokedUrlCommand*) command {
  NSString* recId = [command.arguments objectAtIndex:0];
  NSNumber* gain  = [command.arguments objectAtIndex:1];

  NSLog(@"OLIRecorder: setInputGain: %@, recID: %@", gain, recId);

  if (nil != theAudioRecorder) {
    theAudioRecorder.inputGain = MAX (0.0, (MIN (gain.floatValue, 1.0)));
  }
  
  [self.commandDelegate
   sendPluginResult: [CDVPluginResult resultWithStatus: CDVCommandStatus_OK]
   callbackId: command.callbackId];
}

//
// Recorder Release
//

- (void) releaseRecorder: (CDVInvokedUrlCommand*) command {
  NSLog(@"OLIRecorder: releaseRecorder");

  if (nil != theAudioRecorder) {
    [theAudioRecorder reset];
    theAudioRecorder = nil;
  }
  
  [self.commandDelegate
   sendPluginResult: [CDVPluginResult resultWithStatus: CDVCommandStatus_OK]
   callbackId: command.callbackId];
}

@end
