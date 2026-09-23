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
      'اسم الطالبة: نموذج  الصف: الرابع  اللجنة: الاولى  رقم الجلوس: ( 1 )';

  final rows = List.generate(5, (_) => const [card, card]);
  final document = docx().table(rows).build();
  final bytes = await DocxExporter().exportToBytes(document);
  return Uint8List.fromList(bytes);
}

Uint8List _makeExcel({
  int fourth = 4,
  int fifth = 4,
  int sixth = 4,
}) {
  final excel = Excel.createExcel();

  final s1 = excel['رابع'];
  s1.appendRow([
    TextCellValue('اسم الطالبة'),
    TextCellValue('اللجنة'),
    TextCellValue('الصف'),
    TextCellValue('رقم الجلوس'),
  ]);
  for (var i = 1; i <= fourth; i++) {
    s1.appendRow([
      TextCellValue('طالبة رابع $i'),
      TextCellValue('الاولى'),
      TextCellValue('الرابع'),
      IntCellValue(i),
    ]);
  }

  final s2 = excel['خامس'];
  for (var i = 1; i <= fifth; i++) {
    s2.appendRow([
      IntCellValue(i),
      TextCellValue('طالبة خامس $i'),
      TextCellValue('الثانية'),
      TextCellValue('الخامس'),
    ]);
  }

  final s3 = excel['سادس'];
  for (var i = 1; i <= sixth; i++) {
    s3.appendRow([
      IntCellValue(i),
      TextCellValue('طالبة سادس $i'),
    ]);
  }

  return Uint8List.fromList(excel.save()!);
}

List<String> _cardTexts(Uint8List docxBytes) {
  final archive = ZipDecoder().decodeBytes(docxBytes);
  final documentFile = archive.firstWhere(
    (file) => file.name == 'word/document.xml',
  );

  final xml = XmlDocument.parse(
    utf8.decode(documentFile.content as List<int>),
  );

  return xml.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'tc')
      .map(
        (cell) => cell.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 't')
            .map((element) => element.innerText)
            .join(),
      )
      .where(
        (text) =>
            text.contains('اسم الطالبة') &&
            text.contains('رقم الجلوس'),
      )
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads students from multiple Excel sheets', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcel());

    expect(excel.records.length, 12);
    expect(excel.records.first.grade, 'الرابع');
    expect(excel.records[4].grade, 'الخامس');
    expect(excel.records[8].grade, 'السادس');
  });

  test('seat numbers continue globally across all grades', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcel());
    final numbered = engine.renumberSeats(excel.records, 300);

    expect(numbered.first.seat, '300');
    expect(numbered[3].seat, '303');
    expect(numbered[4].grade, 'الخامس');
    expect(numbered[4].seat, '304');
    expect(numbered[8].grade, 'السادس');
    expect(numbered[8].seat, '308');
    expect(numbered.last.seat, '311');
  });

  test('12 students are distributed evenly over 5 committees', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcel());
    final numbered = engine.renumberSeats(excel.records, 300);
    final distributed = engine.distributeCommittees(numbered, 5);

    expect(engine.committeeSizes(12, 5), [3, 3, 2, 2, 2]);
    expect(distributed.length, 12);

    expect(distributed[0].committee, '1');
    expect(distributed[2].committee, '1');
    expect(distributed[3].committee, '2');
    expect(distributed[5].committee, '2');
    expect(distributed[6].committee, '3');
    expect(distributed[7].committee, '3');
    expect(distributed[8].committee, '4');
    expect(distributed[9].committee, '4');
    expect(distributed[10].committee, '5');
    expect(distributed[11].committee, '5');

    expect(distributed[3].seat, '303');
    expect(distributed[3].valueFor('اللجنة'), '2');
    expect(distributed[3].valueFor('رقم اللجنة'), '2');
  });

  test('Word merge writes redistributed committee numbers into cards', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcel());
    final numbered = engine.renumberSeats(excel.records, 300);
    final distributed = engine.distributeCommittees(numbered, 5);
    final template = await _makeTemplate();

    final merged = engine.mergeDocx(
      templateBytes: template,
      records: distributed,
    );

    expect(merged.length, greaterThan(1000));

    final cards = _cardTexts(merged);
    expect(cards.length, 20);

    expect(cards[0], contains('طالبة رابع 1'));
    expect(cards[0], contains('اللجنة: 1'));
    expect(cards[0], contains('( 300 )'));

    expect(cards[3], contains('اللجنة: 2'));
    expect(cards[3], contains('( 303 )'));

    expect(cards[6], contains('اللجنة: 3'));
    expect(cards[8], contains('اللجنة: 4'));
    expect(cards[10], contains('اللجنة: 5'));
    expect(cards[11], contains('( 311 )'));
  });

  test('292 students over 10 committees differ by at most one student',
      () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(
      _makeExcel(fourth: 90, fifth: 101, sixth: 101),
    );

    final numbered = engine.renumberSeats(excel.records, 300);
    final distributed = engine.distributeCommittees(numbered, 10);
    final sizes = engine.committeeSizes(distributed.length, 10);

    expect(distributed.length, 292);
    expect(distributed.first.seat, '300');
    expect(distributed.last.seat, '591');

    expect(sizes, [30, 30, 29, 29, 29, 29, 29, 29, 29, 29]);
    expect(sizes.reduce((a, b) => a > b ? a : b) -
        sizes.reduce((a, b) => a < b ? a : b), 1);

    expect(distributed[0].committee, '1');
    expect(distributed[29].committee, '1');
    expect(distributed[30].committee, '2');
    expect(distributed[59].committee, '2');
    expect(distributed[60].committee, '3');
    expect(distributed[291].committee, '10');
  });

  test('committee count cannot exceed student count', () async {
    final engine = MergeEngine();
    final excel = await engine.readExcel(_makeExcel());

    expect(
      () => engine.distributeCommittees(excel.records, 13),
      throwsA(isA<Exception>()),
    );
    expect(engine.committeeSizes(12, 13), isEmpty);
  });
}
