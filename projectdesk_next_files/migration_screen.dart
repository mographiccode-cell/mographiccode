import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/migration_backup_service.dart';
import '../services/database_service.dart';

class MigrationScreen extends StatefulWidget {
  final VoidCallback onDone;
  final bool allowSkip;

  const MigrationScreen({super.key, required this.onDone, this.allowSkip = true});

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  BackupInspection? inspection;
  bool busy = false;
  String message = '';

  Future<void> _pick() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final result = await MigrationBackupService.instance.pickAndInspectBackup();
      if (!mounted) return;
      if (result != null) setState(() => inspection = result);
    } catch (error) {
      if (mounted) {
        setState(() => message = 'تعذر قراءة النسخة: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    final selected = inspection;
    if (selected == null || !selected.hasProjects) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await MigrationBackupService.instance.restoreInspection(selected);
      await DatabaseService.instance.setSetting('migration_done', '1');
      if (!mounted) return;
      setState(() => message = 'تم نقل ${selected.projects} مشروع بنجاح.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) widget.onDone();
    } catch (error) {
      if (mounted) {
        setState(() => message = 'فشل الاستيراد: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _skip() async {
    await DatabaseService.instance.setSetting('migration_done', '1');
    if (mounted) widget.onDone();
  }

  Widget _countTile(IconData icon, String label, int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7E7E7)),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final data = inspection;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('ProjectDesk Next', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            const Icon(Icons.move_down_rounded, size: 52, color: AppTheme.accent),
            const SizedBox(height: 10),
            const Text(
              'نقل بيانات ProjectDesk القديم',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'التطبيق القديم سيبقى كما هو. اختر ملف .pobackup الذي أنشأته أداة Recovery، وسنفحصه أولًا قبل نقل أي بيانات.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(data == null ? 'اختيار ملف .pobackup' : 'اختيار ملف آخر'),
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (data != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Row(children: [
                      Icon(Icons.verified_outlined, color: Colors.green),
                      SizedBox(width: 8),
                      Text('تم فحص النسخة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 5),
                    Text(data.fileName, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 12),
                    _countTile(Icons.folder_copy_outlined, 'المشاريع', data.projects),
                    const SizedBox(height: 8),
                    _countTile(Icons.checklist_rtl_rounded, 'عناصر Part 1 / Part 2', data.deliverables),
                    const SizedBox(height: 8),
                    _countTile(Icons.rule_folder_outlined, 'التعديلات والمهام', data.tasks),
                    const SizedBox(height: 8),
                    _countTile(Icons.attach_file_rounded, 'سجلات الملفات', data.projectFiles),
                    const SizedBox(height: 8),
                    _countTile(Icons.inventory_2_outlined, 'ملفات فعلية داخل النسخة', data.embeddedFiles),
                    if (!data.hasProjects) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '⚠️ هذه النسخة لا تحتوي أي مشروع. لا تستخدمها كبديل لبيانات التطبيق القديم.',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy || !data.hasProjects ? null : _restore,
                icon: const Icon(Icons.download_done_rounded),
                label: Text('استيراد ${data.projects} مشروع الآن'),
              ),
            ],
            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF3E8), borderRadius: BorderRadius.circular(12)),
                child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
            if (widget.allowSkip) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: busy ? null : _skip, child: const Text('الدخول بدون استيراد الآن')),
            ],
            const SizedBox(height: 12),
            const Text(
              'لا تحذف ProjectDesk القديم حتى ترى مشاريعك كاملة داخل ProjectDesk Next.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
