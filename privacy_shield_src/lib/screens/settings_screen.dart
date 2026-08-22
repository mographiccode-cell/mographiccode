import 'package:flutter/material.dart';
import '../core/controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Full Protection Mode',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _StateRow('Device Owner', status.isDeviceOwner),
                _StateRow('Sensor grants', status.canGrantSensors),
                _StateRow('Exact alarms', status.canScheduleExactAlarms),
                const SizedBox(height: 14),
                const SelectableText(
                  'adb shell dpm set-device-owner com.privacyshield.privacy_shield/.PrivacyAdminReceiver',
                  style: TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                Text(
                  'ملاحظة: تهيئة Device Owner عبر ADB تتطلب عادة جهازًا بدون حسابات/تهيئة مخصصة. هذا قيد أمني من Android.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.alarm),
                title: const Text('إعدادات Alarms & reminders'),
                subtitle: Text(status.canScheduleExactAlarms ? 'مسموح' : 'مطلوب للفتح المؤقت'),
                onTap: controller.openExactAlarmSettings,
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('إعدادات خصوصية Android'),
                onTap: controller.openPrivacySettings,
              ),
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('إعادة فرض السياسات'),
                subtitle: const Text('يفحص النسخة Native ويعيد تطبيق DENIED المخزنة.'),
                onTap: status.isDeviceOwner && !controller.busy
                    ? () async {
                        try {
                          await controller.repairPolicies();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'الخصوصية: لا يطلب Privacy Shield صلاحية الكاميرا أو الميكروفون أو الموقع لنفسه. سجل السياسات والأحداث محلي على الجهاز. Network Shield يفحص أسماء نطاقات DNS فقط ولا يفك تشفير HTTPS.',
            ),
          ),
        ),
      ],
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow(this.label, this.enabled);
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(enabled ? Icons.check_circle : Icons.cancel,
                color: enabled ? Colors.green : Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      );
}
