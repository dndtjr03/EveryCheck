import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../local/analysis_repository.dart';

/// 분석 세션 1건을 PDF로 변환.
///
/// 구성:
///  - 1p 표지 (주소, 분석일, 총액)
///  - 1p 분석 요약
///  - 1p × N: 손상별 상세 (사진 + AI 결과)
///  - 1p 적용된 판례·법조 + 면책 조항
class PdfReportService {
  PdfReportService._();
  static final PdfReportService instance = PdfReportService._();

  Future<Uint8List> buildReport(int analysisId) async {
    final repo = AnalysisRepository.instance;
    final session = await repo.getAnalysis(analysisId);
    if (session == null) {
      throw Exception('분석 세션을 찾을 수 없어요.');
    }
    final photos = await repo.listPhotos(analysisId);
    final analyzed = photos.where((p) => p.analyzed).toList();

    // 한글 폰트 (Google Fonts CDN에서 가져옴 — printing 패키지 제공)
    final regular = await PdfGoogleFonts.notoSansKRRegular();
    final bold = await PdfGoogleFonts.notoSansKRBold();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);

    final doc = pw.Document(theme: theme);
    final dateFmt = DateFormat('yyyy.MM.dd HH:mm');
    final won = NumberFormat.currency(
        locale: 'ko_KR', symbol: '₩', decimalDigits: 0);
    final totalCost = session.estimatedCost ?? 0;

