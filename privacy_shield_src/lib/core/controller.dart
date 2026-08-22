import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'database.dart';
import 'models.dart';
import 'native_bridge.dart';

class PrivacyController extends ChangeNotifier {
  PrivacyController({PrivacyDatabase? database, NativeBridge? bridge})
      : database = database ?? PrivacyDatabase(),
        bridge = bridge ?? NativeBridge();

  final PrivacyDatabase database;
  final NativeBridge bridge;
  NativeStatus status = const NativeStatus();
  List<ManagedApp> apps = <ManagedApp>[];
  Map<String, AppPolicy> policies = <String, AppPolicy>{};
  List<ActiveSession> sessions = <ActiveSession>[];
  List<AuditEvent> events = <AuditEvent>[];
  Map<String, int> trackerStats = <String, int>{};
  bool loading = true;
  bool busy = false;
  String? error;
  Timer? _timer;

  Future<void> initialize() async {
    try {
      policies = await database.loadPolicies();
      await refreshAll();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refreshSessions()),
      );
    } catch (e) {
      error = _friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
    error = null;
    try {
      status = await bridge.getStatus();
      apps = await bridge.listApps();
      if (status.isDeviceOwner) {
        await _syncNativePolicies();
      }
      sessions = await bridge.getActiveSessions();
      events = await database.loadEvents();
      trackerStats = await bridge.trackerStats();
    } catch (e) {
      error = _friendlyError(e);
    }
    notifyListeners();
  }

  Future<void> refreshSessions() async {
    try {
      sessions = await bridge.getActiveSessions();
      notifyListeners();
    } catch (_) {
      // Security expiry is enforced natively; a transient UI read failure must
      // not alter the native permission state.
    }
  }

  Future<void> _syncNativePolicies() async {
    final native = await bridge.getBlockedPolicies();
    for (final app in apps) {
      final policy = policyFor(app);
      policy.label = app.label;
      for (final sensor in SensorType.values) {
        policy.setBlocked(
          sensor,
          native[app.packageName]?.contains(sensor) ?? false,
        );
      }
      try {
        await database.savePolicy(policy);
      } catch (_) {
        // Native DPC state is authoritative; SQLite is only a local cache.
      }
    }
  }

  AppPolicy policyFor(ManagedApp app) => policies.putIfAbsent(
        app.packageName,
        () => AppPolicy(packageName: app.packageName, label: app.label),
      );

  bool isBlocked(ManagedApp app, SensorType sensor) =>
      policyFor(app).blocked(sensor);

  ActiveSession? sessionFor(String packageName, SensorType sensor) {
    for (final session in sessions) {
      if (session.packageName == packageName && session.sensor == sensor) {
        return session;
      }
    }
    return null;
  }

  Future<void> setBlocked(
    ManagedApp app,
    SensorType sensor,
    bool blocked,
  ) async {
    if (!status.isDeviceOwner) {
      throw StateError('يلزم تفعيل وضع Device Owner لفرض السياسة فعليًا.');
    }
    await _runBusy(() async {
      await bridge.setBlocked(app.packageName, sensor, blocked);
      final policy = policyFor(app);
      policy.setBlocked(sensor, blocked);
      policy.label = app.label;
      try {
        await database.savePolicy(policy);
        await database.addEvent(
          action: blocked ? 'BLOCKED' : 'DEFAULT',
          packageName: app.packageName,
          appLabel: app.label,
          sensor: sensor.wire,
        );
      } catch (_) {
        // DPC/PolicyStore is the source of truth. A cache/audit write failure
        // must never roll back a successfully enforced Android policy.
      }
      await refreshAll();
    });
  }

  Future<void> grantTemporary(ManagedApp app, SensorType sensor) async {
    if (!status.fullProtectionReady) {
      throw StateError('الفتح المؤقت يحتاج Device Owner وصلاحية Exact Alarm.');
    }
    if (!isBlocked(app, sensor)) {
      throw StateError('فعّل الحماية لهذا الحساس أولًا، ثم استخدم الفتح المؤقت.');
    }
    await _runBusy(() async {
      await bridge.temporaryGrant(app.packageName, sensor);
      try {
        await database.addEvent(
          action: 'TEMPORARY_GRANT',
          packageName: app.packageName,
          appLabel: app.label,
          sensor: sensor.wire,
          details: '120 seconds',
        );
      } catch (_) {
        // Audit persistence must not invalidate a natively secured session.
      }
      await refreshSessions();
      await bridge.launchApp(app.packageName);
    });
  }

  Future<void> revokeNow(ManagedApp app, SensorType sensor) async {
    await _runBusy(() async {
      await bridge.revokeNow(app.packageName, sensor);
      await database.addEvent(
        action: 'REVOKED_NOW',
        packageName: app.packageName,
        appLabel: app.label,
        sensor: sensor.wire,
      );
      await refreshAll();
    });
  }

  Future<void> setPanic(bool enabled) async {
    await _runBusy(() async {
      await bridge.setPanic(enabled);
      await database.addEvent(action: enabled ? 'PANIC_ON' : 'PANIC_OFF');
      await refreshAll();
    });
  }

  Future<void> protectAllSensitiveApps() async {
    if (!status.isDeviceOwner) {
      throw StateError('يلزم Device Owner.');
    }
    await _runBusy(() async {
      final failures = <String>[];
      for (final app in apps.where((a) => !a.systemApp)) {
        for (final sensor in SensorType.values) {
          if (!app.supports(sensor)) {
            continue;
          }
          try {
            await bridge.setBlocked(app.packageName, sensor, true);
          } catch (_) {
            failures.add('${app.label} - ${sensor.arLabel}');
          }
        }
      }
      await refreshAll();
      try {
        await database.addEvent(
          action: 'PROTECT_ALL',
          details:
              failures.isEmpty ? 'all enforced' : 'failures=${failures.length}',
        );
      } catch (_) {}
      if (failures.isNotEmpty) {
        throw StateError(
          'تم تطبيق الحماية قدر الإمكان، وتعذر فرض ${failures.length} سياسة: ${failures.take(5).join('، ')}',
        );
      }
    });
  }

  Future<void> repairPolicies() async {
    await _runBusy(() async {
      final repaired = await bridge.repairPolicies();
      await database.addEvent(
        action: 'REPAIR',
        details: '$repaired policy entries',
      );
      await refreshAll();
    });
  }

  Future<void> toggleNetworkShield(bool enabled) async {
    await _runBusy(() async {
      if (enabled) {
        final started = await bridge.startNetworkShield();
        if (!started) {
          throw StateError(
            'وافق على طلب VPN من Android ثم اضغط التفعيل مرة أخرى.',
          );
        }
      } else {
        await bridge.stopNetworkShield();
      }
      await database.addEvent(action: enabled ? 'NETWORK_ON' : 'NETWORK_OFF');
      await refreshAll();
    });
  }

  Future<void> openExactAlarmSettings() => bridge.openExactAlarmSettings();
  Future<void> openPrivacySettings() => bridge.openPrivacySettings();

  int blockedCount(SensorType sensor) =>
      apps.where((app) => isBlocked(app, sensor)).length;

  Future<void> _runBusy(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = _friendlyError(e);
      notifyListeners();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      return error.message ?? error.code;
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(database.close());
    super.dispose();
  }
}
