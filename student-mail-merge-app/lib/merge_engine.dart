import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:xml/xml.dart';

class MergeRecord {
  final String name;
  final String grade;
  final String committee;
  final String seat;
  final Map<String, String> raw;

  const MergeRecord({
    required this.name,
    required this.grade,
    required this.committee,
    required this.seat,
    this.raw = const {},
  });

  String valueFor(String key) {
    final normalized = normalize(key);

    for (final entry in raw.entries) {
      if (normalize(entry.key) == normalized) return entry.value;
    }

    if (_nameAliases.contains(normalized)) return name;
    if (_gradeAliases.contains(normalized)) return grade;
    if (_committeeAliases.contains(normalized)) return committee;
    if (_seatAliases.contains(normalized)) return seat;

    return '';
  }

  MergeRecord withSeat(String newSeat) {
    final updatedRaw = Map<String, String>.from(raw);

    for (final key in updatedRaw.keys.toList()) {
      if (_seatAliases.contains(normalize(key))) {
        updatedRaw[key] = newSeat;
      }
    }

    updatedRaw['رقم الجلوس'] = newSeat;
    updatedRaw['ارقام الجلوس'] = newSeat;
    updatedRaw['أرقام الجلوس'] = newSeat;

    return MergeRecord(
      name: name,
      grade: grade,
      committee: committee,
      seat: newSeat,
      raw: updatedRaw,
    );
  }

  MergeRecord withCommittee(String newCommittee) {
    final updatedRaw = Map<String, String>.from(raw);

    for (final key in updatedRaw.keys.toList()) {
      if (_committeeAliases.contains(normalize(key))) {
        updatedRaw[key] = newCommittee;
      }
    }

    updatedRaw['اللجنة'] = newCommittee;
    updatedRaw['اللجنه'] = newCommittee;
    updatedRaw['رقم اللجنة'] = newCommittee;

    return MergeRecord(
      name: name,
      grade: grade,
      committee: newCommittee,
      seat: seat,
      raw: updatedRaw,
    );
  }

