import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class PrivacyDatabase {
  Database? _database;

  Future<Database> get db async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;

    final root = await getDatabasesPath();
    final path = p.join(root, 'privacy_shield.db');
    try {
      _database = await _open(path);
    } catch (_) {
      // Native PolicyStore/DPM is the security source of truth. This database
      // stores only cache/audit data, so corruption must never prevent startup.
      await deleteDatabase(path);
      _database = await _open(path);
    }
    return _database!;
  }

  Future<Database> _open(String path) => openDatabase(
        path,
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA journal_mode=WAL');
          await database.execute('PRAGMA synchronous=NORMAL');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE policies(
              package_name TEXT PRIMARY KEY,
              label TEXT NOT NULL,
              camera_blocked INTEGER NOT NULL DEFAULT 0,
              microphone_blocked INTEGER NOT NULL DEFAULT 0,
              location_blocked INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE events(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER NOT NULL,
              action TEXT NOT NULL,
              package_name TEXT,
              app_label TEXT,
              sensor TEXT,
              details TEXT
            )
          ''');
          await database.execute(
            'CREATE INDEX events_timestamp_idx ON events(timestamp DESC)',
          );
        },
      );

  Future<Map<String, AppPolicy>> loadPolicies() async {
    final database = await db;
    final rows = await database.query('policies');
    return <String, AppPolicy>{
      for (final row in rows)
        row['package_name']! as String: AppPolicy(
          packageName: row['package_name']! as String,
          label: row['label']! as String,
          cameraBlocked: row['camera_blocked'] == 1,
          microphoneBlocked: row['microphone_blocked'] == 1,
          locationBlocked: row['location_blocked'] == 1,
        ),
    };
  }

  Future<void> savePolicy(AppPolicy policy) async {
    final database = await db;
    await database.insert(
      'policies',
      <String, Object>{
        'package_name': policy.packageName,
        'label': policy.label,
        'camera_blocked': policy.cameraBlocked ? 1 : 0,
        'microphone_blocked': policy.microphoneBlocked ? 1 : 0,
        'location_blocked': policy.locationBlocked ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addEvent({
    required String action,
    String? packageName,
    String? appLabel,
    String? sensor,
    String? details,
  }) async {
    final database = await db;
    await database.insert('events', <String, Object?>{
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'action': action,
      'package_name': packageName,
      'app_label': appLabel,
      'sensor': sensor,
      'details': details,
    });
  }

  Future<List<AuditEvent>> loadEvents({int limit = 150}) async {
    final database = await db;
    final rows = await database.query(
      'events',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => AuditEvent(
            id: row['id']! as int,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              row['timestamp']! as int,
            ),
            action: row['action']! as String,
            packageName: row['package_name'] as String?,
            appLabel: row['app_label'] as String?,
            sensor: row['sensor'] as String?,
            details: row['details'] as String?,
          ),
        )
        .toList();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