    // ── 1p: 표지 ──────────────────────────────────────────────────────
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.all(40),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE3ECFF),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text('다봐드림 분석 리포트',
                  style: pw.TextStyle(
                      fontSize: 11,
                      color: PdfColor.fromInt(0xFF1E4FB6))),
            ),
            pw.SizedBox(height: 36),
            pw.Text('임대차 손상 분석 결과',
                style: pw.TextStyle(
                    fontSize: 26, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Text(session.contractAddr,
                style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 60),
            _kv('분석 일시', dateFmt.format(session.startedAt)),
            _kv('분석 사진', '${photos.length}장'),
            _kv('분석 완료', '${analyzed.length}건'),
            _kv('예상 임차인 부담액',
                won.format(totalCost), bold: true, accent: true),
            pw.Spacer(),
            pw.Divider(color: PdfColor.fromInt(0xFFE3E5EE)),
            pw.SizedBox(height: 8),
            pw.Text(
              '본 문서는 AI 분석을 통해 생성된 참고 자료이며, '
              '실제 법적 효력이나 손해배상 책임은 임대인·임차인 협의 또는 분쟁조정·소송으로 결정됩니다.',
              style: pw.TextStyle(
                  fontSize: 9, color: PdfColor.fromInt(0xFF707080)),
            ),
          ],
        ),
      ),
    ));

    // ── 2p: 요약 ──────────────────────────────────────────────────────
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.all(40),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _h1('분석 요약'),
            pw.SizedBox(height: 12),
            pw.Text(session.summary ?? '요약 데이터가 없습니다.',
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 4)),
          ],
        ),
      ),
    ));

    // ── 3p~: 손상별 상세 ───────────────────────────────────────────────
    for (var i = 0; i < analyzed.length; i++) {
      final ph = analyzed[i];
      Map<String, dynamic> r = {};
      try {
        r = jsonDecode(ph.aiResultJson!) as Map<String, dynamic>;
      } catch (_) {}

      final imgFile = File(ph.filePath);
      final imgBytes =
          imgFile.existsSync() ? imgFile.readAsBytesSync() : null;
      final image = imgBytes != null ? pw.MemoryImage(imgBytes) : null;

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _h1('${ph.group.label} 사진 ${i + 1}'),
              pw.SizedBox(height: 12),
              if (image != null)
                pw.ClipRRect(
                  horizontalRadius: 8,
                  verticalRadius: 8,
                  child: pw.Image(image,
                      fit: pw.BoxFit.cover, width: 515, height: 240),
                )
              else
                pw.Container(
                  height: 100,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF3F4F6),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text('(사진을 불러올 수 없습니다)',
                      style: pw.TextStyle(
                          color: PdfColor.fromInt(0xFF999999))),
                ),
              pw.SizedBox(height: 16),
              _kv('부위', r['part']?.toString() ?? '-'),
              _kv('손상 종류', r['damage_type']?.toString() ?? '-'),
              _kv('추정 수리비',
                  won.format((r['cost'] as num?)?.toInt() ?? 0)),
              _kv('AI 확신도',
                  '${(((r['confidence'] as num?) ?? 0).toDouble() * 100).toStringAsFixed(0)}%'),
              pw.SizedBox(height: 16),
              pw.Text('상세 분석',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text(r['reason']?.toString() ?? '추가 설명 없음',
                  style:
                      const pw.TextStyle(fontSize: 11, lineSpacing: 4)),
            ],
          ),
        ),
      ));
    }

    // ── 마지막 페이지: 적용된 법조·판례 + 면책 ─────────────────────────
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.all(40),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _h1('적용 법조·판례'),
            pw.SizedBox(height: 12),
            _refBlock(
              title: '민법 제615조 (원상회복의무)',
              body:
                  '차주는 차용물을 반환하는 때에 이를 원상에 회복하여야 한다. 이에 부속시킨 물건은 철거할 수 있다.',
            ),
            _refBlock(
              title: '민법 제654조 (준용규정)',
              body:
                  '제610조 제1항, 제615조 내지 제617조의 규정은 임대차에 이를 준용한다.',
            ),
            _refBlock(
              title: '주택임대차보호법',
              body:
                  '주택의 임대차에 관하여 민법에 대한 특례를 규정함으로써 국민 주거생활의 안정을 보장하는 것을 목적으로 한다.',
            ),
            _refBlock(
              title: '국토교통부 임대차 가이드라인 (감가상각 공식)',
              body:
                  '임차인 부담 = 총 수리비 × (1 - 경과연수 / 내용연수). '
                  '벽지·장판 등 일반적 마감재의 내용연수는 통상 10년으로 본다.',
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFFF5E6),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(
                    color: PdfColor.fromInt(0xFFE86030), width: 0.5),
              ),
              child: pw.Text(
                '※ 판례·해석례 RAG 연동은 현재 준비 중입니다. '
                '추후 버전에서 분석 결과와 가장 관련 높은 판례를 자동 인용합니다.',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColor.fromInt(0xFFB85520),
                    lineSpacing: 4),
              ),
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColor.fromInt(0xFFE3E5EE)),
            pw.SizedBox(height: 8),
            pw.Text(
              '면책 조항: 본 리포트는 다봐드림(EveryCheck) AI 모델이 자동으로 생성한 참고 문서로, '
              '법적 자문이나 손해배상 책임을 확정하지 않습니다. 분쟁 시 정식 법률 자문을 받으시기 바랍니다.',
              style: pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColor.fromInt(0xFF707080),
                  lineSpacing: 3),
            ),
            pw.SizedBox(height: 6),
            pw.Text('생성일: ${dateFmt.format(DateTime.now())}',
                style: pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColor.fromInt(0xFFA0A0A0))),
          ],
        ),
      ),
    ));

    return doc.save();
  }

  // ── PDF 헬퍼 위젯 ──────────────────────────────────────────────────────

  static pw.Widget _h1(String text) => pw.Text(
        text,
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      );

  static pw.Widget _kv(String k, String v,
      {bool bold = false, bool accent = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(k,
                style: pw.TextStyle(
                    fontSize: 11, color: PdfColor.fromInt(0xFF707080))),
          ),
          pw.Expanded(
            child: pw.Text(
              v,
              style: pw.TextStyle(
                fontSize: bold ? 14 : 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: accent
                    ? PdfColor.fromInt(0xFFB85520)
                    : PdfColor.fromInt(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _refBlock({required String title, required String body}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(body,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 4)),
        ],
      ),
    );
  }
}

