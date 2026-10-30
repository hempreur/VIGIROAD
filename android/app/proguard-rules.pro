# ML Kit Text Recognition : les reconnaisseurs d'écritures non latines sont
# optionnels et absents de l'application ; R8 ne doit pas les exiger.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# MapLibre (classes appelées par réflexion depuis le code natif).
-keep class org.maplibre.** { *; }
-dontwarn org.maplibre.**

# SQLCipher (JNI).
-keep class net.zetetic.** { *; }
