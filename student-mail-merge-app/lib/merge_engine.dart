import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class MergeRecord {
  final Map<String, String> values;
  const MergeRecord(this.values);

  String valueFor(String key) {
    final exact = values[key];
    if (exact != null) return exact;
    final normalized = normalize(key);
    for (final entry in values.entries) {
      if (normalize(entry.key) == normalized) return entry.value;
    }
    return '';
  }

  static String normalize(String input) => input
      .trim()
      .replaceAll(RegExp(r'[\s_\-]+'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .toLowerCase();
}

class ExcelImportResult {
  final List<String> headers;
  final List<MergeRecord> records;
  const ExcelImportResult(this.headers, this.records);
}

class TemplateInfo {
  final List<String> placeholders;
  final int cardsPerPage;
  const TemplateInfo(this.placeholders, this.cardsPerPage);
}

class MergeEngine {
  static final RegExp _placeholderRegex =
      RegExp(r'\{\{\s*([^{}]+?)\s*\}\}|«\s*([^«»]+?)\s*»');

  Future<ExcelImportResult> readExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('ملف Excel لا يحتوي على أوراق بيانات.');
    }

    final table = excel.tables.values.first;
    if (table.rows.isEmpty) {
      throw Exception('ورقة Excel فارغة.');
    }

    String textOf(Data? cell) => cell?.displayText.trim() ?? '';

    final headers = table.rows.first.map(textOf).toList();
    if (headers.every((e) => e.isEmpty)) {
      throw Exception('الصف الأول في Excel يجب أن يحتوي على أسماء الأعمدة.');
    }

    final normalizedHeaders = <String>{};
    for (final header in headers.where((e) => e.trim().isNotEmpty)) {
      final normalized = MergeRecord.normalize(header);
      if (!normalizedHeaders.add(normalized)) {
        throw Exception('يوجد عمود مكرر أو متشابه في Excel: $header');
      }
    }

    final records = <MergeRecord>[];
    for (final row in table.rows.skip(1)) {
      final values = <String, String>{};
      var hasAnyValue = false;

      for (var i = 0; i < headers.length; i++) {
        final header = headers[i].trim();
        if (header.isEmpty) continue;

        final value = i < row.length ? textOf(row[i]) : '';
        if (value.isNotEmpty) hasAnyValue = true;
        values[header] = value;
      }

      if (hasAnyValue) records.add(MergeRecord(values));
    }

    if (records.isEmpty) {
      throw Exception('لم يتم العثور على بيانات طلاب بعد صف العناوين.');
    }

    return ExcelImportResult(headers, records);
  }

  TemplateInfo inspectWord(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentFile = _findFile(archive, 'word/document.xml');
    final doc = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );

    final placeholders = <String>{};
    for (final paragraph in doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p')) {
      final text = _paragraphText(paragraph);
      for (final match in _placeholderRegex.allMatches(text)) {
        final field = (match.group(1) ?? match.group(2) ?? '').trim();
        if (field.isNotEmpty) placeholders.add(field);
      }
    }

    final body = doc.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'body');

    final table = _firstTopLevelTable(body.children);
    if (table == null) {
      throw Exception(
        'قالب Word يجب أن يحتوي على البطاقات داخل جدول في الصفحة، مثل 5 صفوف × عمودين.',
      );
    }

    final cards = _topLevelCells(table).length;
    if (cards == 0) {
      throw Exception('جدول Word لا يحتوي على بطاقات قابلة للدمج.');
    }

    if (placeholders.isEmpty) {
      throw Exception(
        'لم يتم العثور على حقول دمج في Word. استخدم مثل {{الاسم}} أو «الاسم».',
      );
    }

    return TemplateInfo(placeholders.toList()..sort(), cards);
  }

  List<String> missingFields(
    List<String> excelHeaders,
    List<String> wordFields,
  ) {
    final normalizedHeaders =
        excelHeaders.map(MergeRecord.normalize).toSet();

    return wordFields
        .where(
          (field) => !normalizedHeaders.contains(MergeRecord.normalize(field)),
        )
        .toList();
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
    final sourceDoc = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );

    final body = sourceDoc.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'body');

    final originalChildren = body.children.map((node) => node.copy()).toList();
    final sectionProps = originalChildren
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'sectPr')
        .toList();

    final pageChildren = originalChildren
        .where(
          (node) =>
              !(node is XmlElement && node.name.local == 'sectPr'),
        )
        .toList();

    final probe = _firstTopLevelTable(pageChildren);
    if (probe == null) {
      throw Exception('تعذر العثور على جدول البطاقات داخل Word.');
    }

    final cardsPerPage = _topLevelCells(probe).length;
    if (cardsPerPage == 0) {
      throw Exception('جدول Word لا يحتوي على خلايا بطاقات.');
    }

    body.children.clear();

    var offset = 0;
    var pageIndex = 0;

    while (offset < records.length) {
      final clonedPage = pageChildren.map((node) => node.copy()).toList();
      final table = _firstTopLevelTable(clonedPage);
      if (table == null) {
        throw Exception('تعذر نسخ جدول البطاقات.');
      }

      final cells = _topLevelCells(table);
      if (cells.length != cardsPerPage) {
        throw Exception('بنية جدول البطاقات تغيرت أثناء الدمج.');
      }

      for (var cardIndex = 0; cardIndex < cells.length; cardIndex++) {
        final studentIndex = offset + cardIndex;

        if (studentIndex < records.length) {
          _replaceInCell(cells[cardIndex], records[studentIndex]);
        } else {
          _clearPlaceholders(cells[cardIndex]);
        }
      }

      if (pageIndex > 0) {
        body.children.add(_pageBreak());
      }

      body.children.addAll(clonedPage);
      offset += cardsPerPage;
      pageIndex++;
    }

    if (sectionProps.isNotEmpty) {
      body.children.add(sectionProps.first.copy());
    }

    final mergedXml = sourceDoc.toXmlString(pretty: false);
    final outputArchive = Archive();

    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        final data = utf8.encode(mergedXml);
        outputArchive.addFile(
          ArchiveFile(file.name, data.length, data),
        );
      } else {
        final data = file.content as List<int>;
        outputArchive.addFile(
          ArchiveFile(file.name, data.length, data),
        );
      }
    }

    final zipped = ZipEncoder().encode(outputArchive);
    if (zipped.isEmpty) {
      throw Exception('تعذر إنشاء ملف Word المدموج.');
    }

    return Uint8List.fromList(zipped);
  }

  Future<Uint8List> buildDesignPdfFromTemplate({
    required Uint8List templateBytes,
    required List<MergeRecord> records,
  }) async {
    if (records.isEmpty) {
      throw Exception('لا توجد بيانات طلاب لإنشاء PDF.');
    }

    try {
      final templateInfo = inspectWord(templateBytes);
      final cardsPerPage = templateInfo.cardsPerPage;
      final combinedElements = <DocxNode>[];
      DocxBuiltDocument? baseDocument;

      final pageBreak = docx().pageBreak().build().elements.first;

      for (var offset = 0; offset < records.length; offset += cardsPerPage) {
        final end = offset + cardsPerPage < records.length
            ? offset + cardsPerPage
            : records.length;

        final pageDocx = mergeDocx(
          templateBytes: templateBytes,
          records: records.sublist(offset, end),
        );

        final pageDocument = await DocxReader.loadFromBytes(pageDocx);
        baseDocument ??= pageDocument;

        if (combinedElements.isNotEmpty) {
          combinedElements.add(pageBreak);
        }
        combinedElements.addAll(pageDocument.elements);
      }

      final source = baseDocument!;
      final pagedDocument = DocxBuiltDocument(
        elements: combinedElements,
        section: source.section,
        stylesXml: source.stylesXml,
        numberingXml: source.numberingXml,
        settingsXml: source.settingsXml,
        fontTableXml: source.fontTableXml,
        fontTableRelsXml: source.fontTableRelsXml,
        themeXml: source.themeXml,
        contentTypesXml: source.contentTypesXml,
        rootRelsXml: source.rootRelsXml,
        headerBgXml: source.headerBgXml,
        headerBgRelsXml: source.headerBgRelsXml,
        footnotesXml: source.footnotesXml,
        endnotesXml: source.endnotesXml,
        numberingRelsXml: source.numberingRelsXml,
        numberingImages: source.numberingImages,
        fonts: source.fonts,
        footnotes: source.footnotes,
        endnotes: source.endnotes,
        theme: source.theme,
      );

      final pdf = await PdfExporter().exportToBytes(pagedDocument);
      if (pdf.isEmpty) {
        throw Exception('تم إنشاء PDF فارغ.');
      }

      return Uint8List.fromList(pdf);
    } catch (error) {
      throw Exception(
        'تعذر تحويل Word إلى PDF مع الحفاظ على التصميم: $error',
      );
    }
  }

  Future<String?> tryWindowsOfficePdf(String docxPath) async {
    if (!Platform.isWindows) return null;

    final dir = p.dirname(docxPath);
    final pdfPath = p.join(
      dir,
      '${p.basenameWithoutExtension(docxPath)}.pdf',
    );

    try {
      final escapedDocx = docxPath.replaceAll("'", "''");
      final escapedPdf = pdfPath.replaceAll("'", "''");
      final script =
          r"$word = New-Object -ComObject Word.Application; " +
          r"$word.Visible = $false; " +
          "\$doc = \$word.Documents.Open('$escapedDocx'); " +
          "\$doc.SaveAs([ref]'$escapedPdf', [ref]17); " +
          r"$doc.Close(); $word.Quit();";

      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
      );

      if (result.exitCode == 0 && File(pdfPath).existsSync()) {
        return pdfPath;
      }
    } catch (_) {}

    for (final exe in const ['soffice.exe', 'soffice']) {
      try {
        final result = await Process.run(
          exe,
          [
            '--headless',
            '--convert-to',
            'pdf',
            '--outdir',
            dir,
            docxPath,
          ],
        );

        if (result.exitCode == 0 && File(pdfPath).existsSync()) {
          return pdfPath;
        }
      } catch (_) {}
    }

    return null;
  }

  bool fieldMatches(List<String> headers, String field) {
    final normalized = MergeRecord.normalize(field);
    return headers.any(
      (header) => MergeRecord.normalize(header) == normalized,
    );
  }

  void _replaceInCell(XmlElement cell, MergeRecord record) {
    for (final paragraph in cell.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p')) {
      _replacePlaceholdersInParagraph(
        paragraph,
        (field) => record.valueFor(field),
      );
    }
  }

  void _clearPlaceholders(XmlElement cell) {
    for (final paragraph in cell.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p')) {
      _replacePlaceholdersInParagraph(paragraph, (_) => '');
    }
  }

  void _replacePlaceholdersInParagraph(
    XmlElement paragraph,
    String Function(String field) resolver,
  ) {
    final textNodes = paragraph.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 't')
        .toList();

    if (textNodes.isEmpty) return;

    final originalParts =
        textNodes.map((node) => node.innerText).toList(growable: false);
    final joined = originalParts.join();
    final matches = _placeholderRegex.allMatches(joined).toList();

    if (matches.isEmpty) return;

    final starts = <int>[];
    var cursor = 0;
    for (final part in originalParts) {
      starts.add(cursor);
      cursor += part.length;
    }

    int nodeIndexForOffset(int offset) {
      if (offset <= 0) return 0;

      for (var i = 0; i < originalParts.length; i++) {
        final start = starts[i];
        final end = start + originalParts[i].length;
        if (offset < end || (offset == end && i == originalParts.length - 1)) {
          return i;
        }
      }

      return originalParts.length - 1;
    }

    for (final match in matches.reversed) {
      final field = (match.group(1) ?? match.group(2) ?? '').trim();
      final replacement = resolver(field);

      final startIndex = nodeIndexForOffset(match.start);
      final endIndex = nodeIndexForOffset(match.end - 1);

      final startLocal = match.start - starts[startIndex];
      final endLocal = match.end - starts[endIndex];

      if (startIndex == endIndex) {
        final current = textNodes[startIndex].innerText;
        textNodes[startIndex].innerText = current.replaceRange(
          startLocal,
          endLocal,
          replacement,
        );
        continue;
      }

      final firstText = textNodes[startIndex].innerText;
      final lastText = textNodes[endIndex].innerText;

      textNodes[startIndex].innerText =
          firstText.substring(0, startLocal) + replacement;

      for (var i = startIndex + 1; i < endIndex; i++) {
        textNodes[i].innerText = '';
      }

      textNodes[endIndex].innerText =
          lastText.substring(endLocal.clamp(0, lastText.length));
    }
  }

  static String _paragraphText(XmlElement paragraph) {
    return paragraph.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 't')
        .map((e) => e.innerText)
        .join();
  }

  static XmlElement? _firstTopLevelTable(Iterable<XmlNode> nodes) {
    for (final node in nodes) {
      if (node is XmlElement && node.name.local == 'tbl') {
        return node;
      }
    }
    return null;
  }

  static List<XmlElement> _topLevelCells(XmlElement table) {
    final cells = <XmlElement>[];

    for (final row in table.childElements.where(
      (element) => element.name.local == 'tr',
    )) {
      cells.addAll(
        row.childElements.where(
          (element) => element.name.local == 'tc',
        ),
      );
    }

    return cells;
  }

  static XmlElement _pageBreak() {
    return XmlDocument.parse(
      '<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:r><w:br w:type="page"/></w:r></w:p>',
    ).rootElement;
  }

  static ArchiveFile _findFile(Archive archive, String name) {
    for (final file in archive) {
      if (file.name == name) return file;
    }

    throw Exception('ملف Word غير صالح: $name غير موجود.');
  }
}
