import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../lib/merge_engine.dart';

Future<Uint8List> _makeTemplate() async {
  const card =
      '{{الاسم}} | {{الصف}} | {{اللجنة}} | {{رقم الجلوس}}';

  final rows = List.generate(
    5,
    (_) => const [card, card],
  );

  final document = docx().table(rows).build();
  final bytes = await DocxExporter().exportToBytes(document);
  return Uint8List.fromList(bytes);
}

Uint8List _makeExcel(int count) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];

  sheet.appendRow([
    TextCellValue('الاسم'),
    TextCellValue('الصف'),
    TextCellValue('اللجنة'),
    TextCellValue('رقم الجلوس'),
  ]);

  for (var i = 1; i <= count; i++) {
    sheet.appendRow([
      TextCellValue('طالب $i'),
      TextCellValue('الصف الثالث'),
      TextCellValue('لجنة ${(i % 3) + 1}'),
      TextCellValue('10${i.toString().padLeft(2, '0')}'),
    ]);
  }

  return Uint8List.fromList(excel.save()!);
}

List<String> _tableCellTexts(Uint8List docxBytes) {
  final archive = ZipDecoder().decodeBytes(docxBytes);
  final documentFile = archive.firstWhere(
    (file) => file.name == 'word/document.xml',
  );

  final xml = XmlDocument.parse(
    utf8.decode(documentFile.content as List<int>),
  );

  final body = xml.descendants
      .whereType<XmlElement>()
      .firstWhere((element) => element.name.local == 'body');

  final cells = <String>[];
  for (final table in body.childElements.where(
    (element) => element.name.local == 'tbl',
  )) {
    for (final row in table.childElements.where(
      (element) => element.name.local == 'tr',
    )) {
      for (final cell in row.childElements.where(
        (element) => element.name.local == 'tc',
      )) {
        cells.add(
          cell.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 't')
              .map((element) => element.innerText)
              .join(),
        );
      }
    }
  }

  return cells;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Excel + 10-card Word template merges students in exact order', () async {
    final engine = MergeEngine();

    final excelResult = await engine.readExcel(_makeExcel(12));
    expect(excelResult.records.length, 12);
    expect(excelResult.headers, containsAll([
      'الاسم',
      'الصف',
      'اللجنة',
      'رقم الجلوس',
    ]));

    final templateBytes = await _makeTemplate();
    final template = engine.inspectWord(templateBytes);

    expect(template.cardsPerPage, 10);
    expect(template.placeholders.toSet(), {
      'الاسم',
      'الصف',
      'اللجنة',
      'رقم الجلوس',
    });
    expect(
      engine.missingFields(
        excelResult.headers,
        template.placeholders,
      ),
      isEmpty,
    );

    final merged = engine.mergeDocx(
      templateBytes: templateBytes,
      records: excelResult.records,
    );

    final cells = _tableCellTexts(merged);

    expect(cells.length, 20);
    expect(cells[0], contains('طالب 1'));
    expect(cells[0], contains('الصف الثالث'));
    expect(cells[0], contains('لجنة 2'));
    expect(cells[0], contains('1001'));

    expect(cells[9], contains('طالب 10'));
    expect(cells[10], contains('طالب 11'));
    expect(cells[11], contains('طالب 12'));

    for (final cell in cells.take(12)) {
      expect(cell, isNot(contains('{{')));
      expect(cell, isNot(contains('«')));
    }

    for (final cell in cells.skip(12)) {
      expect(cell, isNot(contains('{{')));
    }
  });

  test('missing Word field blocks merge before producing wrong cards', () async {
    final engine = MergeEngine();

    final missing = engine.missingFields(
      const ['الاسم', 'الصف', 'اللجنة'],
      const ['الاسم', 'الصف', 'اللجنة', 'رقم الجلوس'],
    );

    expect(missing, ['رقم الجلوس']);
  });

  test('merged DOCX converts to a real multi-page PDF', () async {
    final engine = MergeEngine();
    final excelResult = await engine.readExcel(_makeExcel(12));
    final templateBytes = await _makeTemplate();

    final pdfBytes = await engine.buildDesignPdfFromTemplate(
      templateBytes: templateBytes,
      records: excelResult.records,
    );

    expect(pdfBytes.length, greaterThan(1000));
    expect(
      ascii.decode(pdfBytes.sublist(0, 4)),
      '%PDF',
    );

    final pdf = await PdfReader.loadFromBytes(pdfBytes);
    expect(pdf.pageCount, greaterThanOrEqualTo(2));
  });
}
