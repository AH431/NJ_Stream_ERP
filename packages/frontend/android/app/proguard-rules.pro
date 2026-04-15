# Flutter & Dart obfuscation rules
# Flutter 本身的 keep rules 由 flutter.gradle 自動注入，這裡只補充 plugin 層級的需求

# flutter_secure_storage — 保留 JNI/KeyStore 相關類別
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Drift (sqlite3_flutter_libs) — 保留原生 SQLite 綁定
-keep class com.simolus.** { *; }
-keep class io.requery.android.database.** { *; }

# 保留 Parcelable 實作（Android 系統需要）
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# 移除 debug log（生產環境清除 Log.d / Log.v）
-assumenosideeffects class android.util.Log {
    public static int d(...);
    public static int v(...);
}
