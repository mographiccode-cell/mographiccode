from pathlib import Path
import base64
import io
import zipfile

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

# Install the custom launcher icon generated for this app.
icon_archive = Path('tool/launcher_icons_webp.zip.b64')
if icon_archive.exists():
    raw = base64.b64decode(icon_archive.read_text(encoding='ascii'))
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        for member in zf.namelist():
            out = Path('android/app/src/main/res') / member
            out.parent.mkdir(parents=True, exist_ok=True)
            old_png = out.with_suffix('.png')
            if old_png.exists():
                old_png.unlink()
            out.write_bytes(zf.read(member))

# Add the developer signature to the bottom of the home screen.
dart_main = Path('lib/main.dart')
if dart_main.exists():
    d = dart_main.read_text(encoding='utf-8')
    signature = 'تصميم وبرمجة م.محمود دغَبس — 74813824'
    if signature not in d:
        needle = """              _UpcomingList(
                tasks: widget.store.tasks
                    .where((e) => !e.completed)
                    .toList()
                  ..sort((a, b) {
                    if (a.dueAt == null && b.dueAt == null) {
                      return b.createdAt.compareTo(a.createdAt);
                    }
                    if (a.dueAt == null) return 1;
                    if (b.dueAt == null) return -1;
                    return a.dueAt!.compareTo(b.dueAt!);
                  }),
                store: widget.store,
                onOpen: _openEditor,
              ),
"""
        footer = needle + """              const SizedBox(height: 28),
              const Center(
                child: Text(
                  'تصميم وبرمجة م.محمود دغَبس — 74813824',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
              const SizedBox(height: 8),
"""
        if needle in d:
            d = d.replace(needle, footer, 1)
            dart_main.write_text(d, encoding='utf-8')
