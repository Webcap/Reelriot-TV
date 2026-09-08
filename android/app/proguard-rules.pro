# Flutter Core Keep Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# MediaKit / Native C++ JNI Keep Rules
-keep class com.alexmercerind.mediakit.** { *; }
-keepclassmembers class com.alexmercerind.mediakit.** { *; }
-dontwarn com.alexmercerind.mediakit.**

# StartApp SDK Keep Rules
-keep class com.startapp.** { *; }
-dontwarn com.startapp.**

# Supabase / Networking Keep Rules
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Android TV / Leanback Keep Rules
-keep class androidx.leanback.** { *; }
-dontwarn androidx.leanback.**