  static String normalize(String input) => input
      .trim()
      .replaceAll(RegExp(r'[\s_\-–—/\\:：]+'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .toLowerCase();

  static final Set<String> _nameAliases = {
    normalize('الاسم'),
    normalize('اسم الطالب'),
    normalize('اسم الطالبة'),
    normalize('اسم الطالب/الطالبة'),
  };

  static final Set<String> _gradeAliases = {
    normalize('الصف'),
    normalize('الصف الدراسي'),
    normalize('المرحلة'),
  };

  static final Set<String> _committeeAliases = {
    normalize('اللجنة'),
    normalize('رقم اللجنة'),
    normalize('اللجنه'),
  };

  static final Set<String> _seatAliases = {
    normalize('رقم الجلوس'),
    normalize('ارقام الجلوس'),
    normalize('أرقام الجلوس'),
    normalize('رقم الجلوس/الطالب'),
  };
}

class ExcelImportResult {
  final List<MergeRecord> records;
  final int sheetCount;
  final Set<String> detectedFields;

  const ExcelImportResult({
    required this.records,
    required this.sheetCount,
    required this.detectedFields,
  });
}

enum WordTemplateMode { placeholders, labeledCards }

class TemplateInfo {
  final int cardsPerPage;
  final WordTemplateMode mode;
  final List<String> placeholders;
  final Set<String> labeledFields;

  const TemplateInfo({
    required this.cardsPerPage,
    required this.mode,
    this.placeholders = const [],
    this.labeledFields = const {},
  });
}

class MergeEngine {
  static final RegExp _placeholderRegex =
      RegExp(r'\{\{\s*([^{}]+?)\s*\}\}|«\s*([^«»]+?)\s*»');

  static final Map<String, RegExp> _labelRegex = {
    'name': RegExp(r'(اسم\s+الطالب(?:ة)?|الاسم)\s*[:：]\s*'),
    'grade': RegExp(r'(الصف(?:\s+الدراسي)?)\s*[:：]\s*'),
    'committee': RegExp(r'(اللجن[ةه](?:\s+رقم)?)\s*[:：]\s*'),
    'seat': RegExp(r'(رقم\s+الجلوس|أرقام\s+الجلوس|ارقام\s+الجلوس)\s*[:：]\s*'),
  };

  static const List<String> _gradeWords = [
    'الاول',
    'الأول',
    'الثاني',
    'الثالث',
    'الرابع',
    'الخامس',
    'السادس',
    'السابع',
    'الثامن',
    'التاسع',
    'العاشر',
    'اول',
    'أول',
    'ثاني',
    'ثالث',
    'رابع',
    'خامس',
    'سادس',
    'سابع',
    'ثامن',
    'تاسع',
    'عاشر',
  ];

  Future<ExcelImportResult> readExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('ملف Excel لا يحتوي على أوراق بيانات.');
    }

    final allRecords = <MergeRecord>[];
    final fields = <String>{};

    for (final entry in excel.tables.entries) {
      final sheetName = entry.key;
      final table = entry.value;
      if (table.rows.isEmpty) continue;

      final rows = table.rows;
      final maxCols =
          rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
      if (maxCols == 0) continue;

      final gradeHint = _inferGradeHint(sheetName, rows);

      int? headerRow;
      final headerMap = <String, int>{};

      for (var r = 0; r < rows.length && r < 10; r++) {
        final candidate = <String, int>{};
        for (var c = 0; c < rows[r].length; c++) {
          final value = _cellText(rows[r][c]);
          final canonical = _canonicalHeader(value);
          if (canonical != null) candidate[canonical] = c;
        }

        if (candidate.length >= 2) {
          headerRow = r;
          headerMap.addAll(candidate);
          break;
        }
      }

      final scanStart = headerRow == null ? 0 : headerRow + 1;

      final numericScores = List<int>.filled(maxCols, 0);
      final nameScores = List<int>.filled(maxCols, 0);
      final gradeScores = List<int>.filled(maxCols, 0);
      final committeeScores = List<int>.filled(maxCols, 0);

      for (var r = scanStart; r < rows.length; r++) {
        final row = rows[r];

        for (var c = 0; c < maxCols; c++) {
          final text = c < row.length ? _cellText(row[c]) : '';
          if (text.isEmpty) continue;

          if (_looksNumeric(text)) numericScores[c]++;
          if (_looksLikeName(text)) nameScores[c]++;
          if (_looksLikeGrade(text)) gradeScores[c]++;
          if (_looksLikeCommittee(text)) committeeScores[c]++;
        }
      }

      int? bestColumn(List<int> scores, {int minScore = 1}) {
        var best = -1;
        var bestScore = minScore - 1;

        for (var i = 0; i < scores.length; i++) {
          if (scores[i] > bestScore) {
            bestScore = scores[i];
            best = i;
          }
        }

        return best < 0 ? null : best;
      }

      var seatCol = headerMap['seat'];
      final inferredSeat = bestColumn(numericScores, minScore: 2);

      if (seatCol == null ||
          numericScores[seatCol] == 0 ||
          (inferredSeat != null &&
              numericScores[inferredSeat] > numericScores[seatCol] * 2)) {
        seatCol = inferredSeat;
      }

      var nameCol = headerMap['name'];
      nameCol ??= bestColumn(nameScores, minScore: 2);

      var gradeCol = headerMap['grade'];
      if (gradeCol == null || gradeScores[gradeCol] == 0) {
        gradeCol = bestColumn(gradeScores, minScore: 2);
      }

      var committeeCol = headerMap['committee'];
      if (committeeCol == null || committeeScores[committeeCol] == 0) {
        final inferredCommittee = bestColumn(committeeScores, minScore: 2);
        if (inferredCommittee != gradeCol) committeeCol = inferredCommittee;
      }

      if (nameCol == null) continue;

      for (var r = scanStart; r < rows.length; r++) {
        final row = rows[r];

        final seatText = seatCol == null ? '' : _textAt(row, seatCol);
        final nameText = _textAt(row, nameCol);

        if (!_looksLikeName(nameText)) continue;
        if (seatText.isNotEmpty && !_looksNumeric(seatText)) continue;

        final gradeText =
            gradeCol == null ? '' : _textAt(row, gradeCol).trim();
        final committeeText =
            committeeCol == null ? '' : _textAt(row, committeeCol).trim();

        final seat = seatText.isNotEmpty
            ? _normalizeNumber(seatText)
            : (allRecords.length + 1).toString();
        final grade = gradeText.isNotEmpty ? gradeText : gradeHint;
        final committee = committeeText;

        final raw = <String, String>{
          'اسم الطالبة': nameText,
          'اسم الطالب': nameText,
          'الاسم': nameText,
          'الصف': grade,
          'اللجنة': committee,
          'رقم الجلوس': seat,
          'ارقام الجلوس': seat,
        };

        if (headerRow != null) {
          for (final mapEntry in headerMap.entries) {
            final col = mapEntry.value;
            final header =
                col < rows[headerRow].length ? _cellText(rows[headerRow][col]) : '';
            if (header.isNotEmpty) raw[header] = _textAt(row, col);
          }
        }

        allRecords.add(
          MergeRecord(
            name: nameText,
            grade: grade,
            committee: committee,
            seat: seat,
            raw: raw,
          ),
        );

        fields.addAll(['name', 'grade', 'seat']);
        if (committee.isNotEmpty) fields.add('committee');
      }
    }

    if (allRecords.isEmpty) {
      throw Exception(
        'لم أستطع اكتشاف بيانات الطلاب تلقائيًا. يجب أن يحتوي كل طالب على رقم جلوس واسم على الأقل.',
      );
    }

    return ExcelImportResult(
      records: allRecords,
      sheetCount: excel.tables.length,
      detectedFields: fields,
    );
  }

