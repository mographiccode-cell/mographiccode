import 'package:flutter/material.dart';
import '../core/controller.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({required this.controller, super.key});
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.events.isEmpty) return const Center(child: Text('لا توجد أحداث مسجلة بعد.'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: controller.events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final event = controller.events[index];
        return ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(event.appLabel ?? event.action),
          subtitle: Text([
            event.action,
            if (event.sensor != null) event.sensor,
            if (event.details != null) event.details,
          ].whereType<String>().join(' • ')),
          trailing: Text(
            '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}',
          ),
        );
      },
    );
  }
}
