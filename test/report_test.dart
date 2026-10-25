import 'dart:convert';
import 'package:ductletor_pro/core/formatting/fmt.dart';
import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/report/data/report_pdf_builder.dart';
import 'package:ductletor_pro/features/report/domain/report_data.dart';
import 'support/test_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

ReportData data(TestProject c) =>
    ReportData.fromEditor(c.s, when: DateTime.utc(2026, 10, 14));

void main() {
  test('builds a multi-section PDF for the sample project', () async {
    final c = TestProject(root: sampleProject(), name: 'Office Block A');
    c.setInfo(const ReportInfo(
        company: 'Acme HVAC',
        client: 'ABC Ltd',
        preparedBy: 'J. Smith',
        wastePercent: 7));
    final bytes = await buildReportPdf(data(c));
    expect(bytes.length, greaterThan(2000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('imperial and empty-fittings projects also render', () async {
    final c = TestProject(root: blankProject(), name: 'Blank', imperial: true);
    final bytes = await buildReportPdf(data(c));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test(
      'controller: insulation flag and report info are tracked as saveable changes',
      () {
    final c = TestProject(root: sampleProject());
    final r0 = c.revision;
    c.setInsulated('trunk', false);
    expect(c.revision, greaterThan(r0));
    final r1 = c.revision;
    c.setInfo(const ReportInfo(company: 'X'));
    expect(c.revision, greaterThan(r1));
    expect(c.toDoc().info.company, 'X');
    expect(TestProject.fromDoc(c.toDoc()).info.company, 'X');
  });

  test('area formatting', () {
    expect(const Fmt(false).area(10), '10.0 m²');
    expect(const Fmt(true).area(1), '10.8 ft²');
  });

  test('several units: one PDF with every unit', () async {
    final c = TestProject(root: sampleProject(), name: 'Two units');
    c.addUnit();
    c.renameUnit(c.units.last.id, 'AHU-02');
    final d = data(c);
    expect(d.units.length, 2);
    expect(d.boq.sections.length,
        d.units[0].boq.sections.length + d.units[1].boq.sections.length);
    final bytes = await buildReportPdf(d);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
