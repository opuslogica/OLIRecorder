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
 * @param successCallback       The callback to be called when the file is done playing or recording.
 *                                  successCallback()
 * @param errorCallback         The callback to be called if there is an error.
 *                                  errorCallback(int errorCode) - OPTIONAL
 * @param statusCallback        The callback to be called when media status has changed.
 *                                  statusCallback(int statusCode) - OPTIONAL
 */
var OLIRecorder = function(src, successCallback, errorCallback, statusCallback) {
  console.log('OLIRecorder creation');
  argscheck.checkArgs('SFFF', 'OLIRecorder', arguments);
  this.id = utils.createUUID();
  mediaObjects[this.id] = this;
  this.src = src;
  this.successCallback = successCallback;
  this.errorCallback = errorCallback;
  this.statusCallback = statusCallback;
  this._duration = -1;
  this._position = -1;
  exec(null, this.errorCallback, "OLIRecorder", "create", [this.id, this.src]);
};

// SESSION  messages
OLIRecorder.SESSION_STATE = 1;
OLIRecorder.SESSION_ERROR = 2;
OLIRecorder.SESSION_STOPPED = 3;

// "static" function to return existing objs.
OLIRecorder.get = function(id) {
    return recorderObjects[id];
};

/**
 * Start recording a session.
 */
OLIRecorder.prototype.start = function(options) {
  console.log("OLIRecorder: JS: start: ", options);
  exec(null, null, "OLIRecorder", "startSession", [this.id, this.src, options]);
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

/**
 * Get duration of an audio file.
 * The duration is only set for audio that is playing, paused or stopped.
 *
 * @return      duration or -1 if not known.
 */
HLSPlugin.prototype.getDuration = function(success, fail) {
    var me = this;
    exec(function(d) {
        me._duration = d;
        success(d);
    }, fail, "HLSPlugin", "getDurationAudio", [this.id]);
};


/**
 * Get position of audio.
 */
HLSPlugin.prototype.getCurrentPosition = function(success, fail) {
    var me = this;
    exec(function(p) {
        me._position = p;
        success(p);
    }, fail, "HLSPlugin", "getCurrentPositionAudio", [this.id]);
};

/**
 * Adjust the volume.
 */
HLSPlugin.prototype.setVolume = function(volume) {
    exec(null, null, "HLSPlugin", "setVolume", [this.id, volume]);
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
      case OLIRecorder.SESSION_STATE :
      recorder.sessionStateCallback && recorder.sessionStateCallback(value);

      if (value == OLIRecorder.SESSION_STOPPED) {
        recorder.successCallback && recorder.successCallback();
      }
      break;

      case OLIRecorder.SESSION_ERROR :
      recorder.errorCallback && recorder.errorCallback(value);
      break;

      default :
      console.error && console.error("Unhandled OLIRecorder :: " + msgType);
      break;
    }
  } else {
    console.error && console.error("Received OLIRecorder callback for unknown recorderObject :: " + id);
    }

};

module.exports = OLIRecorder;
