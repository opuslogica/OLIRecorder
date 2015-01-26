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
 * This class provides access to the device media, interfaces to both sound and video
 *
 * @constructor
 * @param src                   The file name or url to play
 * @param fileAnnounceCallback  The callback to be called when a recorded file is available
 *                                  recoredFileCallback(string-ish filename)
 * @param errorCallback         The callback to be called if there is an error.
 *                                  errorCallback(int errorCode) - OPTIONAL
 * @param stateCallback        The callback to be called when recorder state has changed.
 *                                  stateCallback(int sessionStateCode) - OPTIONAL
 */
var OLIRecorder = function(src, fileAnnounceCallback, errorCallback, stateCallback) {
  console.log('OLIRecorder creation');
  argscheck.checkArgs('SFFF', 'OLIRecorder', arguments);
  this.id = utils.createUUID();
  mediaObjects[this.id] = this;
  this.src = src;
  this.fileAnnounceCallback = fileAnnounceCallback;
  this.errorCallback = errorCallback;
  this.stateCallback = stateCallback;
  this._duration = -1;
  this._position = -1;
  exec(null, this.errorCallback, "OLIRecorder", "create", [this.id, this.src]);
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
 * Audio has status update.
 * PRIVATE
 *
 * @param id            The media object id (string)
 * @param msgType       The 'type' of update this is
 * @param value         Use of value is determined by the msgType
 */
OLIRecorder.onStatus = function(id, msgType, value) {

  var recorder = recorderObjects[id];

  if (media) {
    switch(msgType) {

      case OLIRecorder.SESSION_STATE:
        recorder.stateCallback && recorder.stateCallback(value);
        break;

      case OLIRecorder.SESSION_ERROR:
        recorder.errorCallback && recorder.errorCallback(value);
        break;

      case OLIRecorder.SESSION_ANNOUNCE_FILE:
        recorder.fileAnnounceCallback && recorder.fileAnnounceCallback(value);
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
