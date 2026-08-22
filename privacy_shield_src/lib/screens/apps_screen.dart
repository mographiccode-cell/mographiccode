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
    final apps = widget.controller.apps.where((app) {
      final q = query.toLowerCase();
      return app.label.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (value) => setState(() => query = value.trim()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ابحث عن تطبيق…',
              suffixText: '${apps.length}/${widget.controller.apps.length}',
            ),
          ),
        ),
        if (!widget.controller.status.isDeviceOwner)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'الوضع الحالي إرشادي فقط. لن نعرض أي تطبيق على أنه محمي حتى يصبح Privacy Shield هو Device Owner.',
                ),
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
                  CircleAvatar(
                    child: Text(app.label.isEmpty ? '?' : app.label.substring(0, 1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          app.packageName,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (app.systemApp)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('مثبت مسبقًا'),
                    ),
                  if (app.criticalSystem)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(Icons.warning_amber_rounded, size: 17),
                      label: Text('نظام حرج'),
                    ),
                  if (!app.enabled)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('معطل'),
                    ),
                ],
              ),
              if (app.criticalSystem)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'تم تعطيل الحظر لهذا المكوّن لتجنب تعطيل وظائف الهاتف الأساسية.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const Divider(height: 20),
              for (final sensor in SensorType.values)
                if (app.supports(sensor))
                  _SensorRow(
                    app: app,
                    sensor: sensor,
                    controller: controller,
                  ),
            ],
          ),
        ),
      );
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.app,
    required this.sensor,
    required this.controller,
  });

  final ManagedApp app;
  final SensorType sensor;
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final blocked = controller.isBlocked(app, sensor);
    final session = controller.sessionFor(app.packageName, sensor);
    final seconds = ((session?.remainingMs ?? 0) / 1000).ceil().clamp(0, 9999);
    final canChange = controller.status.isDeviceOwner &&
        !controller.busy &&
        session == null &&
        !app.criticalSystem &&
        app.enabled;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_sensorIcon(sensor), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sensor.arLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Switch(
                value: blocked,
                onChanged: canChange
                    ? (value) => _guard(
                          context,
                          () => controller.setBlocked(app, sensor, value),
                        )
                    : null,
              ),
            ],
          ),
          if (session != null)
            FilledButton.tonalIcon(
              onPressed: controller.busy
                  ? null
                  : () => _guard(
                        context,
                        () => controller.revokeNow(app, sensor),
                      ),
              icon: const Icon(Icons.lock, size: 18),
              label: Text(
                session.revocationPending
                    ? 'جارٍ إعادة محاولة القفل الآن'
                    : 'قفل الآن • متبقٍ $seconds ثانية',
              ),
            )
          else if (blocked && controller.status.temporaryAccessReady)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                _TempButton(
                  label: '30ث',
                  onPressed: controller.busy
                      ? null
                      : () => _guard(
                            context,
                            () => controller.grantTemporary(
                              app,
                              sensor,
                              durationMs: 30000,
                            ),
                          ),
                ),
                _TempButton(
                  label: '60ث',
                  onPressed: controller.busy
                      ? null
                      : () => _guard(
                            context,
                            () => controller.grantTemporary(
                              app,
                              sensor,
                              durationMs: 60000,
                            ),
                          ),
                ),
                _TempButton(
                  label: 'دقيقتان',
                  onPressed: controller.busy
                      ? null
                      : () => _guard(
                            context,
                            () => controller.grantTemporary(
                              app,
                              sensor,
                              durationMs: 120000,
                            ),
                          ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _sensorIcon(SensorType sensor) => switch (sensor) {
        SensorType.camera => Icons.videocam_outlined,
        SensorType.microphone => Icons.mic_none_rounded,
        SensorType.location => Icons.location_on_outlined,
      };
}

class _TempButton extends StatelessWidget {
  const _TempButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.timer_outlined, size: 18),
        label: Text(label),
      );
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
