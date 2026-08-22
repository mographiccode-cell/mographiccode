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
  SetupDiagnostics? setupDiagnostics;
  List<ManagedApp> apps = <ManagedApp>[];
  Map<String, AppPolicy> policies = <String, AppPolicy>{};
  List<ActiveSession> sessions = <ActiveSession>[];
  List<AuditEvent> events = <AuditEvent>[];
  Map<String, int> trackerStats = <String, int>{};

  bool loading = true;
  bool busy = false;
  String? error;
  String? auditWarning;
  Timer? _timer;

  Future<void> initialize() async {
    try {
      try {
        policies = await database.loadPolicies();
      } catch (e) {
        auditWarning = 'تعذر فتح قاعدة السجل المحلية، لكن الحماية Native ستستمر: ${_friendlyError(e)}';
      }
      await refreshAll();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (sessions.isNotEmpty) unawaited(refreshSessions());
      });
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
      setupDiagnostics = await bridge.getSetupDiagnostics();
      apps = await bridge.listApps();

      if (status.isDeviceOwner) {
        await _syncNativePolicies();
      } else {
        _clearUnenforcedPolicyView();
      }

      sessions = await bridge.getActiveSessions();
      trackerStats = await bridge.trackerStats();
    } catch (e) {
      error = _friendlyError(e);
    }

    try {
      events = await database.loadEvents();
    } catch (e) {
      auditWarning = 'سجل التدقيق المحلي غير متاح: ${_friendlyError(e)}';
    }
    notifyListeners();
  }

  Future<void> refreshSessions() async {
    try {
      sessions = await bridge.getActiveSessions();
      status = await bridge.getStatus();
      notifyListeners();
    } catch (_) {
      // Android alarms + foreground watchdog enforce expiry independently of UI.
    }
  }

  Future<void> _syncNativePolicies() async {
    final native = await bridge.getBlockedPolicies();
    for (final app in apps) {
      final policy = policyFor(app);
      policy.label = app.label;
      for (final sensor in SensorType.values) {
        policy.setBlocked(sensor, native[app.packageName]?.contains(sensor) ?? false);
      }
      await _savePolicyBestEffort(policy);
    }
  }

  void _clearUnenforcedPolicyView() {
    for (final app in apps) {
      final policy = policyFor(app);
      policy.label = app.label;
      for (final sensor in SensorType.values) {
        policy.setBlocked(sensor, false);
      }
    }
    sessions = <ActiveSession>[];
  }

  AppPolicy policyFor(ManagedApp app) => policies.putIfAbsent(
        app.packageName,
        () => AppPolicy(packageName: app.packageName, label: app.label),
      );

  bool isBlocked(ManagedApp app, SensorType sensor) => policyFor(app).blocked(sensor);

  ActiveSession? sessionFor(String packageName, SensorType sensor) {
    for (final session in sessions) {
      if (session.packageName == packageName && session.sensor == sensor) return session;
    }
    return null;
  }

  Future<void> setBlocked(ManagedApp app, SensorType sensor, bool blocked) async {
    if (!status.isDeviceOwner) {
      throw StateError('يلزم Device Owner لفرض المنع على التطبيقات الأخرى.');
    }
    if (app.criticalSystem && blocked) {
      throw StateError('هذا مكوّن نظام حرج؛ الحظر اليدوي معطّل لتجنب تعطيل الهاتف.');
    }

    await _runBusy(() async {
      await bridge.setBlocked(app.packageName, sensor, blocked);
      await refreshAll();
      await _audit(
        action: blocked ? 'BLOCKED' : 'DEFAULT',
        packageName: app.packageName,
        appLabel: app.label,
        sensor: sensor.wire,
      );
    });
  }

  Future<void> grantTemporary(
    ManagedApp app,
    SensorType sensor, {
    int durationMs = 120000,
  }) async {
    if (!status.fullProtectionReady) {
      throw StateError('الفتح المؤقت يحتاج Device Owner يسمح بإدارة صلاحيات الحساسات.');
    }
    if (!isBlocked(app, sensor)) {
      throw StateError('فعّل الحماية لهذا الحساس أولًا، ثم استخدم الفتح المؤقت.');
    }
    if (status.panicEnabled) {
      throw StateError('ألغِ Panic Lock أولًا.');
    }

    await _runBusy(() async {
      await bridge.temporaryGrant(app.packageName, sensor, durationMs: durationMs);
      await refreshSessions();
      await _audit(
        action: 'TEMPORARY_GRANT',
        packageName: app.packageName,
        appLabel: app.label,
        sensor: sensor.wire,
        details: '$durationMs ms',
      );
      final launched = await bridge.launchApp(app.packageName);
      if (!launched) {
        await bridge.revokeNow(app.packageName, sensor);
        await refreshAll();
        throw StateError('تعذر فتح التطبيق المستهدف؛ تم سحب الإذن فورًا للأمان.');
      }
    });
  }

  Future<void> revokeNow(ManagedApp app, SensorType sensor) async {
    await _runBusy(() async {
      await bridge.revokeNow(app.packageName, sensor);
      await refreshAll();
      await _audit(
        action: 'REVOKED_NOW',
        packageName: app.packageName,
        appLabel: app.label,
        sensor: sensor.wire,
      );
    });
  }

  Future<void> setPanic(bool enabled) async {
    await _runBusy(() async {
      await bridge.setPanic(enabled);
      await refreshAll();
      await _audit(action: enabled ? 'PANIC_ON' : 'PANIC_OFF');
    });
  }

  Future<void> protectAllSensitiveApps() async {
    if (!status.isDeviceOwner) throw StateError('يلزم Device Owner.');

    await _runBusy(() async {
      final failures = <String>[];
      var changed = 0;
      final targets = apps.where((app) => app.enabled && !app.criticalSystem);
      for (final app in targets) {
        for (final sensor in SensorType.values) {
          if (!app.supports(sensor)) continue;
          try {
            await bridge.setBlocked(app.packageName, sensor, true);
            changed++;
          } catch (_) {
            failures.add('${app.label} - ${sensor.arLabel}');
          }
        }
      }
      await refreshAll();
      await _audit(
        action: 'PROTECT_ALL',
        details: 'changed=$changed failures=${failures.length}',
      );
      if (failures.isNotEmpty) {
        throw StateError(
          'تم فرض $changed سياسة، وتعذر ${failures.length}: ${failures.take(5).join('، ')}',
        );
      }
    });
  }

  Future<void> repairPolicies() async {
    await _runBusy(() async {
      final repaired = await bridge.repairPolicies();
      await refreshAll();
      await _audit(action: 'REPAIR', details: '$repaired policy entries');
    });
  }

  Future<void> toggleNetworkShield(bool enabled) async {
    await _runBusy(() async {
      if (enabled) {
        if (status.otherVpnActive && !status.networkShieldEnabled) {
          throw StateError('يوجد VPN آخر فعال. أوقفه أولًا حتى لا يتم قطع اتصاله.');
        }
        final started = await bridge.startNetworkShield();
        if (!started) {
          throw StateError('وافق على طلب VPN من Android، ثم ارجع للتطبيق واضغط التفعيل.');
        }
      } else {
        await bridge.stopNetworkShield();
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refreshAll();
      await _audit(action: enabled ? 'NETWORK_ON' : 'NETWORK_OFF');
    });
  }

  Future<void> openExactAlarmSettings() => bridge.openExactAlarmSettings();
  Future<void> openPrivacySettings() => bridge.openPrivacySettings();
  Future<void> openDeviceAdminSettings() => bridge.openDeviceAdminSettings();

  int blockedCount(SensorType sensor) => apps.where((app) => isBlocked(app, sensor)).length;

  int get protectableAppCount => apps.where((app) => app.enabled && !app.criticalSystem).length;

  Future<void> _audit({
    required String action,
    String? packageName,
    String? appLabel,
    String? sensor,
    String? details,
  }) async {
    try {
      await database.addEvent(
        action: action,
        packageName: packageName,
        appLabel: appLabel,
        sensor: sensor,
        details: details,
      );
      events = await database.loadEvents();
      auditWarning = null;
    } catch (e) {
      auditWarning = 'تم تنفيذ الحماية، لكن تعذر حفظ السجل المحلي: ${_friendlyError(e)}';
    }
    notifyListeners();
  }

  Future<void> _savePolicyBestEffort(AppPolicy policy) async {
    try {
      await database.savePolicy(policy);
    } catch (e) {
      auditWarning = 'تعذر تحديث Cache المحلي، وحالة Android Native هي المرجع: ${_friendlyError(e)}';
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (busy) return;
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
    if (error is PlatformException) return error.message ?? error.code;
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(database.close());
    super.dispose();
  }
}
