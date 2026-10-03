package com.corplex.corplex

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (a FlutterActivity) shares the Flutter engine with
// the background audio service, so playback survives the app going away.
class MainActivity : AudioServiceActivity()
