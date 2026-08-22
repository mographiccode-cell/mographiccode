import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/models.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({required this.controller, super.key});
  final PrivacyController controller;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final apps = widget.controller.apps
        .where((app) => app.label.toLowerCase().contains(query.toLowerCase()) || app.packageName.contains(query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (value) => setState(() => query = value.trim()),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ابحث عن تطبيق…',
            ),
          ),
        ),
        Expanded(
          child: apps.isEmpty
              ? const Center(child: Text('لا توجد تطبيقات مطابقة.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: apps.length,
                  itemBuilder: (context, index) => _AppCard(
                    app: apps[index],
                    controller: widget.controller,
                  ),
                ),
        ),
      ],
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.controller});
  final ManagedApp app;
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(child: Text(app.label.isEmpty ? '?' : app.label.substring(0, 1))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.label,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(app.packageName,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (app.systemApp) const Chip(label: Text('نظام')),
                ],
              ),
              const Divider(height: 20),
              for (final sensor in SensorType.values)
                if (app.supports(sensor)) _SensorRow(app: app, sensor: sensor, controller: controller),
            ],
          ),
        ),
      );
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({required this.app, required this.sensor, required this.controller});
  final ManagedApp app;
  final SensorType sensor;
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final blocked = controller.isBlocked(app, sensor);
    final session = controller.sessionFor(app.packageName, sensor);
    final seconds = ((session?.remainingMs ?? 0) / 1000).ceil().clamp(0, 9999);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(sensor.arLabel)),
          Switch(
            value: blocked,
            onChanged: controller.status.isDeviceOwner && !controller.busy && session == null
                ? (value) => _guard(context, () => controller.setBlocked(app, sensor, value))
                : null,
          ),
          const Spacer(),
          if (session != null)
            FilledButton.tonalIcon(
              onPressed: controller.busy
                  ? null
                  : () => _guard(context, () => controller.revokeNow(app, sensor)),
              icon: const Icon(Icons.lock, size: 18),
              label: Text('قفل $secondsث'),
            )
          else
            TextButton.icon(
              onPressed: blocked && controller.status.fullProtectionReady && !controller.busy
                  ? () => _guard(context, () => controller.grantTemporary(app, sensor))
                  : null,
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: const Text('دقيقتان'),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}
