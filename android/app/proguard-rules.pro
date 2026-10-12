# ML Kit finds its components by class name at runtime (the registrars
# named in the merged manifest). R8 renamed/stripped them in release
# builds, so TextRecognition.getClient() crashed MainActivity at launch
# (1.5.0). Keep ML Kit and its Play-services internals intact.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.firebase.components.** { *; }
