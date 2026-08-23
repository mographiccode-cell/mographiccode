import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/app_database.dart';
import '../models/domain.dart';

class AuthService {
  AuthService(this.database);
  final AppDatabase database;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  static const _sessionKey = 'current_user_id';

  static const demoName = 'مستخدم تجريبي';
  static const demoEmail = 'demo@smartshipping.sa';
  static const demoPassword = 'Demo@12345';

  Future<void> ensureDefaultAccount() async {
    final existing = await database.db.query(
      'users',
      where: 'email = ?',
      whereArgs: [demoEmail],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final salt = _randomSalt();
    final hash = _derivePassword(demoPassword, salt);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await database.db.insert('users', {
      'full_name': demoName,
      'email': demoEmail,
      'password_hash': hash,
      'password_salt': salt,
      'created_at': now,
    });
    await database.db.insert('user_preferences', {
      'user_id': id,
      'profile': 'balanced',
      'updated_at': now,
    });
  }

  Future<AppUser?> restoreSession() async {
    final raw = await _secure.read(key: _sessionKey);
    if (raw == null) return null;
    final id = int.tryParse(raw);
    if (id == null) return null;
    final rows = await database.db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _secure.delete(key: _sessionKey);
      return null;
    }
    return AppUser.fromMap(rows.first);
  }

  Future<AppUser> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized)) {
      throw const AuthException('البريد الإلكتروني غير صالح.');
    }
    if (fullName.trim().length < 2) {
      throw const AuthException('أدخل الاسم الكامل.');
    }
    if (password.length < 8) {
      throw const AuthException('كلمة المرور يجب أن تكون 8 أحرف على الأقل.');
    }

    final existing = await database.db.query(
      'users',
      where: 'email = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw const AuthException('يوجد حساب بهذا البريد بالفعل.');
    }

    final salt = _randomSalt();
    final hash = _derivePassword(password, salt);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await database.db.insert('users', {
      'full_name': fullName.trim(),
      'email': normalized,
      'password_hash': hash,
      'password_salt': salt,
      'created_at': now,
    });
    await database.db.insert('user_preferences', {
      'user_id': id,
      'profile': 'balanced',
      'updated_at': now,
    });
    await _secure.write(key: _sessionKey, value: '$id');
    return AppUser(
      id: id,
      fullName: fullName.trim(),
      email: normalized,
    );
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    final rows = await database.db.query(
      'users',
      where: 'email = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AuthException('البريد أو كلمة المرور غير صحيحة.');
    }
    final row = rows.first;
    final expected = row['password_hash'] as String;
    final salt = row['password_salt'] as String;
    final actual = _derivePassword(password, salt);
    if (!_constantTimeEquals(expected, actual)) {
      throw const AuthException('البريد أو كلمة المرور غير صحيحة.');
    }
    final user = AppUser.fromMap(row);
    await _secure.write(key: _sessionKey, value: '${user.id}');
    return user;
  }

  Future<void> logout() => _secure.delete(key: _sessionKey);

  bool _validEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _derivePassword(String password, String salt) {
    var bytes = utf8.encode('$salt:$password');
    for (var i = 0; i < 40000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64UrlEncode(bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    final aa = utf8.encode(a);
    final bb = utf8.encode(b);
    if (aa.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < aa.length; i++) {
      diff |= aa[i] ^ bb[i];
    }
    return diff == 0;
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
