/// 로컬 분석 세션 모델 (서버 연동 전 임시).
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

  factory AnalysisSession.fromMap(Map<String, dynamic> m) => AnalysisSession(
        id: m['id'] as int,
        contractId: m['contract_id'] as int,
        contractAddr: m['contract_addr'] as String,
        status: AnalysisStatus.fromString(m['status'] as String),
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        completedAt: m['completed_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['completed_at'] as int)
            : null,
        summary: m['summary'] as String?,
        estimatedCost: m['estimated_cost'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'contract_id': contractId,
        'contract_addr': contractAddr,
        'status': status.name,
        'started_at': startedAt.millisecondsSinceEpoch,
        'completed_at': completedAt?.millisecondsSinceEpoch,
        'summary': summary,
        'estimated_cost': estimatedCost,
      };
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

/// 손상 사진 (분석 세션에 속함).
class DamagePhoto {
  final int id;
  final int analysisId;
  final String filePath;
  /// AWS S3 백업 URL. 업로드 실패/네트워크 오프라인 시 null.
  final String? s3Url;
  final PhotoGroup group;
  final int orderIndex;
  final bool analyzed;
  final String? aiResultJson;

  const DamagePhoto({
    required this.id,
    required this.analysisId,
    required this.filePath,
    this.s3Url,
    required this.group,
    required this.orderIndex,
    required this.analyzed,
    this.aiResultJson,
  });

  factory DamagePhoto.fromMap(Map<String, dynamic> m) => DamagePhoto(
        id: m['id'] as int,
        analysisId: m['analysis_id'] as int,
        filePath: m['file_path'] as String,
        s3Url: m['s3_url'] as String?,
        group: PhotoGroup.fromString(m['group_type'] as String),
        orderIndex: m['order_index'] as int,
        analyzed: (m['analyzed'] as int) == 1,
        aiResultJson: m['ai_result'] as String?,
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

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as int,
        analysisId: m['analysis_id'] as int,
        role: ChatRole.fromString(m['role'] as String),
        content: m['content'] as String,
        photoId: m['photo_id'] as int?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
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
