import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'backup_service.dart';

class BackupInspection {
  final Uint8List bytes;
  final String fileName;
  final int projects;
  final int deliverables;
  final int tasks;
  final int projectFiles;
  final int embeddedFiles;
  final int databaseVersion;

  const BackupInspection({
    required this.bytes,
    required this.fileName,
    required this.projects,
    required this.deliverables,
    required this.tasks,
    required this.projectFiles,
    required this.embeddedFiles,
    required this.databaseVersion,
  });

  bool get hasProjects => projects > 0;
}

class MigrationBackupService {
  MigrationBackupService._();
  static final MigrationBackupService instance = MigrationBackupService._();

  Future<BackupInspection?> pickAndInspectBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pobackup', 'zip'],
    );
    if (file == null) return null;

    final bytes = Uint8List.fromList(await file.readAsBytes());
    return inspectBytes(bytes, fileName: file.name);
  }

  Future<void> restoreInspection(BackupInspection inspection) {
    return BackupService.instance.restoreBytes(inspection.bytes);
  }

  Future<BackupInspection> inspectBytes(
    Uint8List bytes, {
    String fileName = 'ProjectDesk_Backup.pobackup',
  }) async {
    final decoded = ZipDecoder().decodeBytes(bytes, verify: true);
    ArchiveFile? dbEntry;
    var embeddedFiles = 0;

    for (final item in decoded) {
      if (item.name == 'database/project_organizer.db') {
        dbEntry = item;
      }
      if (item.isFile &&
          item.name.startsWith('project_files/') &&
          item.name != 'project_files/') {
        embeddedFiles++;
      }
    }

    if (dbEntry == null || !dbEntry.isFile) {
      throw Exception('الملف لا يحتوي قاعدة بيانات ProjectDesk صالحة');
    }

    final dbBytes = Uint8List.fromList(dbEntry.content);
    final signature =
        ascii.decode(dbBytes.take(16).toList(), allowInvalid: true);
    if (!signature.startsWith('SQLite format 3')) {
      throw Exception('قاعدة البيانات داخل النسخة غير صالحة');
    }

    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tempDb = File(p.join(temp.path, 'inspect_projectdesk_' +
        stamp.toString() +
        '.db'));
    await tempDb.writeAsBytes(dbBytes, flush: true);

    Database? check;
    try {
      check = await openDatabase(tempDb.path, readOnly: true);

      final tables = await check.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('projects','deliverables','tasks','project_files','settings')",
      );
      final names =
          tables.map((row) => row['name']).whereType<String>().toSet();
      const required = {
        'projects',
        'deliverables',
        'tasks',
        'project_files',
        'settings'
      };
      if (!names.containsAll(required)) {
        throw Exception('النسخة لا تحتوي جداول ProjectDesk المطلوبة');
      }

      final integrity = await check.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw Exception('فحص سلامة قاعدة البيانات لم ينجح');
      }

      Future<int> count(String table) async {
        final rows =
            await check!.rawQuery('SELECT COUNT(*) AS c FROM ' + table);
        return Sqflite.firstIntValue(rows) ?? 0;
      }

      final versionRows = await check.rawQuery('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? 0
          : ((versionRows.first.values.first as num?)?.toInt() ?? 0);

      return BackupInspection(
        bytes: bytes,
        fileName: fileName,
        projects: await count('projects'),
        deliverables: await count('deliverables'),
        tasks: await count('tasks'),
        projectFiles: await count('project_files'),
        embeddedFiles: embeddedFiles,
        databaseVersion: version,
      );
    } finally {
      await check?.close();
      if (await tempDb.exists()) {
        await tempDb.delete();
      }
    }
  }
}
