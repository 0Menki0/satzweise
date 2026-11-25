# Garmin Connect IQ: Klassen werden per Name mit der Garmin-Connect-App
# ausgetauscht und dürfen im Release-Build nicht umbenannt werden.
-keep class com.garmin.** { *; }
-dontwarn com.garmin.**
