import 'package:flutter/services.dart';

import 'models.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('privacy_shield/native');

  Future<NativeStatus> getStatus() async {
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('getStatus');
    return NativeStatus.fromMap(map ?? <dynamic, dynamic>{});
  }

  Future<SetupDiagnostics> getSetupDiagnostics() async {
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('getSetupDiagnostics');
    return SetupDiagnostics.fromMap(map ?? <dynamic, dynamic>{});
  }

  Future<Map<String, Set<SensorType>>> getBlockedPolicies() async {
    final list = await _channel.invokeListMethod<dynamic>('getBlockedPolicies') ?? <dynamic>[];
    final result = <String, Set<SensorType>>{};
    for (final item in list) {
      final map = item as Map<dynamic, dynamic>;
      final packageName = map['packageName'] as String;
      final sensor = SensorType.values.byName(map['sensor'] as String);
      result.putIfAbsent(packageName, () => <SensorType>{}).add(sensor);
    }
    return result;
  }

  Future<List<ManagedApp>> listApps() async {
    final list = await _channel.invokeListMethod<dynamic>('listApps') ?? <dynamic>[];
    return list
        .map((item) => ManagedApp.fromMap(item as Map<dynamic, dynamic>))
        .toList();
  }

  Future<void> setBlocked(String packageName, SensorType sensor, bool blocked) =>
      _channel.invokeMethod<void>('setBlocked', <String, Object>{
        'packageName': packageName,
        'sensor': sensor.wire,
        'blocked': blocked,
      });

  Future<void> temporaryGrant(
    String packageName,
    SensorType sensor, {
    int durationMs = 120000,
  }) =>
      _channel.invokeMethod<void>('temporaryGrant', <String, Object>{
        'packageName': packageName,
        'sensor': sensor.wire,
        'durationMs': durationMs,
      });

  Future<void> revokeNow(String packageName, SensorType sensor) =>
      _channel.invokeMethod<void>('revokeNow', <String, Object>{
        'packageName': packageName,
        'sensor': sensor.wire,
      });

  Future<List<ActiveSession>> getActiveSessions() async {
    final list = await _channel.invokeListMethod<dynamic>('getActiveSessions') ?? <dynamic>[];
    return list
        .map((item) => ActiveSession.fromMap(item as Map<dynamic, dynamic>))
        .toList();
  }

  Future<void> setPanic(bool enabled) =>
      _channel.invokeMethod<void>('setPanic', <String, Object>{'enabled': enabled});

  Future<int> repairPolicies() async =>
      (await _channel.invokeMethod<int>('repairPolicies')) ?? 0;

  Future<bool> launchApp(String packageName) async =>
      (await _channel.invokeMethod<bool>('launchApp', <String, Object>{
        'packageName': packageName,
      })) ??
      false;

  Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod<void>('openExactAlarmSettings');

  Future<void> openPrivacySettings() =>
      _channel.invokeMethod<void>('openPrivacySettings');

  Future<void> openDeviceAdminSettings() =>
      _channel.invokeMethod<void>('openDeviceAdminSettings');

  Future<bool> startNetworkShield() async =>
      (await _channel.invokeMethod<bool>('startNetworkShield')) ?? false;

  Future<void> stopNetworkShield() =>
      _channel.invokeMethod<void>('stopNetworkShield');

  Future<Map<String, int>> trackerStats() async {
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('trackerStats') ??
        <dynamic, dynamic>{};
    return map.map((key, value) => MapEntry(key.toString(), (value as num).toInt()));
  }
}
