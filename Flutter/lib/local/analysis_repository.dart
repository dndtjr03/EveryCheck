import '../models/analysis_local.dart';
import 'local_db.dart';

/// 분석 세션·사진·메시지에 대한 데이터 액세스.
///
/// 서버 연동 시 이 클래스를 인터페이스로 추출하고 remote 구현 추가 예정.
class AnalysisRepository {
  AnalysisRepository._();
  static final AnalysisRepository instance = AnalysisRepository._();

  // ── Analysis ────────────────────────────────────────────────────────────

  Future<int> createAnalysis({
    required int contractId,
    required String contractAddr,
  }) async {
    final db = await LocalDb.instance.database;
    return db.insert('analyses', {
      'contract_id': contractId,
      'contract_addr': contractAddr,
      'status': AnalysisStatus.pending.name,
      'started_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<AnalysisSession?> getAnalysis(int id) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query('analyses', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return AnalysisSession.fromMap(rows.first);
  }

  Future<List<AnalysisSession>> listAnalyses() async {
    final db = await LocalDb.instance.database;
    final rows = await db.query('analyses', orderBy: 'started_at DESC');
    return rows.map(AnalysisSession.fromMap).toList();
  }

  Future<void> updateAnalysisStatus(int id, AnalysisStatus status,
      {String? summary, int? estimatedCost}) async {
    final db = await LocalDb.instance.database;
    final m = <String, dynamic>{'status': status.name};
    if (status == AnalysisStatus.completed) {
      m['completed_at'] = DateTime.now().millisecondsSinceEpoch;
    }
    if (summary != null) m['summary'] = summary;
    if (estimatedCost != null) m['estimated_cost'] = estimatedCost;
    await db.update('analyses', m, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAnalysis(int id) async {
    final db = await LocalDb.instance.database;
    await db.delete('messages', where: 'analysis_id = ?', whereArgs: [id]);
    await db.delete('damage_photos', where: 'analysis_id = ?', whereArgs: [id]);
    await db.delete('analyses', where: 'id = ?', whereArgs: [id]);
  }

  // ── Damage Photos ────────────────────────────────────────────────────────

  Future<int> addPhoto({
    required int analysisId,
    required String filePath,
    required PhotoGroup group,
    required int orderIndex,
  }) async {
    final db = await LocalDb.instance.database;
    return db.insert('damage_photos', {
      'analysis_id': analysisId,
      'file_path': filePath,
      'group_type': group.name,
      'order_index': orderIndex,
      'analyzed': 0,
    });
  }

  Future<List<DamagePhoto>> listPhotos(int analysisId) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      'damage_photos',
      where: 'analysis_id = ?',
      whereArgs: [analysisId],
      orderBy: 'order_index ASC',
    );
    return rows.map(DamagePhoto.fromMap).toList();
  }

  Future<void> markPhotoAnalyzed(int photoId, String aiResultJson) async {
    final db = await LocalDb.instance.database;
    await db.update(
      'damage_photos',
      {'analyzed': 1, 'ai_result': aiResultJson},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<int> addMessage({
    required int analysisId,
    required ChatRole role,
    required String content,
    int? photoId,
  }) async {
    final db = await LocalDb.instance.database;
    return db.insert('messages', {
      'analysis_id': analysisId,
      'role': role.name,
      'content': content,
      'photo_id': photoId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<ChatMessage>> listMessages(int analysisId) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      'messages',
      where: 'analysis_id = ?',
      whereArgs: [analysisId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }
}
