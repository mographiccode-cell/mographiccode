import 'dart:io';

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
  final TextEditingController _committeeCountController =
      TextEditingController();
  bool _autoDistributeCommittees = false;

  PlatformFile? _excelFile;
  PlatformFile? _wordFile;
  Uint8List? _excelBytes;
  Uint8List? _wordBytes;

  ExcelImportResult? _excel;
  TemplateInfo? _template;

  bool _busy = false;
  String _stage = '';
  String _status =
      'اختر ملف Excel ثم Word وحدد بداية رقم الجلوس. توزيع اللجان اختياري.';

  @override
  void dispose() {
    _seatStartController.dispose();
    _committeeCountController.dispose();
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

  int? get _committeeCount {
    final value = int.tryParse(_committeeCountController.text.trim());
    if (value == null || value < 1) return null;
    return value;
  }

  bool get _committeeCountValid {
    if (!_autoDistributeCommittees) return true;

    final count = _committeeCount;
    return count != null &&
        _records.isNotEmpty &&
        count <= _records.length &&
        count <= 999;
  }

  List<int> get _committeeSizes {
    if (!_autoDistributeCommittees) return const [];

    final count = _committeeCount;
    if (count == null || _records.isEmpty) return const [];
    return _engine.committeeSizes(_records.length, count);
  }

  List<String> get _missingFields {
    final excel = _excel;
    final template = _template;
    if (excel == null || template == null) return const [];
    return _engine.missingFields(
      excel,
      template,
      committeeWillBeGenerated: _autoDistributeCommittees,
    );
  }

  List<MergeRecord> _preparedRecords() {
    final start = _seatStart;

    if (start == null) {
      throw Exception('أدخل رقم بداية جلوس صحيحًا، مثال: 300.');
    }

    final numbered = _engine.renumberSeats(_records, start);

    if (!_autoDistributeCommittees) {
      return numbered;
    }

    final committees = _committeeCount;
    if (committees == null) {
      throw Exception('أدخل عدد لجان صحيحًا.');
    }
    if (committees > _records.length) {
      throw Exception(
        'عدد اللجان لا يمكن أن يكون أكبر من عدد الطلاب (${_records.length}).',
      );
    }
    if (committees > 999) {
      throw Exception(
        'التسمية العربية التلقائية للجان تدعم حتى 999 لجنة.',
      );
    }

    return _engine.distributeCommittees(numbered, committees);
  }

  String _committeePreviewText() {
    if (!_autoDistributeCommittees) {
      return 'اختياري: عند إيقافه سيحتفظ التطبيق بقيمة اللجنة الموجودة في Excel كما هي.';
    }

    final count = _committeeCount;

    if (_records.isEmpty) {
      return 'بعد اختيار Excel سيظهر توزيع الطلاب على اللجان هنا.';
    }
    if (count == null) {
      return 'أدخل عددًا صحيحًا للجان.';
    }
    if (count > _records.length) {
      return 'عدد اللجان أكبر من عدد الطلاب.';
    }
    if (count > 999) {
      return 'يدعم التوزيع والتسمية العربية حتى 999 لجنة.';
    }

    final sizes = _committeeSizes;
    if (sizes.isEmpty) return '';

    final minSize = sizes.reduce((a, b) => a < b ? a : b);
    final maxSize = sizes.reduce((a, b) => a > b ? a : b);
    final maxCount = sizes.where((size) => size == maxSize).length;
    final minCount = sizes.where((size) => size == minSize).length;

    if (minSize == maxSize) {
      return '${_records.length} طالب ÷ $count لجان = $maxSize طالب في كل لجنة.';
    }

    return '${_records.length} طالب ÷ $count لجان = '
        '$maxCount لجان × $maxSize طالب، و$minCount لجان × $minSize طالب.';
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
            'تم اكتشاف ${result.records.length} طالب/طالبة من ${result.sheetCount} أوراق.';
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

    if (_autoDistributeCommittees && !_committeeCountValid) {
      _showError(
        'أدخل عدد لجان من 1 إلى ${_records.length} وبحد أقصى 999.',
      );
      return;
    }

    final missing = _missingFields;
    if (missing.isNotEmpty) {
      _showError('بيانات ناقصة: ${missing.join('، ')}');
      return;
    }

    final records = _preparedRecords();
    final startSeat = records.first.seat;
    final endSeat = records.last.seat;
    final committeeCount =
        _autoDistributeCommittees ? _committeeCount : null;

    _setBusy(
      'دمج Word',
      _autoDistributeCommittees
          ? 'جارٍ ترقيم الطلاب من $startSeat إلى $endSeat وتوزيعهم بالتساوي على $committeeCount لجان...'
          : 'جارٍ ترقيم الطلاب من $startSeat إلى $endSeat ودمج بيانات Excel مع الاحتفاظ باللجان الأصلية...',
    );

    try {
      final mergedDocx = _engine.mergeDocx(
        templateBytes: _wordBytes!,
        records: records,
      );

      final dir = await OutputManager.getOutputDirectory();
      final stamp = OutputManager.timestampName();
      final committeePart = _autoDistributeCommittees
          ? '_committees_${committeeCount}'
          : '_original_committees';
      final fileName =
          'student_cards_${startSeat}_${endSeat}${committeePart}_$stamp.docx';
      final docxPath = p.join(dir.path, fileName);

      await File(docxPath).writeAsBytes(mergedDocx, flush: true);

      if (!mounted) return;

      final pageCount = (records.length / _template!.cardsPerPage).ceil();

      setState(() {
        _stage = 'اكتمل';
        _status = _autoDistributeCommittees
            ? 'تم إنشاء Word: ${records.length} طالب، أرقام الجلوس $startSeat–$endSeat، $committeeCount لجان موزعة بالتساوي، $pageCount صفحة.'
            : 'تم إنشاء Word: ${records.length} طالب، أرقام الجلوس $startSeat–$endSeat، مع الاحتفاظ باللجان الأصلية، $pageCount صفحة.';
      });

      await _showResult(
        docxPath: docxPath,
        startSeat: startSeat,
        endSeat: endSeat,
        committeeCount: committeeCount,
        committeeSizes: _committeeSizes,
        autoDistributed: _autoDistributeCommittees,
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
    required int? committeeCount,
    required List<int> committeeSizes,
    required bool autoDistributed,
  }) async {
    final minSize = committeeSizes.isEmpty
        ? null
        : committeeSizes.reduce((a, b) => a < b ? a : b);
    final maxSize = committeeSizes.isEmpty
        ? null
        : committeeSizes.reduce((a, b) => a > b ? a : b);

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
                    autoDistributed
                        ? 'أرقام الجلوس: $startSeat–$endSeat\n'
                            'عدد اللجان: $committeeCount\n'
                            'عدد الطلاب في اللجنة: من $minSize إلى $maxSize فقط.'
                        : 'أرقام الجلوس: $startSeat–$endSeat\n'
                            'تم الاحتفاظ بقيم اللجان الأصلية من Excel.',
                  ),
                  if (autoDistributed && committeeSizes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: List.generate(
                        committeeSizes.length,
                        (index) => Chip(
                          label: Text(
                            'اللجنة ${_engine.committeeName(index + 1)}: ${committeeSizes[index]}',
                          ),
                        ),
                      ),
                    ),
                  ],
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
    final committeeCount = _committeeCount;

    final ready = _excelBytes != null &&
        _wordBytes != null &&
        _records.isNotEmpty &&
        _template != null &&
        missing.isEmpty &&
        start != null &&
        _committeeCountValid &&
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
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Excel + Word → دمج بطاقات مرن',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'حدد بداية رقم الجلوس، ويمكنك اختياريًا توزيع الطلاب على لجان متساوية بأسماء عربية ثم دمجهم داخل تصميم Word.',
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
                _NumberSettingCard(
                  number: '3',
                  title: 'بداية رقم الجلوس',
                  icon: Icons.format_list_numbered_rtl,
                  controller: _seatStartController,
                  hint: 'مثال: 300',
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  footer: start == null
                      ? 'أدخل رقمًا صحيحًا أكبر من صفر.'
                      : _records.isEmpty
                          ? 'سيبدأ أول طالب بالرقم $start.'
                          : 'أول طالب = $start  •  آخر طالب = $end  •  الرقم لا يعاد عند تغيير الصف.',
                  error: start == null,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 17,
                              child: Text('4'),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'توزيع اللجان تلقائيًا',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'اختياري',
                                    style: TextStyle(
                                      color: Color(0xFF667389),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _autoDistributeCommittees,
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _autoDistributeCommittees = value;
                                      });
                                    },
                            ),
                          ],
                        ),
                        if (_autoDistributeCommittees) ...[
                          const SizedBox(height: 13),
                          TextField(
                            controller: _committeeCountController,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'عدد اللجان',
                              hintText: 'مثال: 10',
                              prefixIcon: Icon(
                                Icons.groups_2_outlined,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _committeePreviewText(),
                          style: TextStyle(
                            color: _autoDistributeCommittees &&
                                    !_committeeCountValid
                                ? Theme.of(context).colorScheme.error
                                : const Color(0xFF506079),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_committeeSizes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: List.generate(
                          _committeeSizes.length,
                          (index) => Chip(
                            avatar: const Icon(
                              Icons.groups_rounded,
                              size: 17,
                            ),
                            label: Text(
                              'اللجنة ${_engine.committeeName(index + 1)}: ${_committeeSizes[index]}',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
                    label: Text(
                      _autoDistributeCommittees
                          ? 'توزيع اللجان ودمج ملف Word'
                          : 'دمج ملف Word',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
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

class _NumberSettingCard extends StatelessWidget {
  final String number;
  final String title;
  final IconData icon;
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String footer;
  final bool error;

  const _NumberSettingCard({
    required this.number,
    required this.title,
    required this.icon,
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.onChanged,
    required this.footer,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 17, child: Text(number)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(icon),
              ],
            ),
            const SizedBox(height: 13),
            TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: Icon(icon),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              footer,
              style: TextStyle(
                color: error
                    ? Theme.of(context).colorScheme.error
                    : const Color(0xFF506079),
                fontWeight: FontWeight.w600,
              ),
            ),
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
