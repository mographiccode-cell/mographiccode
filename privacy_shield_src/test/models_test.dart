import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_shield/core/models.dart';

void main() {
  test('policy has independent sensor states', () {
    final policy = AppPolicy(packageName: 'x', label: 'X');
    policy.setBlocked(SensorType.camera, true);
    expect(policy.blocked(SensorType.camera), isTrue);
    expect(policy.blocked(SensorType.microphone), isFalse);
    expect(policy.blocked(SensorType.location), isFalse);
  });

  test('temporary access can work without exact alarm but full mode is strict', () {
    const readyWithoutExactAlarm = NativeStatus(
      isDeviceOwner: true,
      canGrantSensors: true,
      canScheduleExactAlarms: false,
      watchdogRunning: true,
    );
    const full = NativeStatus(
      isDeviceOwner: true,
      canGrantSensors: true,
      canScheduleExactAlarms: true,
    );
    const noSensorGrantControl = NativeStatus(
      isDeviceOwner: true,
      canGrantSensors: false,
      canScheduleExactAlarms: true,
    );
    expect(readyWithoutExactAlarm.temporaryAccessReady, isTrue);
    expect(readyWithoutExactAlarm.fullProtectionReady, isFalse);
    expect(full.fullProtectionReady, isTrue);
    expect(noSensorGrantControl.temporaryAccessReady, isFalse);
  });

  test('managed app parses critical and preinstalled states separately', () {
    final app = ManagedApp.fromMap(<dynamic, dynamic>{
      'packageName': 'com.google.android.youtube',
      'label': 'YouTube',
      'hasCamera': true,
      'hasMicrophone': true,
      'hasLocation': true,
      'systemApp': true,
      'criticalSystem': false,
      'enabled': true,
    });
    expect(app.systemApp, isTrue);
    expect(app.criticalSystem, isFalse);
    expect(app.enabled, isTrue);
    expect(app.supports(SensorType.camera), isTrue);
  });

  test('expired session can surface pending fail-closed revocation', () {
    final session = ActiveSession.fromMap(<dynamic, dynamic>{
      'packageName': 'test.package',
      'sensor': 'camera',
      'remainingMs': 0,
      'revocationPending': true,
    });
    expect(session.remainingMs, 0);
    expect(session.revocationPending, isTrue);
  });
}
