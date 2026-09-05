# Flutter ships its own default ProGuard/R8 rules via the Gradle plugin, so
# this file only needs project-specific keeps. For a standard Flutter + Firebase
# app, the defaults already cover Flutter, Firebase, and Play Core.
#
# Keep annotations and generic signatures (helps reflection-based libs).
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Firebase / Firestore models are accessed reflectively during (de)serialization.
# We don't use custom model classes with Firestore's toObject() (we map manually),
# but keeping these is cheap insurance against stripping something Firestore needs.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Suppress warnings for optional Play Core / deferred-components classes that
# Flutter references but which aren't bundled in a standard build.
-dontwarn com.google.android.play.core.**
