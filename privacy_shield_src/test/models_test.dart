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

  test('full protection is strict', () {
    const good = NativeStatus(
      isDeviceOwner: true,
      canGrantSensors: true,
      canScheduleExactAlarms: true,
    );
    const missingAlarm = NativeStatus(
      isDeviceOwner: true,
      canGrantSensors: true,
    );
    expect(good.fullProtectionReady, isTrue);
    expect(missingAlarm.fullProtectionReady, isFalse);
  });
}
