import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'merge_engine.dart';
import 'output_manager.dart';
import 'saved_files_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MailMergeApp());
}

class MailMergeApp extends StatelessWidget {
  const MailMergeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F5FBF),
      brightness: Brightness.light,
    );

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
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            side: BorderSide(color: Color(0xFFE2E7F0)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFFD9E0EA)),
          ),
        ),
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
  final TextEditingController _seatStartController =
      TextEditingController(text: '1');

  PlatformFile? _excelFile;
  PlatformFile? _wordFile;
  Uint8List? _excelBytes;
  Uint8List? _wordBytes;

  ExcelImportResult? _excel;
  TemplateInfo? _template;

  bool _busy = false;
  String _stage = '';
  String _status = 'اختر ملف Excel ثم Word وحدد بداية رقم الجلوس.';

  @override
  void dispose() {
    _seatStartController.dispose();
    super.dispose();
  }

  List<MergeRecord> get _records => _excel?.records ?? const [];

  int? get _seatStart {
    final value = int.tryParse(_seatStartController.text.trim());
    if (value == null || value < 1) return null;
    return value;
  }

  int? get _seatEnd {
    final start = _seatStart;
    if (start == null || _records.isEmpty) return null;
    return start + _records.length - 1;
  }

  List<String> get _missingFields {
    final excel = _excel;
    final template = _template;
    if (excel == null || template == null) return const [];
    return _engine.missingFields(excel, template);
  }

  List<MergeRecord> _numberedRecords() {
    final start = _seatStart;
    if (start == null) {
      throw Exception('أدخل رقم بداية جلوس صحيحًا، مثال: 300.');
    }
    return _engine.renumberSeats(_records, start);
  }

  Future<void> _pickExcel() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
    );
    if (file == null) return;

    _setBusy('قراءة Excel', 'جارٍ تحليل الأوراق والطلاب تلقائيًا...');

    try {
      final bytes = await file.readAsBytes();
      final result = await _engine.readExcel(bytes);

      if (!mounted) return;
      setState(() {
        _excelFile = file;
        _excelBytes = bytes;
        _excel = result;
        _status =
            'تم اكتشاف ${result.records.length} طالب/طالبة من ${result.sheetCount} أوراق. سيتم تطبيق رقم الجلوس المتسلسل الذي تحدده.';
      });
    } catch (error) {
      _showError(error);
    } finally {
      _finishBusy();
    }
  }

  Future<void> _pickWord() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
    );
    if (file == null) return;

    _setBusy('تحليل Word', 'جارٍ اكتشاف تصميم البطاقة وعدد البطاقات...');

    try {
      final bytes = await file.readAsBytes();
      final info = _engine.inspectWord(bytes);

      if (!mounted) return;
      setState(() {
        _wordFile = file;
        _wordBytes = bytes;
        _template = info;
        _status =
            'تم اكتشاف ${info.cardsPerPage} بطاقات في الصفحة. سيتم الحفاظ على تصميم Word نفسه.';
      });
    } catch (error) {
      _showError(error);
    } finally {
      _finishBusy();
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

    if (_seatStart == null) {
      _showError('أدخل رقم بداية جلوس صحيحًا، مثال: 300.');
      return;
    }

    final missing = _missingFields;
    if (missing.isNotEmpty) {
      _showError('بيانات ناقصة: ${missing.join('، ')}');
      return;
    }

    final records = _numberedRecords();
    final startSeat = records.first.seat;
    final endSeat = records.last.seat;

    _setBusy(
      'دمج Word',
      'جارٍ ترقيم الطلاب من $startSeat إلى $endSeat وكتابة البيانات داخل البطاقات...',
    );

    try {
      final mergedDocx = _engine.mergeDocx(
        templateBytes: _wordBytes!,
        records: records,
      );

      final dir = await OutputManager.getOutputDirectory();
      final stamp = OutputManager.timestampName();
      final fileName =
          'student_cards_${startSeat}_${endSeat}_$stamp.docx';
      final docxPath = p.join(dir.path, fileName);

      await File(docxPath).writeAsBytes(mergedDocx, flush: true);

      if (!mounted) return;

      final pageCount = (records.length / _template!.cardsPerPage).ceil();

      setState(() {
        _stage = 'اكتمل';
        _status =
            'تم إنشاء ملف Word بنجاح: ${records.length} سجل، أرقام الجلوس $startSeat–$endSeat، $pageCount صفحة.';
      });

      await _showResult(
        docxPath: docxPath,
        startSeat: startSeat,
        endSeat: endSeat,
      );
    } catch (error) {
      _showError(error);
    } finally {
      _finishBusy();
    }
  }

  Future<void> _shareWord(String path) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        title: 'بطاقات الطلاب',
        text: 'ملف Word النهائي لبطاقات الطلاب',
      ),
    );
  }

  void _setBusy(String stage, String status) {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _stage = stage;
      _status = status;
    });
  }

  void _finishBusy() {
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _showResult({
    required String docxPath,
    required String startSeat,
    required String endSeat,
  }) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(0xFFE6F4EA),
                        child: Icon(
                          Icons.check_rounded,
                          color: Color(0xFF167B3F),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'تم إنشاء ملف Word',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'تم تطبيق ترقيم متسلسل واحد من $startSeat إلى $endSeat وحفظ ملف DOCX النهائي.',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => OpenFilex.open(docxPath),
                    icon: const Icon(Icons.description_rounded),
                    label: const Text('فتح ملف Word'),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: () => _shareWord(docxPath),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('مشاركة ملف Word'),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SavedFilesScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.folder_copy_rounded),
                    label: const Text('الملفات النهائية'),
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

    setState(() {
      _stage = 'يوجد خطأ';
      _status = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missingFields;
    final start = _seatStart;
    final end = _seatEnd;

    final ready = _excelBytes != null &&
        _wordBytes != null &&
        _records.isNotEmpty &&
        _template != null &&
        missing.isEmpty &&
        start != null &&
        !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'دمج بطاقات الطلاب',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'الملفات النهائية',
            icon: const Icon(Icons.folder_copy_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SavedFilesScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF174A8B), Color(0xFF2B69C9)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.description_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Excel + Word → Word مدموج',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'الناتج النهائي DOCX فقط. يحافظ على تصميم Word ويكتب بيانات الطلاب وأرقام الجلوس المتسلسلة داخله.',
                        style: TextStyle(
                          color: Color(0xFFE7EEFA),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _FileStep(
                  number: '1',
                  icon: Icons.table_chart_outlined,
                  title: 'ملف Excel',
                  subtitle: _excelFile == null
                      ? 'اختر ملف الطلاب؛ يدعم عدة أوراق.'
                      : '${_excelFile!.name} — ${_records.length} سجل',
                  done: _excelFile != null,
                  onTap: _busy ? null : _pickExcel,
                ),
                const SizedBox(height: 12),
                _FileStep(
                  number: '2',
                  icon: Icons.description_outlined,
                  title: 'قالب Word',
                  subtitle: _wordFile == null
                      ? 'اختر DOCX الذي يحتوي تصميم البطاقات.'
                      : '${_wordFile!.name} — ${_template?.cardsPerPage ?? 0} بطاقات/صفحة',
                  done: _wordFile != null,
                  onTap: _busy ? null : _pickWord,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            CircleAvatar(radius: 17, child: Text('3')),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'بداية رقم الجلوس',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Icon(Icons.format_list_numbered_rtl),
                          ],
                        ),
                        const SizedBox(height: 13),
                        TextField(
                          controller: _seatStartController,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'ابدأ الترقيم من',
                            hintText: 'مثال: 300',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          start == null
                              ? 'أدخل رقمًا صحيحًا أكبر من صفر.'
                              : _records.isEmpty
                                  ? 'سيبدأ أول طالب بالرقم $start.'
                                  : 'أول طالب = $start  •  آخر طالب = $end  •  الرقم يستمر بين جميع الصفوف.',
                          style: TextStyle(
                            color: start == null
                                ? Theme.of(context).colorScheme.error
                                : const Color(0xFF506079),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_template != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF1A7F46),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'تم اكتشاف ${_template!.cardsPerPage} بطاقات في الصفحة وسيتم استخدام تصميم Word نفسه.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'بيانات ناقصة: ${missing.join('، ')}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (_busy)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _stage,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 10),
                        Text(_status),
                      ],
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: ready ? _generate : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.merge_type_rounded),
                    label: const Text(
                      'دمج البيانات وإنشاء ملف Word',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                const SizedBox(height: 12),
                if (!_busy)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xFFE2E7F0),
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 20),
                        const SizedBox(width: 9),
                        Expanded(child: Text(_status)),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SavedFilesScreen(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            child: Icon(Icons.folder_copy_rounded),
                          ),
                          SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'الملفات النهائية',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'عرض ملفات Word الناتجة وفتحها أو مشاركتها.',
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_left_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'تصميم وبرمجة م.محمود دغَبس\n774813824',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A8494),
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                    ),
                  ),
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
  final bool done;
  final VoidCallback? onTap;

  const _FileStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    done ? const Color(0xFFE6F4EA) : null,
                child: done
                    ? const Icon(
                        Icons.check,
                        color: Color(0xFF167B3F),
                      )
                    : Text(number),
              ),
              const SizedBox(width: 13),
              Icon(icon, size: 30),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667389),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
