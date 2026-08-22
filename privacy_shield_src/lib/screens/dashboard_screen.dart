import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/models.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.controller, super.key});
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    return RefreshIndicator(
      onRefresh: controller.refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ProtectionHero(controller: controller),
          if (status.panicDegraded) ...[
            const SizedBox(height: 10),
            _WarningCard(
              icon: Icons.gpp_bad_rounded,
              title: 'Panic Lock يحتاج إصلاحًا فوريًا',
              text: 'Android أبلغ أن جزءًا من قفل الطوارئ غير مفروض بالكامل. اضغط إعادة فرض السياسات.',
              action: status.isDeviceOwner && !controller.busy
                  ? () => _guard(context, controller.repairPolicies)
                  : null,
            ),
          ],
          if (status.policyDriftCount > 0) ...[
            const SizedBox(height: 10),
            _WarningCard(
              icon: Icons.sync_problem_rounded,
              title: 'اكتُشف Policy Drift',
              text: '${status.policyDriftCount} سياسة مخزنة لا تطابق حالة Android الفعلية.',
              action: status.isDeviceOwner && !controller.busy
                  ? () => _guard(context, controller.repairPolicies)
                  : null,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SensorCard(
                  icon: Icons.videocam_outlined,
                  title: 'الكاميرا',
                  value: controller.blockedCount(SensorType.camera),
                  enforced: status.isDeviceOwner,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SensorCard(
                  icon: Icons.mic_none_rounded,
                  title: 'الميكروفون',
                  value: controller.blockedCount(SensorType.microphone),
                  enforced: status.isDeviceOwner,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SensorCard(
                  icon: Icons.location_on_outlined,
                  title: 'الموقع',
                  value: controller.blockedCount(SensorType.location),
                  enforced: status.isDeviceOwner,
                ),
              ),
            ],
          ),
          if (controller.sessions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: Icon(
                  status.watchdogRunning ? Icons.timer_rounded : Icons.warning_rounded,
                ),
                title: Text('${controller.sessions.length} جلسة حساس مؤقتة'),
                subtitle: Text(
                  status.watchdogRunning
                      ? 'Foreground Watchdog يعمل. ${status.canScheduleExactAlarms ? 'Exact Alarm يعمل كطبقة إضافية.' : 'Exact Alarm غير متاح؛ Watchdog + fallback alarms ما زالت تعمل.'}'
                      : 'Watchdog غير ظاهر كعامل تشغيل؛ أعد فرض السياسات فورًا.',
                ),
                trailing: status.watchdogRunning
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : Icon(Icons.error, color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public_off_rounded),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Network Shield',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Switch(
                        value: status.networkShieldEnabled,
                        onChanged: controller.busy
                            ? null
                            : (value) => _guard(
                                  context,
                                  () => controller.toggleNetworkShield(value),
                                ),
                      ),
                    ],
                  ),
                  const Text(
                    'فلترة DNS محلية لنطاقات التتبع المعروفة. لا تفك تشفير HTTPS ولا تمنع DoH الخاص داخل التطبيق.',
                  ),
                  if (status.otherVpnActive && !status.networkShieldEnabled) ...[
                    const SizedBox(height: 8),
                    Text(
                      'يوجد VPN آخر فعال؛ لن يستبدله Privacy Shield تلقائيًا.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'المحجوب اليوم: ${controller.trackerStats['blockedToday'] ?? 0}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: status.panicEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
              foregroundColor: status.panicEnabled
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onError,
              minimumSize: const Size.fromHeight(58),
            ),
            onPressed: status.isDeviceOwner && !controller.busy
                ? () => _guard(
                      context,
                      () => controller.setPanic(!status.panicEnabled),
                    )
                : null,
            icon: Icon(status.panicEnabled ? Icons.lock_open : Icons.lock),
            label: Text(
              status.panicEnabled
                  ? 'إلغاء قفل الطوارئ بأمان'
                  : 'قفل الطوارئ — LOCK EVERYTHING',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: status.isDeviceOwner && !controller.busy
                ? () => _guard(context, controller.protectAllSensitiveApps)
                : null,
            icon: const Icon(Icons.security_rounded),
            label: Text(
              'حماية جميع التطبيقات غير الحرجة (${controller.protectableAppCount})',
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$e')),
    );
  }
}

class _ProtectionHero extends StatelessWidget {
  const _ProtectionHero({required this.controller});
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final (title, subtitle, icon) = status.fullProtectionReady
        ? (
            'الحماية المدارة جاهزة',
            'Android Device Owner يستطيع فرض DENIED وفتح الحساس مؤقتًا ثم إعادة القفل تلقائيًا.',
            Icons.verified_user,
          )
        : status.isDeviceOwner
            ? (
                'المنع يعمل — الفتح المؤقت محدود',
                'Device Owner فعال لكن Android لا يسمح لهذا provisioning بمنح صلاحيات الحساسات مؤقتًا.',
                Icons.shield,
              )
            : (
                'الحماية الكاملة غير مفعّلة',
                'لا يمكن لتطبيق Android عادي التحكم في صلاحيات التطبيقات الأخرى. أكمل Device Owner من الإعدادات.',
                Icons.info_outline,
              );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(icon, size: 32),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle),
                  if (status.panicEnabled) ...[
                    const SizedBox(height: 10),
                    Chip(
                      avatar: Icon(
                        status.panicDegraded ? Icons.warning : Icons.lock,
                        size: 18,
                      ),
                      label: Text(
                        status.panicDegraded
                            ? 'PANIC LOCK — يحتاج إصلاح'
                            : 'PANIC LOCK مفعّل ومؤكد',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(text),
                  ],
                ),
              ),
              if (action != null)
                TextButton(onPressed: action, child: const Text('إصلاح')),
            ],
          ),
        ),
      );
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.enforced,
  });

  final IconData icon;
  final String title;
  final int value;
  final bool enforced;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '$value',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              Text(
                enforced ? 'DPM DENIED' : 'غير مفروض',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      );
}
