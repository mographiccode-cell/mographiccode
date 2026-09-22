import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../lib/merge_engine.dart';

Future<Uint8List> _makeLabeledTemplate() async {
  const card =
      'اسم الطالبة: نموذج  الصف: الرابع  اللجنة: الاولى  رقم الجلوس: ( 1 )';

  final rows = List.generate(5, (_) => const [card, card]);
  final document = docx().table(rows).build();
  final bytes = await DocxExporter().exportToBytes(document);
  return Uint8List.fromList(bytes);
}

Uint8List _makeExcelLikeUserFile({
  int fourth = 4,
  int fifth = 4,
  int sixth = 4,
}) {
  final excel = Excel.createExcel();

  final s1 = excel['ورقة1'];
  s1.appendRow([
    TextCellValue(''),
    TextCellValue('اسم الطالبة'),
    TextCellValue('اللجنة'),
    TextCellValue('الصف'),
    TextCellValue('ارقام الجلوس'),
  ]);
  for (var i = 1; i <= fourth; i++) {
    s1.appendRow([
      IntCellValue(i),
      TextCellValue('طالبة رابع رقم $i'),
      TextCellValue('الاولى'),
      TextCellValue('الرابع'),
      TextCellValue(''),
    ]);
  }

  final s2 = excel['ورقة2'];
  s2.appendRow([
    TextCellValue(''),
    TextCellValue('خامس'),
    TextCellValue(''),
    TextCellValue(''),
  ]);
  for (var i = 1; i <= fifth; i++) {
    s2.appendRow([
      IntCellValue(i),
      TextCellValue('طالبة خامس رقم $i'),
      TextCellValue('الثانية'),
      TextCellValue('الخامس'),
    ]);
  }

  final s3 = excel['ورقة3'];
  s3.appendRow([
    TextCellValue(''),
    TextCellValue('سادس'),
  ]);
  for (var i = 1; i <= sixth; i++) {
    s3.appendRow([
      IntCellValue(i),
      TextCellValue('طالبة سادس رقم $i'),
    ]);
  }

  return Uint8List.fromList(excel.save()!);
}

List<String> _cardCellTexts(Uint8List docxBytes) {
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
        final text = cell.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 't')
            .map((element) => element.innerText)
            .join();

        if (text.contains('اسم الطالبة') && text.contains('رقم الجلوس')) {
          cells.add(text);
        }
      }
    }
  }

  return cells;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads irregular three-sheet Excel structure', () async {
    final engine = MergeEngine();
    final result = await engine.readExcel(_makeExcelLikeUserFile());

    expect(result.records.length, 12);
    expect(result.records[0].grade, 'الرابع');
    expect(result.records[4].grade, 'الخامس');
    expect(result.records[8].grade, 'السادس');
  });

  test('global seat numbering never resets between grades', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcelLikeUserFile());
    final numbered = engine.renumberSeats(excel.records, 300);

    expect(numbered.first.seat, '300');
    expect(numbered[3].seat, '303');
    expect(numbered[4].grade, 'الخامس');
    expect(numbered[4].seat, '304');
    expect(numbered[8].grade, 'السادس');
    expect(numbered[8].seat, '308');
    expect(numbered.last.seat, '311');
    expect(numbered[4].valueFor('رقم الجلوس'), '304');
    expect(numbered[4].valueFor('ارقام الجلوس'), '304');
  });

  test('292 students starting at 300 end at 591 continuously', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(
      _makeExcelLikeUserFile(fourth: 90, fifth: 101, sixth: 101),
    );
    final numbered = engine.renumberSeats(excel.records, 300);

    expect(numbered.length, 292);
    expect(numbered[89].grade, 'الرابع');
    expect(numbered[89].seat, '389');
    expect(numbered[90].grade, 'الخامس');
    expect(numbered[90].seat, '390');
    expect(numbered[190].seat, '490');
    expect(numbered[191].grade, 'السادس');
    expect(numbered[191].seat, '491');
    expect(numbered.last.seat, '591');
  });

  test('Word cards receive continuous user-defined seat numbers', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcelLikeUserFile());
    final numbered = engine.renumberSeats(excel.records, 300);
    final templateBytes = await _makeLabeledTemplate();

    final merged = engine.mergeDocx(
      templateBytes: templateBytes,
      records: numbered,
    );

    final cards = _cardCellTexts(merged);
    expect(cards.length, 20);
    expect(cards[0], contains('( 300 )'));
    expect(cards[3], contains('( 303 )'));
    expect(cards[4], contains('( 304 )'));
    expect(cards[8], contains('( 308 )'));
    expect(cards[11], contains('( 311 )'));
  });

  test('Arabic-safe PDF is multi-page and preserves Unicode text mapping',
      () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcelLikeUserFile());
    final numbered = engine.renumberSeats(excel.records, 300);
    final templateBytes = await _makeLabeledTemplate();

    final pdfBytes = await engine.buildDesignPdfFromTemplate(
      templateBytes: templateBytes,
      records: numbered,
    );

    expect(pdfBytes.length, greaterThan(1000));
    expect(ascii.decode(pdfBytes.sublist(0, 4)), '%PDF');

    final parsed = await PdfReader.loadFromBytes(pdfBytes);
    expect(parsed.pageCount, greaterThanOrEqualTo(2));

    final extracted = MarkdownExporter().export(
      DocxBuiltDocument(elements: parsed.elements),
    );
    final normalized = extracted.replaceAll(RegExp(r'\s+'), '');
    expect(normalized, contains('طالبة'));
  });
}
