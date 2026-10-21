package com.corplex.corplex

import com.ryanheise.audioservice.AudioServiceFragmentActivity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceFragmentActivity (a FlutterFragmentActivity, which local_auth's
// biometric prompt requires) shares the Flutter engine with
// the background audio service, so playback survives the app going away.
class MainActivity : AudioServiceFragmentActivity() {
    private var speak: SpeakChannel? = null
    private var reminders: RemindersChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OcrChannel.register(flutterEngine.dartExecutor.binaryMessenger)
        speak = SpeakChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        reminders = RemindersChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        reminders?.let { r -> intent?.getStringExtra("reminderNote")?.let { r.opened(it) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("reminderNote")?.let { reminders?.opened(it) }
    }
}
