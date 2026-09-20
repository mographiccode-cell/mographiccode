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

  List<String> get _missingFields {
    final template = _template;
    if (template == null) return const [];
    return _engine.missingFields(_headers, template.placeholders);
  }

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

        final missing = _missingFields;
        _status = missing.isEmpty
            ? 'تمت قراءة ${_records.length} طالب من Excel.'
            : 'تمت قراءة Excel، لكن توجد حقول في Word غير موجودة في Excel.';
      });
    } catch (error) {
      _showError(error);
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

        final missing = _missingFields;
        _status = missing.isEmpty
            ? 'تم اكتشاف ${info.cardsPerPage} بطاقة في الصفحة و${info.placeholders.length} حقول دمج.'
            : 'تم تحميل Word، لكن بعض حقوله غير موجودة في Excel.';
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    if (_excelBytes == null ||
        _wordBytes == null ||
        _records.isEmpty ||
        _template == null) {
      _showError('اختر ملف Excel وقالب Word أولاً.');
      return;
    }

    final missing = _missingFields;
    if (missing.isNotEmpty) {
      _showError(
        'لا يمكن الدمج قبل مطابقة هذه الحقول مع أعمدة Excel: ${missing.join('، ')}',
      );
      return;
    }

    setState(() {
      _busy = true;
      _status =
          'جارٍ دمج ${_records.length} طالب داخل ${_template!.cardsPerPage} بطاقة لكل صفحة...';
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

      late String pdfPath;
      late Uint8List pdfBytes;

      String? officePdfPath;
      if (Platform.isWindows) {
        if (mounted) {
          setState(() {
            _status =
                'تم الدمج. جارٍ إنشاء PDF باستخدام Word/LibreOffice لأعلى تطابق مع التصميم...';
          });
        }
        officePdfPath = await _engine.tryWindowsOfficePdf(docxPath);
      }

      if (officePdfPath != null && File(officePdfPath).existsSync()) {
        pdfPath = officePdfPath;
        pdfBytes = await File(pdfPath).readAsBytes();
      } else {
        if (mounted) {
          setState(() {
            _status =
                'جارٍ تحويل ملف Word المدموج إلى PDF مع الحفاظ على الجداول والصور والألوان والحدود...';
          });
        }

        pdfBytes = await _engine.buildDesignPdfFromTemplate(
          templateBytes: _wordBytes!,
          records: _records,
        );
        pdfPath = p.join(dir.path, 'student_cards_$stamp.pdf');
        await File(pdfPath).writeAsBytes(pdfBytes, flush: true);
      }

      if (!mounted) return;

      setState(() {
        _status =
            'تم بنجاح: ${_records.length} طالب، ${_template!.cardsPerPage} بطاقة لكل صفحة، وPDF جاهز للطباعة.';
      });

      await _showResult(
        docxPath: docxPath,
        pdfPath: pdfPath,
        pdfBytes: pdfBytes,
      );
    } catch (error) {
      _showError(error);
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
                    'تم إنشاء البطاقات',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تم دمج ${_records.length} طالب حسب ترتيب صفوف Excel داخل تصميم Word.',
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
    final missing = _missingFields;
    final ready = _excelBytes != null &&
        _wordBytes != null &&
        _records.isNotEmpty &&
        _template != null &&
        missing.isEmpty &&
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
                        'دمج بطاقات الطلاب — Excel + Word',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Word هو التصميم الأساسي للبطاقات. Excel هو مصدر البيانات فقط. الطالب الأول يذهب للبطاقة الأولى، والثاني للثانية، وهكذا، ثم تبدأ صفحة جديدة تلقائيًا.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _FileStep(
                  number: '1',
                  icon: Icons.table_chart_outlined,
                  title: 'اختر ملف Excel',
                  subtitle: _excelFile == null
                      ? 'الصف الأول أسماء الأعمدة، وكل صف بعده طالب واحد.'
                      : '${_excelFile!.name} — ${_records.length} طالب',
                  onTap: _busy ? null : _pickExcel,
                ),
                const SizedBox(height: 12),
                _FileStep(
                  number: '2',
                  icon: Icons.description_outlined,
                  title: 'اختر قالب Word',
                  subtitle: _wordFile == null
                      ? 'DOCX يحتوي على البطاقات داخل جدول وحقول مثل {{الاسم}}.'
                      : '${_wordFile!.name} — ${_template?.cardsPerPage ?? 0} بطاقة/صفحة',
                  onTap: _busy ? null : _pickWord,
                ),
                if (_template != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'مطابقة حقول Word مع أعمدة Excel',
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
                          ok
                              ? Icons.check_circle
                              : Icons.error_outline_rounded,
                          size: 18,
                          color: ok ? Colors.green : Colors.red,
                        ),
                        label: Text(field),
                      );
                    }).toList(),
                  ),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'لن يسمح التطبيق بالدمج حتى توجد هذه الأعمدة في Excel: ${missing.join('، ')}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                        : 'دمج البيانات وإنشاء PDF للطباعة',
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
                      ? 'Windows: يستخدم Microsoft Word أو LibreOffice عند توفره للحصول على أعلى تطابق ممكن مع قالب Word، مع محول DOCX داخلي احتياطي.'
                      : 'Android: يحافظ ملف Word المدموج على القالب الأصلي، ويحوَّل إلى PDF عبر محرك DOCX يدعم الجداول والصور والألوان والحدود.',
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