  List<MergeRecord> renumberSeats(
    List<MergeRecord> records,
    int startNumber,
  ) {
    if (startNumber < 1) {
      throw Exception('رقم بداية الجلوس يجب أن يكون 1 أو أكبر.');
    }

    return List<MergeRecord>.generate(
      records.length,
      (index) => records[index].withSeat((startNumber + index).toString()),
      growable: false,
    );
  }

  List<MergeRecord> distributeCommittees(
    List<MergeRecord> records,
    int committeeCount,
  ) {
    if (records.isEmpty) {
      throw Exception('لا توجد بيانات طلاب لتوزيعها على اللجان.');
    }
    if (committeeCount < 1) {
      throw Exception('عدد اللجان يجب أن يكون 1 أو أكبر.');
    }
    if (committeeCount > records.length) {
      throw Exception(
        'عدد اللجان لا يمكن أن يكون أكبر من عدد الطلاب (${records.length}).',
      );
    }

    final baseSize = records.length ~/ committeeCount;
    final remainder = records.length % committeeCount;
    final distributed = <MergeRecord>[];

    var sourceIndex = 0;
    for (var committeeIndex = 0;
        committeeIndex < committeeCount;
        committeeIndex++) {
      final committeeSize =
          baseSize + (committeeIndex < remainder ? 1 : 0);
      final committeeLabel = committeeName(committeeIndex + 1);

      for (var i = 0; i < committeeSize; i++) {
        distributed.add(
          records[sourceIndex].withCommittee(committeeLabel),
        );
        sourceIndex++;
      }
    }

    return distributed;
  }

