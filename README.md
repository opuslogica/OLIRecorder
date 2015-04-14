OLIRecorder
=========

Opus Logica Recorder for iOS
---------------------------
ionic plugin add https://github.com/opuslogica/OLIRecorder.git

recorder = new OLIRecorder(function perFileFunc(file) {});

recorder.create_meter(left, top, width, height);

recorder.start();
recorder.pause();
recorder.stop();
recorder.destroy();

recorder.destroy_meter();
