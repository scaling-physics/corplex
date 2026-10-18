package com.corplex.corplex

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Read aloud (`corplex/speak`) with Android's `TextToSpeech`. The engine is
 * created on the first `speak`, never at registration (a failure at
 * registration would crash the app at launch); requests that arrive before
 * it is ready are queued. Utterances queue natively; each reports `done`
 * (finished true, or false when cut off by `stop`).
 *
 * Android's TTS has no pause, so `pause` stops after the current utterance's
 * position is lost: the sentence is spoken again from its start on `resume`.
 */
class SpeakChannel(private val context: Context, messenger: BinaryMessenger) {
    private class Request(val id: Int, val text: String, val rate: Float, val language: String?)

    private val channel = MethodChannel(messenger, "corplex/speak")
    private var tts: TextToSpeech? = null
    private var ready = false
    private var failed = false
    private val waiting = ArrayList<Request>()

    // Everything handed to the engine and not yet reported, in order.
    private val active = ArrayList<Request>()
    private var paused = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val id = call.argument<Int>("id")
                    val text = call.argument<String>("text")
                    if (id == null || text == null) {
                        result.error("bad_args", "Expected id and text", null)
                        return@setMethodCallHandler
                    }
                    val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    val request = Request(id, text, rate, call.argument<String>("language"))
                    if (!ensureEngine()) {
                        result.error("tts_unavailable", "Text to speech is unavailable", null)
                        return@setMethodCallHandler
                    }
                    active.add(request)
                    if (ready && !paused) enqueue(request) else if (!ready) waiting.add(request)
                    result.success(null)
                }
                "pause" -> {
                    paused = true
                    tts?.stop()
                    result.success(null)
                }
                "resume" -> {
                    if (paused) {
                        paused = false
                        // Speak again what was cut off, from its start.
                        if (ready) active.forEach { enqueue(it) }
                    }
                    result.success(null)
                }
                "stop" -> {
                    paused = false
                    waiting.clear()
                    tts?.stop()
                    val dropped = ArrayList(active)
                    active.clear()
                    dropped.forEach { report(it.id, false) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureEngine(): Boolean {
        if (tts != null) return !failed
        if (failed) return false
        try {
            tts = TextToSpeech(context.applicationContext) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    ready = true
                    tts?.setOnUtteranceProgressListener(listener)
                    val pending = ArrayList(waiting)
                    waiting.clear()
                    if (!paused) pending.forEach { enqueue(it) }
                } else {
                    failed = true
                    val dropped = ArrayList(active)
                    active.clear()
                    waiting.clear()
                    dropped.forEach { report(it.id, false) }
                }
            }
        } catch (e: Exception) {
            failed = true
            return false
        }
        return true
    }

    private fun enqueue(request: Request) {
        val engine = tts ?: return
        if (request.language != null) {
            val result = engine.setLanguage(Locale.forLanguageTag(request.language))
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                engine.language = Locale.getDefault()
            }
        } else {
            engine.language = Locale.getDefault()
        }
        engine.setSpeechRate(request.rate)
        val status = engine.speak(request.text, TextToSpeech.QUEUE_ADD, Bundle(), request.id.toString())
        if (status != TextToSpeech.SUCCESS) {
            active.remove(request)
            report(request.id, false)
        }
    }

    private fun report(id: Int, finished: Boolean) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("done", mapOf("id" to id, "finished" to finished))
        }
    }

    private val listener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {}

        override fun onDone(utteranceId: String?) {
            val id = utteranceId?.toIntOrNull() ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (active.removeAll { it.id == id }) report(id, true)
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            val id = utteranceId?.toIntOrNull() ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (active.removeAll { it.id == id }) report(id, false)
            }
        }

        // stop() ends utterances through onStop; stop/pause already account
        // for them, so a pause is not reported as a cut-off.
        override fun onStop(utteranceId: String?, interrupted: Boolean) {}
    }
}
