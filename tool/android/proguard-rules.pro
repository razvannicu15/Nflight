# flutter_local_notifications stores scheduled notifications with Gson; R8 must keep
# the generic type info, otherwise cancel/schedule fail in release ("Missing type parameter").
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
