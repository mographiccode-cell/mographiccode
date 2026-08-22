enum SensorType { camera, microphone, location }

extension SensorTypeX on SensorType {
  String get wire => name;
  String get arLabel => switch (this) {
        SensorType.camera => 'الكاميرا',
        SensorType.microphone => 'الميكروفون',
        SensorType.location => 'الموقع',
      };
}

class ManagedApp {
  ManagedApp({
    required this.packageName,
    required this.label,
    required this.hasCamera,
    required this.hasMicrophone,
    required this.hasLocation,
    required this.systemApp,
  });

  factory ManagedApp.fromMap(Map<dynamic, dynamic> map) => ManagedApp(
        packageName: map['packageName'] as String,
        label: (map['label'] as String?) ?? (map['packageName'] as String),
        hasCamera: map['hasCamera'] == true,
        hasMicrophone: map['hasMicrophone'] == true,
        hasLocation: map['hasLocation'] == true,
        systemApp: map['systemApp'] == true,
      );

  final String packageName;
  final String label;
  final bool hasCamera;
  final bool hasMicrophone;
  final bool hasLocation;
  final bool systemApp;

  bool supports(SensorType sensor) => switch (sensor) {
        SensorType.camera => hasCamera,
        SensorType.microphone => hasMicrophone,
        SensorType.location => hasLocation,
      };
}

class AppPolicy {
  AppPolicy({
    required this.packageName,
    required this.label,
    this.cameraBlocked = false,
    this.microphoneBlocked = false,
    this.locationBlocked = false,
  });

  final String packageName;
  String label;
  bool cameraBlocked;
  bool microphoneBlocked;
  bool locationBlocked;

  bool blocked(SensorType sensor) => switch (sensor) {
        SensorType.camera => cameraBlocked,
        SensorType.microphone => microphoneBlocked,
        SensorType.location => locationBlocked,
      };

  void setBlocked(SensorType sensor, bool value) {
    switch (sensor) {
      case SensorType.camera:
        cameraBlocked = value;
        break;
      case SensorType.microphone:
        microphoneBlocked = value;
        break;
      case SensorType.location:
        locationBlocked = value;
        break;
    }
  }
}

class ActiveSession {
  ActiveSession({
    required this.packageName,
    required this.sensor,
    required this.remainingMs,
  });

  factory ActiveSession.fromMap(Map<dynamic, dynamic> map) => ActiveSession(
        packageName: map['packageName'] as String,
        sensor: SensorType.values.byName(map['sensor'] as String),
        remainingMs: (map['remainingMs'] as num).toInt(),
      );

  final String packageName;
  final SensorType sensor;
  final int remainingMs;
}

class NativeStatus {
  const NativeStatus({
    this.isDeviceOwner = false,
    this.canGrantSensors = false,
    this.canScheduleExactAlarms = false,
    this.panicEnabled = false,
    this.networkShieldEnabled = false,
    this.vpnPrepared = false,
  });

  factory NativeStatus.fromMap(Map<dynamic, dynamic> map) => NativeStatus(
        isDeviceOwner: map['isDeviceOwner'] == true,
        canGrantSensors: map['canGrantSensors'] == true,
        canScheduleExactAlarms: map['canScheduleExactAlarms'] == true,
        panicEnabled: map['panicEnabled'] == true,
        networkShieldEnabled: map['networkShieldEnabled'] == true,
        vpnPrepared: map['vpnPrepared'] == true,
      );

  final bool isDeviceOwner;
  final bool canGrantSensors;
  final bool canScheduleExactAlarms;
  final bool panicEnabled;
  final bool networkShieldEnabled;
  final bool vpnPrepared;

  bool get fullProtectionReady =>
      isDeviceOwner && canGrantSensors && canScheduleExactAlarms;
}

class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.timestamp,
    required this.action,
    this.packageName,
    this.appLabel,
    this.sensor,
    this.details,
  });

  final int id;
  final DateTime timestamp;
  final String action;
  final String? packageName;
  final String? appLabel;
  final String? sensor;
  final String? details;
}
