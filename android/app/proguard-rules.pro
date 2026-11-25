# Keep flutter_rust_bridge JNI / FFI classes and native methods intact under R8.
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
