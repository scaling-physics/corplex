package com.corplex.corplex

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceActivity (a FlutterActivity) shares the Flutter engine with
// the background audio service, so playback survives the app going away.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OcrChannel.register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
