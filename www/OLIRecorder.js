/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
*/

var argscheck = require('cordova/argscheck'),
    utils = require('cordova/utils'),
    exec = require('cordova/exec');

var recorderObjects = {};

/**
 * This class provides access to the device recording interfaces for recording sound
 *
 * @constructor
 * @param file_ready_callback  The callback to be called when a recorded file is available
 *                                  recordedFileCallback(string-ish filename)
 * @param errorCallback         The callback to be called if there is an error.
 *                                  errorCallback(int errorCode) - OPTIONAL
 * @param stateCallback        The callback to be called when recorder state has changed.
 *                                  stateCallback(int sessionStateCode) - OPTIONAL
 */
var OLIRecorder = function(file_ready_callback, error_callback, state_callback) {
  console.log('OLIRecorder creation');
  argscheck.checkArgs('FFF', 'OLIRecorder', arguments);
  this.id = utils.createUUID();
  this.file_ready_callback = file_ready_callback;
  this.error_callback = error_callback;
  this.state_callback = state_callback;
  recorderObjects[this.id] = this;
  this._position = -1;
  exec(null, this.error_callback, "OLIRecorder", "create", [this.id]);
};

// SESSION  messages
OLIRecorder.SESSION_STATE = 1;
OLIRecorder.SESSION_ERROR = 2;
OLIRecorder.SESSION_ANNOUNCE_FILE = 3;

// Session State Codes
OLIRecorder.SESSION_STATE_WAITING = 10;
OLIRecorder.SESSION_STATE_PAUSING = 11;
OLIRecorder.SESSION_STATE_RUNNING = 12;
OLIRecorder.SESSION_STATE_DEAD    = 19;

// "static" function to return existing objs.
OLIRecorder.get = function(id) {
    return recorderObjects[id];
};

/**
 * Start recording a session.
 */
OLIRecorder.prototype.start = function(options) {
  console.log("OLIRecorder: JS: start: ", options);
  exec(null, null, "OLIRecorder", "startSession", [this.id, options]);
};

/**
 * Pause recording a session.
 */
OLIRecorder.prototype.pause = function() {
    exec(null, this.errorCallback, "OLIRecorder", "pauseSession", [this.id]);
};

/**
 * Stop recording a session.
 */
OLIRecorder.prototype.stop = function() {
    var me = this;
    exec(function() {
        me._position = 0;
    }, this.errorCallback, "OLIRecorder", "stopSession", [this.id]);
};

/**
 * Release the recorder object.
 */
OLIRecorder.prototype.release = function() {
    var me = this;
    exec(function() {
    }, this.errorCallback, "OLIRecorder", "releaseRecorder", [this.id]);
};

//
// Examples (end to end)
//

/**
 * Get input gain
 */
OLIRecorder.prototype.getInputGain = function(success, fail) {
    var me = this;
    exec(function(p) {
        me._position = p;
        success(p);
    }, fail, "OLIRecorder", "getInputGain", [this.id]);
};

/**
 * set input gain
 */
OLIRecorder.prototype.setInputGain = function(volume) { // float: [0.0, 1.0]
    exec(null, null, "OLIRecorder", "setInputGain", [this.id, volume]);
};

/**
 * enable output
 */
OLIRecorder.prototype.enableOutput = function(enable) { // bool: 0, 1
  exec(null, null, "OLIRecorder", "enableOutput", [this.id, enable]);
};

/**
 * Get output gain
 */
OLIRecorder.prototype.getOutputGain = function(success, fail) {
  var me = this;
  exec(function(p) {
       me._position = p;
       success(p);
       }, fail, "OLIRecorder", "getOutputGain", [this.id]);
};

/**
 * set output gain
 */
OLIRecorder.prototype.setOutputGain = function(volume) { // float: [0.0, 1.0]
  exec(null, null, "OLIRecorder", "setOutputGain", [this.id, volume]);
};


/**
 * expunge (delete) already processed file
 */
OLIRecorder.prototype.expungeLeftOverAudioFile = function(fileURL) {
  exec (null, null,
        "OLIRecorder", "expungeLeftOverAudioFile",
        [this.id, fileURL]);
};

/**
 * expunge (delete) any and all already processed files
 */
OLIRecorder.prototype.expungeLeftOverAudioFiles = function() {
  exec (null, null,
        "OLIRecorder", "expungeLeftOverAudioFiles",
        [this.id]);
};

/**
 * Apply handleFile to any and all already processed files
 */
OLIRecorder.prototype.processLeftOverAudioFiles = function(handleFile) {
  exec (function (files) { files.forEach(handleFile) },
        null,
        "OLIRecorder", "arrayOfLeftOverAudioFiles",
        [this.id]);
};

OLIRecorder.prototype.getMeterLevels = function(handleLevels) {
  exec(function(levels) { handleLevels(levels); }, null, "OLIRecorder", "getMeterLevels", [this.id]);
};

/**
 * Callbacks.  Invoked view evalJS.  There is no CDVInvokedUrlCommand
 
/**
 * process file
 */
OLIRecorder.processFile = function(id, url) {
  console.log ("OLIRecorder: JS: processFile: ", url)

  var recorder = recorderObjects[id];

  if (recorder && recorder.file_ready_callback)
    recorder.file_ready_callback(url)
  else
    console.log ("OLIRecorder: JS: processFile: <missed recorder and/or callback>");
}

/**
 * Process route changes
 */
OLIRecorder.processRoute = function(id, placeholder) {
  console.log ("OLIRecorder: JS: processRoute: ", placeholder)
  
  var recorder = recorderObjects[id];
  
  if (!recorder)
    console.log ("OLIRecorder: JS: processRoute: <missed recorder>");
};


/**
 * Audio has status update.
 * PRIVATE
 *
 * @param id            The recorder object id (string)
 * @param msgType       The 'type' of update this is
 * @param value         Use of value is determined by the msgType
 */
OLIRecorder.onStatus = function(id, msgType, value) {

  var recorder = recorderObjects[id];

  if (recorder) {
    switch(msgType) {

      case OLIRecorder.SESSION_STATE:
        recorder.state_callback && recorder.state_callback(value);
        break;

      case OLIRecorder.SESSION_ERROR:
        recorder.error_callback && recorder.error_callback(value);
        break;

      case OLIRecorder.SESSION_ANNOUNCE_FILE:
        recorder.file_ready_callback && recorder.file_ready_callback(value);
        break;

      default:
        console.error && console.error("Unhandled OLIRecorder :: " + msgType);
        break;
    }
  } else {
    console.error && console.error("Received OLIRecorder callback for unknown recorderObject :: " + id);
  }
};

module.exports = OLIRecorder;
