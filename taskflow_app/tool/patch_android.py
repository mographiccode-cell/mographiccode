from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')

permissions = '''\n    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />\n\n    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n    </queries>\n'''

if 'android.permission.RECORD_AUDIO' not in text:
    text = text.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">' + permissions)

receivers = '''\n        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON" />\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n            </intent-filter>\n        </receiver>\n'''

if 'ScheduledNotificationReceiver' not in text:
    text = text.replace('</application>', receivers + '\n    </application>')

manifest.write_text(text, encoding='utf-8')

gradle_kts = Path('android/app/build.gradle.kts')
if gradle_kts.exists():
    g = gradle_kts.read_text(encoding='utf-8')
    g = g.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g = g.replace(
            'compileOptions {\n        sourceCompatibility = JavaVersion.VERSION_17',
            'compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n        sourceCompatibility = JavaVersion.VERSION_17',
        )
    if 'multiDexEnabled = true' not in g:
        g = g.replace('defaultConfig {', 'defaultConfig {\n        multiDexEnabled = true', 1)
    if 'coreLibraryDesugaring(' not in g:
        g += '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    gradle_kts.write_text(g, encoding='utf-8')

strings = Path('android/app/src/main/res/values/strings.xml')
strings.parent.mkdir(parents=True, exist_ok=True)
strings.write_text('''<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="app_name">مهامي</string>\n</resources>\n''', encoding='utf-8')

text = manifest.read_text(encoding='utf-8')
text = text.replace('android:label="taskflow"', 'android:label="@string/app_name"')
manifest.write_text(text, encoding='utf-8')