  List<int> committeeSizes(int studentCount, int committeeCount) {
    if (studentCount < 1 ||
        committeeCount < 1 ||
        committeeCount > studentCount) {
      return const [];
    }

    final baseSize = studentCount ~/ committeeCount;
    final remainder = studentCount % committeeCount;

    return List<int>.generate(
      committeeCount,
      (index) => baseSize + (index < remainder ? 1 : 0),
      growable: false,
    );
  }

  String committeeName(int number) {
    if (number < 1) {
      throw Exception('رقم اللجنة يجب أن يكون 1 أو أكبر.');
    }
    if (number > 999) {
      throw Exception(
        'التسمية العربية التلقائية للجان تدعم حتى 999 لجنة.',
      );
    }

    return _feminineOrdinal(number);
  }

  String _feminineOrdinal(int number) {
    const units = <int, String>{
      1: 'الأولى',
      2: 'الثانية',
      3: 'الثالثة',
      4: 'الرابعة',
      5: 'الخامسة',
      6: 'السادسة',
      7: 'السابعة',
      8: 'الثامنة',
      9: 'التاسعة',
      10: 'العاشرة',
      11: 'الحادية عشرة',
      12: 'الثانية عشرة',
      13: 'الثالثة عشرة',
      14: 'الرابعة عشرة',
      15: 'الخامسة عشرة',
      16: 'السادسة عشرة',
      17: 'السابعة عشرة',
      18: 'الثامنة عشرة',
      19: 'التاسعة عشرة',
    };

    const tens = <int, String>{
      20: 'العشرون',
      30: 'الثلاثون',
      40: 'الأربعون',
      50: 'الخمسون',
      60: 'الستون',
      70: 'السبعون',
      80: 'الثمانون',
      90: 'التسعون',
    };

    const hundreds = <int, String>{
      100: 'المائة',
      200: 'المائتان',
      300: 'الثلاثمائة',
      400: 'الأربعمائة',
      500: 'الخمسمائة',
      600: 'الستمائة',
      700: 'السبعمائة',
      800: 'الثمانمائة',
      900: 'التسعمائة',
    };

    if (number < 20) {
      return units[number]!;
    }

    if (number < 100) {
      final tensValue = (number ~/ 10) * 10;
      final unitValue = number % 10;

      if (unitValue == 0) {
        return tens[tensValue]!;
      }

      return '${units[unitValue]!} و${tens[tensValue]!}';
    }

    final hundredsValue = (number ~/ 100) * 100;
    final remainder = number % 100;
    final hundredWord = hundreds[hundredsValue]!;

    if (remainder == 0) {
      return hundredWord;
    }

    return '${_feminineOrdinal(remainder)} بعد $hundredWord';
  }

  TemplateInfo inspectWord(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentFile = _findFile(archive, 'word/document.xml');
    final document = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );

    final body = document.descendants
        .whereType<XmlElement>()
        .firstWhere((element) => element.name.local == 'body');

    final table = _findTemplateTable(body);
    if (table == null) {
      throw Exception(
        'لم أتعرف على صفحة البطاقات في Word. يجب أن تكون البطاقات داخل جدول كما في الملف المرفق.',
      );
    }

    final cardCells = _cardCells(table);
    if (cardCells.isEmpty) {
      throw Exception('لم أتعرف على بطاقات قابلة للدمج داخل Word.');
    }

    final placeholders = <String>{};
    final labeledFields = <String>{};

    for (final cell in cardCells) {
      final text = _elementText(cell);

      for (final match in _placeholderRegex.allMatches(text)) {
        final field = (match.group(1) ?? match.group(2) ?? '').trim();
        if (field.isNotEmpty) placeholders.add(field);
      }

      for (final entry in _labelRegex.entries) {
        if (entry.value.hasMatch(text)) labeledFields.add(entry.key);
      }
    }

