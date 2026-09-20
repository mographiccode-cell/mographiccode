import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import 'merge_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MailMergeApp());
}

class MailMergeApp extends StatelessWidget {
  const MailMergeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دمج بطاقات الطلاب',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2457C5),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MergeEngine _engine = MergeEngine();

  PlatformFile? _excelFile;
  PlatformFile? _wordFile;
  Uint8List? _excelBytes;
  Uint8List? _wordBytes;

  List<String> _headers = const [];
  List<MergeRecord> _records = const [];
  TemplateInfo? _template;

  bool _busy = false;
  String _status = 'اختر ملف Excel ثم قالب Word لبدء الدمج.';

  Future<void> _pickExcel() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
    );
    if (file == null) return;

    setState(() {
      _busy = true;
      _status = 'جارٍ قراءة ملف Excel...';
    });

    try {
      final bytes = await file.readAsBytes();
      final result = await _engine.readExcel(bytes);
      if (!mounted) return;
      setState(() {
        _excelFile = file;
        _excelBytes = bytes;
        _headers = result.headers;
        _records = result.records;
        _status = 'تمت قراءة ${_records.length} سجل من Excel.';
      });
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickWord() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
    );
    if (file == null) return;

    setState(() {
      _busy = true;
      _status = 'جارٍ فحص قالب Word...';
    });

    try {
      final bytes = await file.readAsBytes();
      final info = _engine.inspectWord(bytes);
      if (!mounted) return;
      setState(() {
        _wordFile = file;
        _wordBytes = bytes;
        _template = info;
        _status =
            'تم اكتشاف ${info.cardsPerPage} كروت و${info.placeholders.length} حقول في Word.';
      });
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    if (_excelBytes == null || _wordBytes == null || _records.isEmpty) {
      _showError('اختر Excel وWord أولاً.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'جارٍ تنفيذ Mail Merge...';
    });

    try {
      final mergedDocx = _engine.mergeDocx(
        templateBytes: _wordBytes!,
        records: _records,
      );

      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final docxPath = p.join(dir.path, 'student_cards_$stamp.docx');
      await File(docxPath).writeAsBytes(mergedDocx, flush: true);

      String? pdfPath;
      Uint8List pdfBytes;

      if (Platform.isWindows) {
        if (mounted) {
          setState(() {
            _status =
                'تم دمج Word. جارٍ محاولة إنشاء PDF بنفس التصميم عبر Word أو LibreOffice...';
          });
        }
        pdfPath = await _engine.tryWindowsOfficePdf(docxPath);
      }

      if (pdfPath != null && File(pdfPath).existsSync()) {
        pdfBytes = await File(pdfPath).readAsBytes();
      } else {
        if (mounted) {
          setState(() {
            _status =
                'جارٍ إنشاء PDF داخلي من كروت Word للطباعة على Android وWindows...';
          });
        }
        final cardTemplates = _engine.extractCardLines(_wordBytes!);
        pdfBytes = await _engine.buildPdf(
          records: _records,
          cardTemplates: cardTemplates,
        );
        pdfPath = p.join(dir.path, 'student_cards_$stamp.pdf');
        await File(pdfPath).writeAsBytes(pdfBytes, flush: true);
      }

      if (!mounted) return;
      setState(() {
        _status = 'تم إنشاء الملفات بنجاح.';
      });
      await _showResult(
        docxPath: docxPath,
        pdfPath: pdfPath,
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResult({
    required String docxPath,
    required String pdfPath,
    required Uint8List pdfBytes,
  }) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'تم إنشاء الملفات',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تم إنشاء Word مدموج وPDF جاهز للطباعة.',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      await Printing.layoutPdf(
                        onLayout: (_) async => pdfBytes,
                      );
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة PDF الآن'),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: () => OpenFilex.open(pdfPath),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('فتح PDF'),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: () => OpenFilex.open(docxPath),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('فتح Word المدموج'),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    pdfPath,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _fieldMatches(String field) {
    return _engine.fieldMatches(_headers, field);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _excelBytes != null &&
        _wordBytes != null &&
        _records.isNotEmpty &&
        !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دمج بطاقات الطلاب'),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mail Merge للكروت — Excel + Word',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'اختر ملف Excel الذي يحتوي على بيانات الطلاب، ثم اختر ملف Word المصمم مسبقًا وفيه الكروت وحقول مثل {{الاسم}} أو «الاسم». التطبيق يملأ الكروت بالتسلسل ويولد الصفحات تلقائيًا.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _FileStep(
                  number: '1',
                  icon: Icons.table_chart_outlined,
                  title: 'اختر Excel',
                  subtitle: _excelFile == null
                      ? 'الصف الأول هو أسماء الحقول، وكل صف بعده طالب.'
                      : '${_excelFile!.name} — ${_records.length} سجل',
                  onTap: _busy ? null : _pickExcel,
                ),
                const SizedBox(height: 12),
                _FileStep(
                  number: '2',
                  icon: Icons.description_outlined,
                  title: 'اختر قالب Word',
                  subtitle: _wordFile == null
                      ? 'DOCX يحتوي على الكروت داخل جدول وحقول الدمج.'
                      : '${_wordFile!.name} — ${_template?.cardsPerPage ?? 0} كرت/صفحة',
                  onTap: _busy ? null : _pickWord,
                ),
                if (_template != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'مطابقة حقول Word مع Excel',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _template!.placeholders.map((field) {
                      final ok = _fieldMatches(field);
                      return Chip(
                        avatar: Icon(
                          ok ? Icons.check_circle : Icons.warning_amber_rounded,
                          size: 18,
                          color: ok ? Colors.green : Colors.orange,
                        ),
                        label: Text(field),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: ready ? _generate : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.merge_type),
                  label: Text(
                    _busy
                        ? 'جارٍ التنفيذ...'
                        : 'دمج المراسلات وإنشاء PDF',
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(_status),
                ),
                const SizedBox(height: 14),
                Text(
                  Platform.isWindows
                      ? 'على Windows: يحاول التطبيق استخدام Microsoft Word أو LibreOffice لتحويل الملف المدموج إلى PDF بنفس تصميم Word. وإذا لم يتوفر أي منهما يستخدم مولد PDF الداخلي.'
                      : 'على Android: يتم إنشاء Word مدموج، ويستخدم التطبيق مولد PDF الداخلي للطباعة.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileStep extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _FileStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                child: Text(number),
              ),
              const SizedBox(width: 14),
              Icon(icon, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}
