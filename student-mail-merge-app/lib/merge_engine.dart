import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:xml/xml.dart';

class MergeRecord {
  final Map<String, String> values;
  const MergeRecord(this.values);

  String valueFor(String key) {
    final exact = values[key];
    if (exact != null) return exact;
    final normalized = _normalize(key);
    for (final entry in values.entries) {
      if (_normalize(entry.key) == normalized) return entry.value;
    }
    return '';
  }

  static String _normalize(String input) => input
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

class MergeOutput {
  final Uint8List mergedDocx;
  final Uint8List pdfBytes;
  const MergeOutput(this.mergedDocx, this.pdfBytes);
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
      throw Exception('لم يتم العثور على بيانات بعد صف العناوين.');
    }
    return ExcelImportResult(headers, records);
  }

  TemplateInfo inspectWord(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentFile = _findFile(archive, 'word/document.xml');
    final doc = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );

    final allText = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 't')
        .map((e) => e.innerText)
        .join();

    final placeholders = <String>{};
    for (final match in _placeholderRegex.allMatches(allText)) {
      final field = (match.group(1) ?? match.group(2) ?? '').trim();
      if (field.isNotEmpty) placeholders.add(field);
    }

    final body = doc.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'body');

    XmlElement? firstTable;
    for (final child in body.childElements) {
      if (child.name.local == 'tbl') {
        firstTable = child;
        break;
      }
    }

    final cards = firstTable == null ? 0 : _topLevelCells(firstTable).length;
    if (cards == 0) {
      throw Exception(
        'قالب Word يجب أن يحتوي على الكروت داخل جدول، مثل 5 صفوف × عمودين.',
      );
    }

    return TemplateInfo(placeholders.toList()..sort(), cards);
  }

  Uint8List mergeDocx({
    required Uint8List templateBytes,
    required List<MergeRecord> records,
  }) {
    if (records.isEmpty) throw Exception('لا توجد بيانات للدمج.');

    final archive = ZipDecoder().decodeBytes(templateBytes);
    final documentFile = _findFile(archive, 'word/document.xml');
    final sourceDoc = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );
    final body = sourceDoc.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'body');

    final originalChildren = body.children.map((n) => n.copy()).toList();
    final sectionProps = originalChildren
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'sectPr')
        .toList();

    final pageChildren = originalChildren
        .where((n) => !(n is XmlElement && n.name.local == 'sectPr'))
        .toList();

    XmlElement? findFirstTable(List<XmlNode> nodes) {
      for (final node in nodes) {
        if (node is XmlElement && node.name.local == 'tbl') return node;
      }
      return null;
    }

    final probe = findFirstTable(pageChildren);
    if (probe == null) {
      throw Exception('تعذر العثور على جدول الكروت داخل Word.');
    }

    final cardsPerPage = _topLevelCells(probe).length;
    if (cardsPerPage == 0) {
      throw Exception('جدول Word لا يحتوي على خلايا كروت قابلة للدمج.');
    }

    body.children.clear();

    var offset = 0;
    var pageIndex = 0;
    while (offset < records.length) {
      final clonedPage = pageChildren.map((n) => n.copy()).toList();
      final table = findFirstTable(clonedPage);
      if (table == null) throw Exception('تعذر نسخ جدول الكروت.');

      final cells = _topLevelCells(table);
      for (var i = 0; i < cells.length; i++) {
        final recordIndex = offset + i;
        if (recordIndex < records.length) {
          _replaceInCell(cells[i], records[recordIndex]);
        } else {
          _clearPlaceholders(cells[i]);
        }
      }

      if (pageIndex > 0) body.children.add(_pageBreak());
      body.children.addAll(clonedPage);
      offset += cardsPerPage;
      pageIndex++;
    }

    if (sectionProps.isNotEmpty) {
      body.children.add(sectionProps.first.copy());
    }

    final mergedXml = sourceDoc.toXmlString(pretty: false);
    final out = Archive();

    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        final data = utf8.encode(mergedXml);
        out.addFile(ArchiveFile(file.name, data.length, data));
      } else {
        final data = file.content as List<int>;
        out.addFile(ArchiveFile(file.name, data.length, data));
      }
    }

    final zipped = ZipEncoder().encode(out);
    if (zipped == null) throw Exception('تعذر إنشاء ملف Word المدموج.');
    return Uint8List.fromList(zipped);
  }

  List<List<String>> extractCardLines(Uint8List templateBytes) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final documentFile = _findFile(archive, 'word/document.xml');
    final doc = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );
    final body = doc.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'body');

    XmlElement? table;
    for (final child in body.childElements) {
      if (child.name.local == 'tbl') {
        table = child;
        break;
      }
    }
    if (table == null) throw Exception('تعذر العثور على جدول الكروت.');

    return _topLevelCells(table).map((cell) {
      final lines = <String>[];
      for (final paragraph in cell.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'p')) {
        final text = paragraph.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .map((e) => e.innerText)
            .join();
        if (text.trim().isNotEmpty) lines.add(text);
      }
      return lines;
    }).toList();
  }

  Future<Uint8List> buildPdf({
    required List<MergeRecord> records,
    required List<List<String>> cardTemplates,
  }) async {
    final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
    final bold = await PdfGoogleFonts.notoNaskhArabicBold();
    final pdf = pw.Document();

    final cardsPerPage = cardTemplates.isEmpty ? 10 : cardTemplates.length;
    final rowsPerPage = (cardsPerPage / 2).ceil();

    for (var offset = 0; offset < records.length; offset += cardsPerPage) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(7 * PdfPageFormat.mm),
          build: (_) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                children: List.generate(rowsPerPage, (row) {
                  return pw.Expanded(
                    child: pw.Padding(
                      padding: pw.EdgeInsets.only(
                        bottom: row == rowsPerPage - 1
                            ? 0
                            : 2.5 * PdfPageFormat.mm,
                      ),
                      child: pw.Row(
                        children: List.generate(2, (col) {
                          final cardIndex = row * 2 + col;
                          final recordIndex = offset + cardIndex;

                          final card = cardIndex >= cardsPerPage ||
                                  recordIndex >= records.length
                              ? pw.SizedBox()
                              : _buildCard(
                                  cardTemplates[cardIndex],
                                  records[recordIndex],
                                  regular,
                                  bold,
                                );

                          return pw.Expanded(
                            child: pw.Padding(
                              padding: pw.EdgeInsets.only(
                                left: col == 0 ? 1.25 * PdfPageFormat.mm : 0,
                                right: col == 1 ? 1.25 * PdfPageFormat.mm : 0,
                              ),
                              child: card,
                            ),
                          );
                        }),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  Future<String?> tryWindowsOfficePdf(String docxPath) async {
    if (!Platform.isWindows) return null;

    final dir = p.dirname(docxPath);
    final pdfPath = p.join(
      dir,
      '${p.basenameWithoutExtension(docxPath)}.pdf',
    );

    for (final exe in const ['soffice.exe', 'soffice']) {
      try {
        final result = await Process.run(
          exe,
          ['--headless', '--convert-to', 'pdf', '--outdir', dir, docxPath],
        );
        if (result.exitCode == 0 && File(pdfPath).existsSync()) {
          return pdfPath;
        }
      } catch (_) {}
    }

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

    return null;
  }

  bool fieldMatches(List<String> headers, String field) {
    final normalized = MergeRecord._normalize(field);
    return headers.any(
      (header) => MergeRecord._normalize(header) == normalized,
    );
  }

  void _replaceInCell(XmlElement cell, MergeRecord record) {
    for (final paragraph in cell.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p')) {
      final texts = paragraph.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 't')
          .toList();

      if (texts.isEmpty) continue;

      final joined = texts.map((e) => e.innerText).join();
      final replaced = joined.replaceAllMapped(_placeholderRegex, (match) {
        final key = (match.group(1) ?? match.group(2) ?? '').trim();
        return record.valueFor(key);
      });

      if (replaced != joined) {
        texts.first.innerText = replaced;
        for (final node in texts.skip(1)) {
          node.innerText = '';
        }
      }
    }
  }

  void _clearPlaceholders(XmlElement cell) {
    for (final paragraph in cell.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p')) {
      final texts = paragraph.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 't')
          .toList();

      if (texts.isEmpty) continue;

      final joined = texts.map((e) => e.innerText).join();
      final cleared = joined.replaceAll(_placeholderRegex, '');

      if (cleared != joined) {
        texts.first.innerText = cleared;
        for (final node in texts.skip(1)) {
          node.innerText = '';
        }
      }
    }
  }

  pw.Widget _buildCard(
    List<String> lines,
    MergeRecord record,
    pw.Font regular,
    pw.Font bold,
  ) {
    final resolved = lines.map((line) {
      return line.replaceAllMapped(_placeholderRegex, (match) {
        final key = (match.group(1) ?? match.group(2) ?? '').trim();
        return record.valueFor(key);
      });
    }).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: List.generate(resolved.length, (index) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
            child: pw.Text(
              resolved[index],
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: index == 0 ? bold : regular,
                fontSize: index == 0 ? 11.5 : 9.5,
              ),
            ),
          );
        }),
      ),
    );
  }

  static List<XmlElement> _topLevelCells(XmlElement table) {
    final cells = <XmlElement>[];
    for (final row in table.childElements.where((e) => e.name.local == 'tr')) {
      cells.addAll(row.childElements.where((e) => e.name.local == 'tc'));
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
