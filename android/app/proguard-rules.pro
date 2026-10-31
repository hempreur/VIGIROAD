# ML Kit Text Recognition : les reconnaisseurs d'écritures non latines sont
# optionnels et absents de l'application ; R8 ne doit pas les exiger.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ONNX Runtime (mot d'activation « Sentrix ») : JNI.
-keep class ai.onnxruntime.** { *; }

# MapLibre (classes appelées par réflexion depuis le code natif).
-keep class org.maplibre.** { *; }
-dontwarn org.maplibre.**

# SQLCipher (JNI).
-keep class net.zetetic.** { *; }

# Lecture des plaques en release : la caméra (CameraX + plugin Flutter) et
# ML Kit passent par JNI, la réflexion et des registres de composants. Si R8
# renomme ou retire ces classes, l'analyse échoue sans planter l'application.
# On les conserve intégralement.
-keep class io.flutter.plugins.camerax.** { *; }
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.libraries.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.android.odml.**
# Cause constatée (logcat, APK release) : « NoSuchMethodException:
# com.google.mlkit.vision.text.internal.TextRegistrar.<init> » — les
# registres de composants sont instanciés par réflexion via le manifeste.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.firebase.components.** { *; }