    return TemplateInfo(
      cardsPerPage: cardCells.length,
      mode: placeholders.isNotEmpty
          ? WordTemplateMode.placeholders
          : WordTemplateMode.labeledCards,
      placeholders: placeholders.toList()..sort(),
      labeledFields: labeledFields,
    );
  }

  List<String> missingFields(
    ExcelImportResult excel,
    TemplateInfo template, {
    bool committeeWillBeGenerated = false,
  }) {
    final missing = <String>[];

    if (template.mode == WordTemplateMode.placeholders) {
      for (final field in template.placeholders) {
        final normalized = MergeRecord.normalize(field);

        if (committeeWillBeGenerated &&
            MergeRecord._committeeAliases.contains(normalized)) {
          continue;
        }

        final hasValue = excel.records.any(
          (record) => record.valueFor(field).isNotEmpty,
        );
        if (!hasValue) missing.add(field);
      }
      return missing;
    }

    bool hasField(String canonical) {
      switch (canonical) {
        case 'name':
          return excel.records.any((record) => record.name.isNotEmpty);
        case 'grade':
          return excel.records.any((record) => record.grade.isNotEmpty);
        case 'committee':
          // Empty committee is valid for a whole sheet, as in the supplied sixth-grade sheet.
          return true;
        case 'seat':
          return excel.records.any((record) => record.seat.isNotEmpty);
      }
      return true;
    }

    for (final field in template.labeledFields) {
      if (!hasField(field)) missing.add(field);
    }

    return missing;
  }

  Uint8List mergeDocx({
    required Uint8List templateBytes,
    required List<MergeRecord> records,
  }) {
    if (records.isEmpty) {
      throw Exception('لا توجد بيانات طلاب للدمج.');
    }

    final archive = ZipDecoder().decodeBytes(templateBytes);
    final documentFile = _findFile(archive, 'word/document.xml');
    final document = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );

    final body = document.descendants
        .whereType<XmlElement>()
        .firstWhere((element) => element.name.local == 'body');

    final directChildren = body.children.toList();
    final templateTable = _findTemplateTable(body);

    if (templateTable == null) {
      throw Exception('تعذر العثور على جدول البطاقات في Word.');
    }

    final templateIndex = directChildren.indexOf(templateTable);
    XmlElement? sectionBreakParagraph;

    for (var i = templateIndex + 1; i < directChildren.length; i++) {
      final node = directChildren[i];

      if (node is XmlElement && node.name.local == 'p') {
        final hasSectPr = node.descendants
            .whereType<XmlElement>()
            .any((element) => element.name.local == 'sectPr');

        if (hasSectPr) {
          sectionBreakParagraph = node;
          break;
        }
      }

      if (node is XmlElement && node.name.local == 'tbl') break;
    }

    XmlElement? finalSectPr;
    for (final node in directChildren.reversed) {
      if (node is XmlElement && node.name.local == 'sectPr') {
        finalSectPr = node;
        break;
      }
    }

    final templateCardCount = _cardCells(templateTable).length;
    if (templateCardCount == 0) {
      throw Exception('صفحة Word لا تحتوي على بطاقات قابلة للدمج.');
    }

    body.children.clear();

    var pageIndex = 0;

    for (var offset = 0;
        offset < records.length;
        offset += templateCardCount) {
      final clonedTable = templateTable.copy();
      final cells = _cardCells(clonedTable);

      if (cells.length != templateCardCount) {
        throw Exception('تغيّر عدد البطاقات أثناء نسخ تصميم Word.');
      }

      for (var cardIndex = 0; cardIndex < cells.length; cardIndex++) {
        final recordIndex = offset + cardIndex;

        if (recordIndex < records.length) {
          _mergeCard(cells[cardIndex], records[recordIndex]);
        } else {
          _clearCardValues(cells[cardIndex]);
        }
      }

      if (pageIndex > 0) {
        if (sectionBreakParagraph != null) {
          body.children.add(sectionBreakParagraph.copy());
        } else {
          body.children.add(_pageBreakBeforeParagraph());
        }
      }

      body.children.add(clonedTable);
      pageIndex++;
    }

    if (finalSectPr != null) {
      body.children.add(finalSectPr.copy());
    }

    final mergedXml = document.toXmlString(pretty: false);
    final output = Archive();

    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        final data = utf8.encode(mergedXml);
        output.addFile(ArchiveFile(file.name, data.length, data));
      } else {
        final data = file.content as List<int>;
        output.addFile(ArchiveFile(file.name, data.length, data));
      }
    }

    final zipped = ZipEncoder().encode(output);
    if (zipped.isEmpty) {
      throw Exception('تعذر إنشاء ملف Word المدموج.');
    }

    return Uint8List.fromList(zipped);
  }

  void _mergeCard(XmlElement cell, MergeRecord record) {
    _replacePlaceholders(cell, record);

    for (final paragraph in cell.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'p')) {
      final originalText = _paragraphText(paragraph);
      if (originalText.isEmpty) continue;

      final matches = <_LabeledMatch>[];

      for (final entry in _labelRegex.entries) {
        final match = entry.value.firstMatch(originalText);
        if (match != null) {
          matches.add(
            _LabeledMatch(
              field: entry.key,
              start: match.start,
              valueStart: match.end,
            ),
          );
        }
      }

      if (matches.isEmpty) continue;
      matches.sort((a, b) => a.start.compareTo(b.start));

      for (var i = matches.length - 1; i >= 0; i--) {
        final current = matches[i];
        final valueEnd =
            i + 1 < matches.length ? matches[i + 1].start : originalText.length;

        var replacement = _canonicalValue(record, current.field);

        if (current.field == 'seat') {
          final oldValue = originalText
              .substring(current.valueStart, valueEnd)
              .trim();

          if (oldValue.contains('(') || oldValue.contains(')')) {
            replacement = replacement.isEmpty ? '' : '( $replacement )';
          }
        }

        _replaceTextRange(
          paragraph,
          current.valueStart,
          valueEnd,
          replacement,
        );
      }
    }
  }

  void _clearCardValues(XmlElement cell) {
    _replacePlaceholders(cell, const MergeRecord(
      name: '',
      grade: '',
      committee: '',
      seat: '',
    ));

    for (final paragraph in cell.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'p')) {
      final originalText = _paragraphText(paragraph);
      final matches = <_LabeledMatch>[];

      for (final entry in _labelRegex.entries) {
        final match = entry.value.firstMatch(originalText);
        if (match != null) {
          matches.add(
            _LabeledMatch(
              field: entry.key,
              start: match.start,
              valueStart: match.end,
            ),
          );
        }
      }

      if (matches.isEmpty) continue;
      matches.sort((a, b) => a.start.compareTo(b.start));

      for (var i = matches.length - 1; i >= 0; i--) {
        final valueEnd =
            i + 1 < matches.length ? matches[i + 1].start : originalText.length;

        _replaceTextRange(
          paragraph,
          matches[i].valueStart,
          valueEnd,
          '',
        );
      }
    }
  }

  void _replacePlaceholders(XmlElement cell, MergeRecord record) {
    for (final paragraph in cell.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'p')) {
      final original = _paragraphText(paragraph);
      final matches = _placeholderRegex.allMatches(original).toList();

      for (final match in matches.reversed) {
        final field = (match.group(1) ?? match.group(2) ?? '').trim();
        _replaceTextRange(
          paragraph,
          match.start,
          match.end,
          record.valueFor(field),
        );
      }
    }
  }

  void _replaceTextRange(
    XmlElement paragraph,
    int start,
    int end,
    String replacement,
  ) {
    final textNodes = paragraph.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 't')
        .toList();

    if (textNodes.isEmpty || end < start) return;

    final parts =
        textNodes.map((node) => node.innerText).toList(growable: false);
    final starts = <int>[];

    var cursor = 0;
    for (final part in parts) {
      starts.add(cursor);
      cursor += part.length;
    }

    int nodeForOffset(int offset) {
      if (offset <= 0) return 0;

      for (var i = 0; i < parts.length; i++) {
        final nodeStart = starts[i];
        final nodeEnd = nodeStart + parts[i].length;

        if (offset < nodeEnd ||
            (offset == nodeEnd && i == parts.length - 1)) {
          return i;
        }
      }

      return parts.length - 1;
    }

    final startNode = nodeForOffset(start);
    final endNode = nodeForOffset(end > start ? end - 1 : end);

    final startLocal = (start - starts[startNode])
        .clamp(0, textNodes[startNode].innerText.length);

    final endLocal = (end - starts[endNode])
        .clamp(0, textNodes[endNode].innerText.length);

    if (startNode == endNode) {
      final current = textNodes[startNode].innerText;
      textNodes[startNode].innerText =
          current.replaceRange(startLocal, endLocal, replacement);
      return;
    }

    final first = textNodes[startNode].innerText;
    final last = textNodes[endNode].innerText;

    textNodes[startNode].innerText =
        first.substring(0, startLocal) + replacement;

    for (var i = startNode + 1; i < endNode; i++) {
      textNodes[i].innerText = '';
    }

    textNodes[endNode].innerText = last.substring(endLocal);
  }

  XmlElement? _findTemplateTable(XmlElement body) {
    XmlElement? best;
    var bestCount = 0;

    for (final child in body.childElements) {
      if (child.name.local != 'tbl') continue;

      final count = _cardCells(child).length;
      if (count > bestCount) {
        best = child;
        bestCount = count;
      }

      if (count >= 2) return child;
    }

    return bestCount > 0 ? best : null;
  }

  List<XmlElement> _cardCells(XmlElement table) {
    final result = <XmlElement>[];

    for (final row in table.childElements
        .where((element) => element.name.local == 'tr')) {
      for (final cell in row.childElements
          .where((element) => element.name.local == 'tc')) {
        final text = _elementText(cell);
        final placeholders = _placeholderRegex.hasMatch(text);

        var labelHits = 0;
        if (_labelRegex['name']!.hasMatch(text)) labelHits++;
        if (_labelRegex['grade']!.hasMatch(text)) labelHits++;
        if (_labelRegex['committee']!.hasMatch(text)) labelHits++;
        if (_labelRegex['seat']!.hasMatch(text)) labelHits++;

        if (placeholders || labelHits >= 2) result.add(cell);
      }
    }

    return result;
  }

  static String _canonicalValue(MergeRecord record, String field) {
    switch (field) {
      case 'name':
        return record.name;
      case 'grade':
        return record.grade;
      case 'committee':
        return record.committee;
      case 'seat':
        return record.seat;
    }
    return '';
  }

  static String _paragraphText(XmlElement paragraph) {
    return paragraph.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 't')
        .map((element) => element.innerText)
        .join();
  }

  static String _elementText(XmlElement element) {
    return element.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 't')
        .map((node) => node.innerText)
        .join('\n');
  }

  static String _cellText(Data? cell) => cell?.displayText.trim() ?? '';

  static String _textAt(List<Data?> row, int column) {
    if (column < 0 || column >= row.length) return '';
    return _cellText(row[column]);
  }

  static bool _looksNumeric(String text) {
    final normalized =
        text.replaceAllMapped(RegExp(r'[٠-٩]'), (match) {
      const eastern = '٠١٢٣٤٥٦٧٨٩';
      return eastern.indexOf(match.group(0)!).toString();
    }).trim();

    return RegExp(r'^\d+(?:\.0+)?$').hasMatch(normalized);
  }

  static String _normalizeNumber(String text) {
    var normalized =
        text.replaceAllMapped(RegExp(r'[٠-٩]'), (match) {
      const eastern = '٠١٢٣٤٥٦٧٨٩';
      return eastern.indexOf(match.group(0)!).toString();
    }).trim();

    if (RegExp(r'^\d+\.0+$').hasMatch(normalized)) {
      normalized = normalized.substring(0, normalized.indexOf('.'));
    }

    return normalized;
  }

  static bool _looksLikeName(String text) {
    final value = text.trim();
    if (value.length < 7) return false;
    if (_looksNumeric(value)) return false;
    if (_canonicalHeader(value) != null) return false;
    if (_looksLikeGrade(value) || _looksLikeCommittee(value)) return false;

    return value.split(RegExp(r'\s+')).length >= 2;
  }

  static bool _looksLikeGrade(String text) {
    final normalized = MergeRecord.normalize(text);

    return _gradeWords.any(
      (word) => MergeRecord.normalize(word) == normalized,
    );
  }

  static bool _looksLikeCommittee(String text) {
    final normalized = MergeRecord.normalize(text);
    const committees = [
      'الاولى',
      'الأولى',
      'الثانية',
      'الثالثة',
      'الرابعة',
      'الخامسة',
      'السادسة',
      'السابعة',
      'الثامنة',
      'التاسعة',
      'العاشرة',
    ];

    return committees.any(
      (word) => MergeRecord.normalize(word) == normalized,
    );
  }

  static String _inferGradeHint(
    String sheetName,
    List<List<Data?>> rows,
  ) {
    final candidates = <String>[sheetName];

    for (var r = 0; r < rows.length && r < 8; r++) {
      for (final cell in rows[r]) {
        final text = _cellText(cell);
        if (text.isNotEmpty) candidates.add(text);
      }
    }

    const canonicalGrades = {
      'اول': 'الاول',
      'الأول': 'الاول',
      'الاول': 'الاول',
      'ثاني': 'الثاني',
      'الثاني': 'الثاني',
      'ثالث': 'الثالث',
      'الثالث': 'الثالث',
      'رابع': 'الرابع',
      'الرابع': 'الرابع',
      'خامس': 'الخامس',
      'الخامس': 'الخامس',
      'سادس': 'السادس',
      'السادس': 'السادس',
      'سابع': 'السابع',
      'السابع': 'السابع',
      'ثامن': 'الثامن',
      'الثامن': 'الثامن',
      'تاسع': 'التاسع',
      'التاسع': 'التاسع',
      'عاشر': 'العاشر',
      'العاشر': 'العاشر',
    };

    for (final candidate in candidates) {
      final normalized = MergeRecord.normalize(candidate);

      for (final entry in canonicalGrades.entries) {
        final key = MergeRecord.normalize(entry.key);

        if (normalized == key || normalized.contains(key)) {
          return entry.value;
        }
      }
    }

    return '';
  }

  static String? _canonicalHeader(String text) {
    final normalized = MergeRecord.normalize(text);
    if (normalized.isEmpty) return null;

    if (MergeRecord._nameAliases.contains(normalized)) return 'name';
    if (MergeRecord._gradeAliases.contains(normalized)) return 'grade';
    if (MergeRecord._committeeAliases.contains(normalized)) {
      return 'committee';
    }
    if (MergeRecord._seatAliases.contains(normalized)) return 'seat';

    return null;
  }

  static XmlElement _pageBreakBeforeParagraph() {
    return XmlDocument.parse(
      '<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:pPr><w:pageBreakBefore/></w:pPr>'
      '</w:p>',
    ).rootElement;
  }

  static ArchiveFile _findFile(Archive archive, String name) {
    for (final file in archive) {
      if (file.name == name) return file;
    }

    throw Exception('ملف Word غير صالح: $name غير موجود.');
  }
}

class _LabeledMatch {
  final String field;
  final int start;
  final int valueStart;

  const _LabeledMatch({
    required this.field,
    required this.start,
    required this.valueStart,
  });
}
