import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OutputManager {
  static Future<Directory> getOutputDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(documents.path, 'Student Mail Merge', 'Final Files'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String timestampName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static Future<List<File>> listOutputFiles() async {
    final dir = await getOutputDirectory();
    final files = <File>[];

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext == '.docx') {
        files.add(entity);
      }
    }

    files.sort((a, b) {
      final aTime = a.lastModifiedSync();
      final bTime = b.lastModifiedSync();
      return bTime.compareTo(aTime);
    });

    return files;
  }

  static Future<void> openFolder() async {
    final dir = await getOutputDirectory();
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir.path]);
    }
  }
}
