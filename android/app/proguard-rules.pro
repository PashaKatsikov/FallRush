# Flutter engine + plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase — keep aggressively. firebase-messaging,
# firebase-installations и firebase-iid рефлексят на собственные
# service-классы (FirebaseMessagingService, FirebaseInstallationsApi,
# RegistrarImpl). Если R8 их вычищает — токен не выпускается, install
# не регистрируется, и FCM Console отвечает «Application install not
# found».
-keep class com.google.firebase.**             { *; }
-keep class com.google.firebase.iid.**         { *; }
-keep class com.google.firebase.installations.** { *; }
-keep class com.google.firebase.messaging.**   { *; }
-keep class com.google.firebase.components.**  { *; }
-keep interface com.google.firebase.**         { *; }
-keep class com.google.android.gms.**          { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# google-services plugin генерирует стабильный список ComponentRegistrar
# на этапе компиляции — R8 не должен их стирать.
-keepnames class * extends com.google.firebase.components.ComponentRegistrar

# AppsFlyer
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# WebView plugin
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Play Core (deferred components — unused but referenced by Flutter)
-dontwarn com.google.android.play.core.**

# Native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Strip android.util.Log calls in release builds
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
