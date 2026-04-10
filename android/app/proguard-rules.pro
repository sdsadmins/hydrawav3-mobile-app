# Stripe / R8 rules
# Some Stripe modules (e.g., push provisioning) are optional. R8 can see references
# from included SDK code paths and fail the build if it can’t resolve them.
-keep class com.stripe.** { *; }
-dontwarn com.stripe.**

# If any transitive artifact references React Native Stripe symbols, ignore warnings.
-dontwarn com.reactnativestripesdk.**

