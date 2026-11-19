# Razorpay checkout
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
-dontwarn proguard.annotation.Keep
-dontwarn proguard.annotation.KeepClassMembers
# Optional Google Pay client referenced by the Razorpay SDK.
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.**

# Flutter deferred components (Play Core) are not used by this app.
-dontwarn com.google.android.play.core.**

# Compile-time annotations referenced by Google libraries (not needed at run time).
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
