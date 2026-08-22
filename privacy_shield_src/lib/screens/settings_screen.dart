import 'package:flutter/material.dart';

import '../core/controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final setup = controller.setupDiagnostics;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'حالة الحماية الفعلية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _StateRow('Device Owner', status.isDeviceOwner),
                _StateRow('إدارة صلاحيات الحساسات', status.canGrantSensors),
                _StateRow('Panic Lock سليم', !status.panicDegraded),
                _StateRow(
                  'لا يوجد Policy Drift',
                  status.policyDriftCount == 0,
                ),
                if (controller.sessions.isNotEmpty)
                  _StateRow('Temporary Grant Watchdog', status.watchdogRunning),
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      status.canScheduleExactAlarms
                          ? Icons.alarm_on_rounded
                          : Icons.alarm_off_rounded,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status.canScheduleExactAlarms
                            ? 'Exact Alarm متاح كطبقة إعادة قفل إضافية.'
                            : 'Exact Alarm غير متاح. الفتح المؤقت يعتمد على Foreground Watchdog + fallback alarm ولا يتوقف بالكامل.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!status.isDeviceOwner)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تفعيل Full Protection',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Android لا يسمح لتطبيق عادي بتغيير Camera/Microphone permissions لتطبيقات أخرى. لذلك Full Protection يحتاج Privacy Shield كـ Device Owner.',
                  ),
                  const SizedBox(height: 10),
                  if (setup != null) ...[
                    _StateRow('Device Admin مفعّل', setup.isAdminActive),
                    _StateRow('Provisioning متاح الآن', setup.provisioningAllowed),
                    if (setup.deviceProvisioned && !setup.isDeviceOwner)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'هذا الهاتف تم إكمال إعداده مسبقًا. أمر Device Owner قد يرفضه Android حتى إزالة الحسابات/Work Profile أو استخدام جهاز اختبار نظيف/إعادة تهيئة مناسبة.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text('أمر الاختبار على جهاز Android نظيف:'),
                    const SizedBox(height: 6),
                    SelectableText(
                      setup.adbCommand,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: controller.openDeviceAdminSettings,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Device Admin'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.openPrivacySettings,
                        icon: const Icon(Icons.privacy_tip_outlined),
                        label: const Text('Privacy Controls'),
                      ),
                    ],
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
                title: const Text('Alarms & reminders'),
                subtitle: Text(
                  status.canScheduleExactAlarms
                      ? 'مسموح — طبقة إضافية'
                      : 'اختياري — Watchdog ما زال يعيد القفل',
                ),
                onTap: controller.openExactAlarmSettings,
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('إعدادات خصوصية Android'),
                onTap: controller.openPrivacySettings,
              ),
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('فحص وإعادة فرض كل السياسات'),
                subtitle: const Text(
                  'يعيد مطابقة PolicyStore مع DPM ويسحب أي orphan GRANTED بلا جلسة مؤقتة صالحة.',
                ),
                onTap: status.isDeviceOwner && !controller.busy
                    ? () async {
                        try {
                          await controller.repairPolicies();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Network Shield',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  status.otherVpnActive && !status.networkShieldEnabled
                      ? 'يوجد VPN آخر فعال. Privacy Shield لن يستبدله تلقائيًا.'
                      : status.networkShieldEnabled
                          ? 'Local DNS VPN الخاص بـPrivacy Shield هو النشط.'
                          : 'غير مفعّل.',
                ),
              ],
            ),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'الخصوصية: Privacy Shield لا يطلب CAMERA أو RECORD_AUDIO أو Location لنفسه. سجل الواجهة محلي، وحالة DPM Native هي مصدر الحقيقة. Network Shield يفحص DNS فقط ولا يقرأ HTTPS أو الرسائل.',
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
            Icon(
              enabled ? Icons.check_circle : Icons.cancel,
              color: enabled
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
          ],
        ),
      );
}
