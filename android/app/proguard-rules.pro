# R8 / ProGuard rules for KamaiPlus POS
#
# Added because Play Console flagged the app: "No R8 metadata included",
# obfuscation 2%, shrinking blank. `isMinifyEnabled` and `isShrinkResources`
# were both explicitly false, so no shrinking or obfuscation ran at all, and
# Google warns that percentages under 25% "may impact your visibility and
# publishing capabilities on Google Play".
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE TOUCHING ANYTHING HERE
#
# R8 failures do NOT appear at build time. The AAB builds, installs and opens
# perfectly, and then one specific feature crashes the first time a real
# merchant uses it — because R8 renamed or removed a class that some library
# looks up by name at runtime. Payments, sign-in, notifications and background
# sync are the usual casualties, and they are exactly the things a shopkeeper
# cannot work around.
#
# So: every rule below exists for a named library that resolves something
# reflectively. If you add a plugin that uses reflection, a JNI callback, a
# @Keep annotation or a WebView JavascriptInterface, add its keep rule here AND
# test that feature on a release build before shipping.
# ---------------------------------------------------------------------------

# Disable aggressive multi-pass optimization to prevent R8 OutOfMemoryError on heap-constrained systems.
# Code shrinking, resource shrinking, and full obfuscation (name mangling) remain fully active.
-dontoptimize

# Keep annotations, signatures and line numbers. Line numbers cost almost
# nothing and are the difference between a readable Play Console crash report
# and an unusable one.
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Anything explicitly marked keep-worthy by AndroidX/Google.
-keep class androidx.annotation.Keep
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# ---------------------------------------------------------------------------
# Flutter engine + embedding
# ---------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ---------------------------------------------------------------------------
# Razorpay — the highest-risk dependency here.
#
# The SDK resolves the merchant's payment callback by METHOD NAME through a
# WebView JavascriptInterface. R8 renames those methods by default, the
# checkout sheet then opens, the customer pays, and the callback never fires —
# money leaves the customer's account and the app never records the sale.
# These are Razorpay's own published rules.
# ---------------------------------------------------------------------------
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}

# ---------------------------------------------------------------------------
# Firebase / Google Play Services
# ---------------------------------------------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firestore serializes model classes reflectively. This app writes its own
# toMap/fromMap, but the SDK's own internal models still need this.
-keepclassmembers class com.google.firebase.firestore.** { *; }

# FCM: the messaging service is resolved from the manifest by class name.
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService { *; }

# ---------------------------------------------------------------------------
# ML Kit (text recognition, Latin + Devanagari) — models are loaded by
# reflected class name, and a stripped one fails only when a merchant scans.
# ---------------------------------------------------------------------------
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }

# ---------------------------------------------------------------------------
# Local notifications — the plugin deserializes scheduled notifications from
# disk with Gson after a reboot, so its models must keep their field names or
# every scheduled reminder silently stops firing.
# ---------------------------------------------------------------------------
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-dontwarn com.dexterous.**

# Gson, used by the above.
-keepattributes AnnotationDefault
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn sun.misc.**

# ---------------------------------------------------------------------------
# WorkManager / background sync — the Dart callback dispatcher is looked up by
# name from a headless isolate. Lose it and background sync stops without any
# visible error.
# ---------------------------------------------------------------------------
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-dontwarn androidx.work.**

# ---------------------------------------------------------------------------
# Biometrics, camera/scanner, sign-in
# ---------------------------------------------------------------------------
-keep class androidx.biometric.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.journeyapps.barcodescanner.** { *; }
-keep class com.google.zxing.** { *; }
-dontwarn com.google.zxing.**

# ---------------------------------------------------------------------------
# Bluetooth thermal printing — the plugin talks to the platform channel with
# reflected method names.
# ---------------------------------------------------------------------------
-keep class com.android.** { *; }
-dontwarn android.bluetooth.**

# ---------------------------------------------------------------------------
# Kotlin coroutines / metadata
# ---------------------------------------------------------------------------
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ---------------------------------------------------------------------------
# Core library desugaring
# ---------------------------------------------------------------------------
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Native methods keep their names on both sides of the JNI boundary.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Enum valueOf/values are resolved reflectively by the platform.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable CREATOR fields are read by name.
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Serializable plumbing.
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
