# Flutter Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Supabase and other potential reflection-heavy libs
-keep class com.supabase.** { *; }
-keep class org.postgresql.** { *; }

# Preserve GSON/JSON models if needed
-keepclassmembers class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Fix for Missing classes detected while running R8 (Play Core)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

