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

  final rows = List.generate(
    5,
    (_) => const [card, card],
  );

  final document = docx().table(rows).build();
  final bytes = await DocxExporter().exportToBytes(document);
  return Uint8List.fromList(bytes);
}

Uint8List _makeExcelLikeUserFile() {
  final excel = Excel.createExcel();

  final s1 = excel['ورقة1'];
  s1.appendRow([
    TextCellValue(''),
    TextCellValue(''),
    TextCellValue(''),
    TextCellValue(''),
    TextCellValue(''),
  ]);
  s1.appendRow([
    TextCellValue(''),
    TextCellValue('اسم الطالبة'),
    TextCellValue('اللجنة'),
    TextCellValue('الصف'),
    TextCellValue('ارقام الجلوس'),
  ]);

  for (var i = 1; i <= 4; i++) {
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

  for (var i = 1; i <= 4; i++) {
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

  for (var i = 1; i <= 4; i++) {
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

        if (text.contains('اسم الطالبة') &&
            text.contains('رقم الجلوس')) {
          cells.add(text);
        }
      }
    }
  }

  return cells;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads the same irregular three-sheet Excel structure as user file',
      () async {
    final engine = MergeEngine();
    final result = await engine.readExcel(_makeExcelLikeUserFile());

    expect(result.records.length, 12);

    expect(result.records[0].name, 'طالبة رابع رقم 1');
    expect(result.records[0].grade, 'الرابع');
    expect(result.records[0].committee, 'الاولى');
    expect(result.records[0].seat, '1');

    expect(result.records[4].name, 'طالبة خامس رقم 1');
    expect(result.records[4].grade, 'الخامس');
    expect(result.records[4].committee, 'الثانية');
    expect(result.records[4].seat, '1');

    expect(result.records[8].name, 'طالبة سادس رقم 1');
    expect(result.records[8].grade, 'السادس');
    expect(result.records[8].committee, isEmpty);
    expect(result.records[8].seat, '1');
  });

  test('detects an already-filled Word card page without placeholders',
      () async {
    final engine = MergeEngine();
    final templateBytes = await _makeLabeledTemplate();

    final info = engine.inspectWord(templateBytes);

    expect(info.cardsPerPage, 10);
    expect(info.mode, WordTemplateMode.labeledCards);
    expect(info.labeledFields, containsAll({
      'name',
      'grade',
      'committee',
      'seat',
    }));
  });

  test('merges 12 records into 10-card pages in exact order', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcelLikeUserFile());
    final templateBytes = await _makeLabeledTemplate();

    final merged = engine.mergeDocx(
      templateBytes: templateBytes,
      records: excel.records,
    );

    final cards = _cardCellTexts(merged);

    expect(cards.length, 20);
    expect(cards[0], contains('طالبة رابع رقم 1'));
    expect(cards[0], contains('الرابع'));
    expect(cards[0], contains('الاولى'));
    expect(cards[0], contains('( 1 )'));

    expect(cards[3], contains('طالبة رابع رقم 4'));
    expect(cards[4], contains('طالبة خامس رقم 1'));
    expect(cards[8], contains('طالبة سادس رقم 1'));

    expect(cards[9], contains('طالبة سادس رقم 2'));
    expect(cards[10], contains('طالبة سادس رقم 3'));
    expect(cards[11], contains('طالبة سادس رقم 4'));

    for (final card in cards.skip(12)) {
      expect(card, isNot(contains('نموذج')));
    }
  });

  test('merged DOCX converts to a real multi-page PDF', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcelLikeUserFile());
    final templateBytes = await _makeLabeledTemplate();

    final merged = engine.mergeDocx(
      templateBytes: templateBytes,
      records: excel.records,
    );

    final pdfBytes = await engine.buildDesignPdfFromDocx(merged);

    expect(pdfBytes.length, greaterThan(1000));
    expect(ascii.decode(pdfBytes.sublist(0, 4)), '%PDF');

    final pdf = await PdfReader.loadFromBytes(pdfBytes);
    expect(pdf.pageCount, greaterThanOrEqualTo(2));
  });
}
