package com.corplex.corplex

import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * On-device OCR (`corplex/ocr`) with ML Kit's bundled Latin model. Returns
 * lines with word boxes as fractions of the image, origin top-left.
 */
object OcrChannel {
    fun register(messenger: BinaryMessenger) {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        MethodChannel(messenger, "corplex/ocr").setMethodCallHandler { call, result ->
            if (call.method != "recognize") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("image")
            val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (bitmap == null) {
                result.error("bad_args", "Expected PNG bytes", null)
                return@setMethodCallHandler
            }
            val w = bitmap.width.toDouble()
            val h = bitmap.height.toDouble()
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { text ->
                    val lines = ArrayList<Map<String, Any>>()
                    for (block in text.textBlocks) {
                        for (line in block.lines) {
                            val words = ArrayList<Map<String, Any>>()
                            for (el in line.elements) {
                                val b = el.boundingBox ?: continue
                                words.add(
                                    mapOf(
                                        "text" to el.text,
                                        "left" to b.left / w,
                                        "top" to b.top / h,
                                        "right" to b.right / w,
                                        "bottom" to b.bottom / h,
                                    )
                                )
                            }
                            lines.add(mapOf("text" to line.text, "words" to words))
                        }
                    }
                    bitmap.recycle()
                    result.success(lines)
                }
                .addOnFailureListener { e ->
                    bitmap.recycle()
                    result.error("ocr_failed", e.message, null)
                }
        }
    }
}
