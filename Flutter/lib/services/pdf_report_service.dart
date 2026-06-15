import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../local/analysis_repository.dart';
import '../models/analysis_local.dart';

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
    // 분석 실패한 사진도 PDF에 포함 (분석 정보 없음으로 표시).
    // analyzed=true 만 포함하면 첫 분석 실패한 사진이 PDF에서 사라져 사용자가 혼란.
    final analyzed = photos.toList();

    // 한글 폰트 (앱 번들 자산 — assets/fonts/).
    // 기존: PdfGoogleFonts.notoSansKRRegular() — 인터넷에서 CDN 다운로드 필요해서
    //       오프라인·불안정 망에서 폰트 로드 실패 시 한글이 □로 깨졌음.
    // 변경: pubspec.yaml에 등록한 NanumGothic .ttf를 rootBundle에서 직접 로드.
    final regularData = await rootBundle.load(
      'assets/fonts/NanumGothic-Regular.ttf',
    );
    final boldData = await rootBundle.load(
      'assets/fonts/NanumGothic-Bold.ttf',
    );
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);
    final theme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
      // 한글 폰트에 없는 글리프(이모지 등)는 다시 한글 폰트로 폴백 → 두부(□) 방지.
      fontFallback: [regular],
    );

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

    // ── 3p~: 손상별 상세 (입주/퇴거 사진 쌍으로 한 페이지) ──────────────
    // orderIndex 기준으로 입주·퇴거 사진을 매칭
    final moveInMap = <int, DamagePhoto>{
      for (final p in analyzed.where((p) => p.group == PhotoGroup.moveIn))
        p.orderIndex: p
    };
    final moveOutMap = <int, DamagePhoto>{
      for (final p in analyzed.where((p) => p.group == PhotoGroup.moveOut))
        p.orderIndex: p
    };
    final allIndexes = {
      ...moveInMap.keys,
      ...moveOutMap.keys,
    }.toList()..sort();

    for (var idx = 0; idx < allIndexes.length; idx++) {
      final key = allIndexes[idx];
      final inPh = moveInMap[key];
      final outPh = moveOutMap[key];

      // 대표 분석 결과는 퇴거 사진 기준 (손상 판정)
      Map<String, dynamic> r = {};
      final repr = outPh ?? inPh;
      if (repr != null && repr.analyzed && repr.aiResultJson != null) {
        try {
          r = jsonDecode(repr.aiResultJson!) as Map<String, dynamic>;
        } catch (_) {}
      }

      // 입주/퇴거 사진은 각각 S3에서 비동기 다운로드 후 PDF 임베드.
      final inImage = await _loadPhotoImage(inPh);
      final outImage = await _loadPhotoImage(outPh);

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _h1('사진 ${idx + 1}'),
              pw.SizedBox(height: 12),
              // 입주/퇴거 사진 나란히
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: _photoPanel('입주 사진', inImage)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: _photoPanel('퇴거 사진', outImage)),
                ],
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

  /// S3에서 사진 다운로드 + EXIF 방향 보정 + 가로 사진 → 세로 자동 회전.
  static Future<pw.MemoryImage?> _loadPhotoImage(DamagePhoto? ph) async {
    if (ph == null) return null;
    try {
      final resp = await http.get(Uri.parse(ph.s3Url));
      if (resp.statusCode != 200) {
        dev.log(
          'PDF photo download failed (${resp.statusCode}): ${ph.s3Url}',
          name: 'pdf',
        );
        return null;
      }
      final rawBytes = resp.bodyBytes;
      if (rawBytes.isEmpty) {
        dev.log('PDF photo empty: ${ph.s3Url}', name: 'pdf');
        return null;
      }

      // EXIF 방향 태그 적용 (스마트폰 사진은 EXIF로 회전 정보를 저장)
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        dev.log('PDF photo decode failed: ${ph.s3Url}', name: 'pdf');
        return pw.MemoryImage(rawBytes);
      }

      img.Image oriented = img.bakeOrientation(decoded);

      // 가로 사진(width > height)이면 시계 반대 방향 90° 회전 → 세로로 변환
      if (oriented.width > oriented.height) {
        oriented = img.copyRotate(oriented, angle: 90);
        dev.log('PDF photo rotated to portrait: ${ph.s3Url}', name: 'pdf');
      }

      final finalBytes = img.encodeJpg(oriented, quality: 90);
      dev.log(
        'PDF photo ready: ${ph.s3Url} '
        '(${oriented.width}x${oriented.height})',
        name: 'pdf',
      );
      return pw.MemoryImage(Uint8List.fromList(finalBytes));
    } catch (e, st) {
      dev.log('PDF photo load failed', name: 'pdf', error: e, stackTrace: st);
      return null;
    }
  }

  static pw.Widget _photoPanel(String label, pw.MemoryImage? image) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE3ECFF),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColor.fromInt(0xFF1E4FB6),
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 6),
        if (image != null)
          pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Image(image, fit: pw.BoxFit.cover, height: 200),
          )
        else
          pw.Container(
            height: 200,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF3F4F6),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              '사진 없음',
              style:
                  pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF999999)),
            ),
          ),
      ],
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

