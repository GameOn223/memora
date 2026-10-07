# R8 runs on release builds. These are the things it must not rename.
#
# The symptom when it does is not a missing class, it is a crash from inside
# a library at the moment it reads one of its own fields by name:
#
#   Field modelPath_ for xy not found. Known fields are
#   [public fu xy.j, public static final xy xy.k, ...]
#
# which is MediaPipe asking protobuf for modelPath_ after R8 renamed it to j.

# Protobuf lite reads and writes generated message fields reflectively, by
# the exact `name_` the generator produced. Renaming any of them breaks
# every message that holds one, which is how MediaPipe is configured.
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
  <fields>;
}
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite$Builder {
  <fields>;
}
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# The LLM Inference API and the MPImage types the vision path hands it.
# These cross into native code, which looks them up by name, so neither the
# classes nor their members can move.
-keep class com.google.mediapipe.tasks.genai.** { *; }
-keep class com.google.mediapipe.framework.image.** { *; }
-keep class com.google.mediapipe.proto.** { *; }
-keep class com.google.mediapipe.tasks.core.** { *; }
-dontwarn com.google.mediapipe.**

# AutoValue builders behind the MPImage types.
-keepclassmembers class com.google.mediapipe.** {
  <init>(...);
}

# ONNX Runtime, for on-device embeddings. Same story: JNI by name.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Anything reached only from native code. Flutter's own rules cover the
# engine and the plugins.
-keepclasseswithmembernames class * {
  native <methods>;
}
