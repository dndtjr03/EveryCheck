import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 로컬 SQLite 데이터베이스 (서버 미구현 동안 임시 저장소).
///
/// 서버 연동 시 이 파일만 교체하거나, `AnalysisRepository`의 source를
/// 원격으로 갈아끼우는 식으로 마이그레이션 예정.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'everycheck_local.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int v) async {
    // 분석 세션 1건 = 한 계약에 대한 손상 분석 모음
    await db.execute('''
      CREATE TABLE analyses (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        contract_id     INTEGER NOT NULL,
        contract_addr   TEXT NOT NULL,
        status          TEXT NOT NULL,          -- pending / in_progress / completed
        started_at      INTEGER NOT NULL,       -- epoch ms
        completed_at    INTEGER,
        summary         TEXT,                   -- 분석 요약(JSON or text)
        estimated_cost  INTEGER                 -- 예상 부담액(원)
      );
    ''');

    // 손상 사진 (분석 세션에 속함)
    await db.execute('''
      CREATE TABLE damage_photos (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        analysis_id INTEGER NOT NULL,
        file_path   TEXT NOT NULL,              -- 로컬 파일 경로
        group_type  TEXT NOT NULL,              -- move_in / move_out
        order_index INTEGER NOT NULL,
        analyzed    INTEGER NOT NULL DEFAULT 0, -- 0/1
        ai_result   TEXT,                       -- JSON: { part, damage_type, cost, confidence }
        FOREIGN KEY (analysis_id) REFERENCES analyses(id) ON DELETE CASCADE
      );
    ''');

    // 채팅 메시지 (분석 세션에 속함)
    await db.execute('''
      CREATE TABLE messages (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        analysis_id INTEGER NOT NULL,
        role        TEXT NOT NULL,              -- user / ai / system
        content     TEXT NOT NULL,
        photo_id    INTEGER,                    -- 사진과 함께 분석한 경우
        created_at  INTEGER NOT NULL,
        FOREIGN KEY (analysis_id) REFERENCES analyses(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
        'CREATE INDEX idx_analyses_contract ON analyses(contract_id);');
    await db.execute(
        'CREATE INDEX idx_photos_analysis ON damage_photos(analysis_id);');
    await db.execute(
        'CREATE INDEX idx_messages_analysis ON messages(analysis_id);');
  }
}
