/// 분석 세션·사진·메시지 모델.
///
/// 백엔드(PostgreSQL) JSON 응답을 기반으로 한다 — 로컬 SQLite 시절의
/// `fromMap`(epoch ms 기반)은 더 이상 사용하지 않는다.
class AnalysisSession {
  final int id;
  final int contractId;
  final String contractAddr;
  final AnalysisStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? summary;
  final int? estimatedCost;

  const AnalysisSession({
    required this.id,
    required this.contractId,
    required this.contractAddr,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.summary,
    this.estimatedCost,
  });

  factory AnalysisSession.fromJson(Map<String, dynamic> j) => AnalysisSession(
        id: j['id'] as int,
        contractId: j['contract_id'] as int,
        contractAddr: j['contract_addr'] as String,
        status: AnalysisStatus.fromString(j['status'] as String),
        startedAt: DateTime.parse(j['started_at'] as String),
        completedAt: j['completed_at'] != null
            ? DateTime.parse(j['completed_at'] as String)
            : null,
        summary: j['summary'] as String?,
        estimatedCost: j['estimated_cost'] as int?,
      );
}

enum AnalysisStatus {
  pending,
  inProgress,
  completed;

  static AnalysisStatus fromString(String s) {
    switch (s) {
      case 'in_progress':
        return AnalysisStatus.inProgress;
      case 'completed':
        return AnalysisStatus.completed;
      default:
        return AnalysisStatus.pending;
    }
  }

  String get name {
    switch (this) {
      case AnalysisStatus.pending:
        return 'pending';
      case AnalysisStatus.inProgress:
        return 'in_progress';
      case AnalysisStatus.completed:
        return 'completed';
    }
  }
}

/// 손상 사진 (분석 세션에 속함). S3 URL이 진실 소스.
class DamagePhoto {
  final int id;
  final int analysisId;

  /// AWS S3 영구 public URL. 백엔드에 등록 시 필수.
  final String s3Url;
  final PhotoGroup group;
  final int orderIndex;
  final bool analyzed;
  final String? aiResultJson;

  const DamagePhoto({
    required this.id,
    required this.analysisId,
    required this.s3Url,
    required this.group,
    required this.orderIndex,
    required this.analyzed,
    this.aiResultJson,
  });

  factory DamagePhoto.fromJson(Map<String, dynamic> j) => DamagePhoto(
        id: j['id'] as int,
        analysisId: j['analysis_id'] as int,
        s3Url: j['s3_url'] as String,
        group: PhotoGroup.fromString(j['group_type'] as String),
        orderIndex: j['order_index'] as int,
        analyzed: j['analyzed'] as bool,
        aiResultJson: j['ai_result'] as String?,
      );
}

enum PhotoGroup {
  moveIn,
  moveOut;

  static PhotoGroup fromString(String s) =>
      s == 'move_in' ? PhotoGroup.moveIn : PhotoGroup.moveOut;
  String get name => this == PhotoGroup.moveIn ? 'move_in' : 'move_out';
  String get label => this == PhotoGroup.moveIn ? '입주' : '퇴거';
}

/// 채팅 메시지.
class ChatMessage {
  final int id;
  final int analysisId;
  final ChatRole role;
  final String content;
  final int? photoId;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.analysisId,
    required this.role,
    required this.content,
    this.photoId,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as int,
        analysisId: j['analysis_id'] as int,
        role: ChatRole.fromString(j['role'] as String),
        content: j['content'] as String,
        photoId: j['photo_id'] as int?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

enum ChatRole {
  user,
  ai,
  system;

  static ChatRole fromString(String s) {
    switch (s) {
      case 'user':
        return ChatRole.user;
      case 'system':
        return ChatRole.system;
      default:
        return ChatRole.ai;
    }
  }

  String get name {
    switch (this) {
      case ChatRole.user:
        return 'user';
      case ChatRole.system:
        return 'system';
      case ChatRole.ai:
        return 'ai';
    }
  }
}
