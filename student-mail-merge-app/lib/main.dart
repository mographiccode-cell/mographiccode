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

  ExcelImportResult? _excel;
  TemplateInfo? _template;

  bool _busy = false;
  String _status = 'اختر ملف Excel ثم ملف Word لبدء الدمج.';

  List<MergeRecord> get _records => _excel?.records ?? const [];

  List<String> get _missingFields {
    final excel = _excel;
    final template = _template;
    if (excel == null || template == null) return const [];
    return _engine.missingFields(excel, template);
  }

  Future<void> _pickExcel() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
    );
    if (file == null) return;

    setState(() {
      _busy = true;
      _status = 'جارٍ تحليل Excel واكتشاف الأوراق والأعمدة تلقائيًا...';
    });

    try {
      final bytes = await file.readAsBytes();
      final result = await _engine.readExcel(bytes);

      if (!mounted) return;
      setState(() {
        _excelFile = file;
        _excelBytes = bytes;
        _excel = result;

        final missing = _missingFields;
        _status = missing.isEmpty
            ? 'تم اكتشاف ${result.records.length} طالب/طالبة من ${result.sheetCount} أوراق.'
            : 'تمت قراءة Excel، لكن بعض بيانات Word المطلوبة غير متوفرة.';
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
      _status = 'جارٍ تحليل تصميم Word واكتشاف البطاقات...';
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
        final modeText = info.mode == WordTemplateMode.placeholders
            ? 'حقول دمج'
            : 'حقول مكتوبة داخل البطاقة';

        _status = missing.isEmpty
            ? 'تم اكتشاف ${info.cardsPerPage} بطاقات في الصفحة باستخدام $modeText.'
            : 'تم تحميل Word، لكن توجد بيانات مطلوبة غير متوفرة في Excel.';
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
      _showError('اختر ملف Excel وملف Word أولاً.');
      return;
    }

    final missing = _missingFields;
    if (missing.isNotEmpty) {
      _showError(
        'لا يمكن الدمج قبل توفير هذه البيانات: ${missing.join('، ')}',
      );
      return;
    }

    setState(() {
      _busy = true;
      _status =
          'جارٍ تعبئة ${_records.length} سجل داخل تصميم Word، ${_template!.cardsPerPage} بطاقات لكل صفحة...';
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
                'تم الدمج. جارٍ تحويل Word إلى PDF بأعلى تطابق مع التصميم...';
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
                'جارٍ إنشاء PDF من ملف Word المدموج مع الحفاظ على الجداول والصور والحدود...';
          });
        }

        pdfBytes = await _engine.buildDesignPdfFromDocx(mergedDocx);
        pdfPath = p.join(dir.path, 'student_cards_$stamp.pdf');
        await File(pdfPath).writeAsBytes(pdfBytes, flush: true);
      }

      if (!mounted) return;

      final pageCount =
          (_records.length / _template!.cardsPerPage).ceil();

      setState(() {
        _status =
            'تم بنجاح: ${_records.length} سجل، $pageCount صفحة، وPDF جاهز للطباعة.';
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
                    'تم دمج ${_records.length} سجل حسب ترتيب Excel داخل تصميم Word.',
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
                        'دمج مراسلات للبطاقات — Excel + Word',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'ارفع Excel وWord كما هما. التطبيق يكتشف بيانات الاسم والصف واللجنة ورقم الجلوس، ويأخذ تصميم البطاقات من Word نفسه دون إعادة تصميمها.',
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
                      ? 'يدعم عدة أوراق، صفوف فارغة، وعناوين غير موحدة.'
                      : '${_excelFile!.name} — ${_records.length} سجل من ${_excel?.sheetCount ?? 0} أوراق',
                  onTap: _busy ? null : _pickExcel,
                ),
                const SizedBox(height: 12),
                _FileStep(
                  number: '2',
                  icon: Icons.description_outlined,
                  title: 'اختر ملف Word',
                  subtitle: _wordFile == null
                      ? 'يمكن أن يكون قالبًا أو ملف بطاقات موجودًا بالفعل.'
                      : '${_wordFile!.name} — ${_template?.cardsPerPage ?? 0} بطاقات/صفحة',
                  onTap: _busy ? null : _pickWord,
                ),
                if (_template != null) ...[
                  const SizedBox(height: 18),
                  _TemplateSummary(template: _template!),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'بيانات ناقصة: ${missing.join('، ')}',
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
                        : 'دمج البيانات وإنشاء PDF',
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
                      ? 'على Windows يتم تفضيل Microsoft Word أو LibreOffice لتحويل الملف المدموج إلى PDF بنفس تخطيط Word.'
                      : 'على Android يتم الدمج داخل DOCX نفسه ثم تحويله إلى PDF محليًا.',
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

class _TemplateSummary extends StatelessWidget {
  final TemplateInfo template;

  const _TemplateSummary({required this.template});

  @override
  Widget build(BuildContext context) {
    final fields = template.mode == WordTemplateMode.placeholders
        ? template.placeholders
        : template.labeledFields.map((field) {
            switch (field) {
              case 'name':
                return 'الاسم';
              case 'grade':
                return 'الصف';
              case 'committee':
                return 'اللجنة';
              case 'seat':
                return 'رقم الجلوس';
              default:
                return field;
            }
          }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اكتشاف Word',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '${template.cardsPerPage} بطاقات في الصفحة — ${template.mode == WordTemplateMode.placeholders ? 'قالب حقول' : 'اكتشاف تلقائي من النص الموجود'}',
            ),
            if (fields.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: fields
                    .map(
                      (field) => Chip(
                        avatar: const Icon(
                          Icons.check_circle,
                          size: 17,
                          color: Colors.green,
                        ),
                        label: Text(field),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
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
              CircleAvatar(child: Text(number)),
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
