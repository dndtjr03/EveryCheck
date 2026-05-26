import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';

import 'api_service.dart';

/// 백엔드 photo 라우터(S3 업로드)를 호출하는 서비스.
///
/// 흐름:
///   1. 분석 시작 시 `ensureChecklist()` 호출 → 체크리스트 ID 확보 (없으면 자동 생성)
///   2. 사진 추가 시 `uploadPhoto()` 호출 → S3 업로드 + DB 메타 저장
class PhotoUploadService {
  PhotoUploadService._();
  static final PhotoUploadService instance = PhotoUploadService._();

  final ApiService _api = ApiService();

  /// 체크리스트 1건 확보. 인자로 받은 [title]에 해당하는 게 없으면 새로 만들고 ID 반환.
  /// (분석 세션 당 1개 체크리스트가 자동 매핑되도록 사용)
  Future<int> ensureChecklist(String title) async {
    final mine = await _api.get('/checklists/me');
    if (mine is List) {
      for (final raw in mine) {
        if (raw is Map && raw['title'] == title && raw['id'] is int) {
          return raw['id'] as int;
        }
      }
    }
    // 없으면 생성
    final created = await _api.post('/checklists/', {'title': title});
    if (created is Map && created['id'] is int) {
      return created['id'] as int;
    }
    throw const PhotoUploadException('체크리스트 생성 응답이 올바르지 않습니다.');
  }

  /// 사진 1장을 백엔드 `/photos/upload`로 업로드.
  ///
  /// [photoType]: 'INITIAL' (입주) / 'DAMAGED' (퇴거)
  /// 반환: 백엔드가 발급한 photo_id (실패 시 예외)
  Future<int> uploadPhoto({
    required Uint8List bytes,
    required String fileName,
    required int checklistId,
    required String photoType,
  }) async {
    final result = await _api.postMultipart(
      '/photos/upload',
      fields: {
        'checklist_id': checklistId.toString(),
        'photo_type': photoType,
      },
      fileBytes: bytes,
      fileName: fileName,
      fileField: 'files',
    );
    // 응답: { count, photos: [{ photo_id, display_url, expires_in }] }
    if (result is Map &&
        result['photos'] is List &&
        (result['photos'] as List).isNotEmpty) {
      final first = (result['photos'] as List).first;
      if (first is Map && first['photo_id'] is int) {
        return first['photo_id'] as int;
      }
    }
    throw const PhotoUploadException('photos 응답에 photo_id가 없습니다.');
  }

  /// 분석 화면 전용 단일 사진 백업 업로드 (`/photos/upload-single`).
  ///
  /// 체크리스트 모델·DB 행 없이 S3에만 올려서 영구 public URL을 받는다.
  /// 로컬 SQLite의 damage_photos.s3_url에 그대로 저장하면 PDF에서도 임베드 가능.
  /// 네트워크/인증 실패 시 null 반환 (예외 던지지 않음 → 분석 흐름은 막지 않음).
  Future<String?> uploadSingle(File photo) async {
    try {
      final bytes = await photo.readAsBytes();
      final filename = photo.path.split(Platform.pathSeparator).last;
      // 백엔드 validate_and_read_image_file 이 Content-Type 헤더를
      // ALLOWED_IMAGE_MIME_TYPES 화이트리스트와 일치시키므로 확장자 → MIME 매핑 필요.
      // (지정 안 하면 application/octet-stream 으로 나가 400 발생)
      final mime = _mimeFromFilename(filename);
      final res = await _api.postMultipart(
        '/photos/upload-single',
        fields: const {},
        fileBytes: bytes,
        fileName: filename,
        fileField: 'file',
        fileContentType: mime,
      );
      if (res is Map && res['s3_url'] is String) {
        final url = res['s3_url'] as String;
        if (url.isNotEmpty) {
          dev.log('S3 upload OK: $url', name: 'photo_upload');
          return url;
        }
      }
      dev.log('S3 upload unexpected response: $res', name: 'photo_upload');
      return null;
    } catch (e, st) {
      dev.log('S3 upload failed: $e',
          name: 'photo_upload', error: e, stackTrace: st);
      return null;
    }
  }
}

String _mimeFromFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  // .jpg / .jpeg / 기타 → 백엔드 기본 분기인 image/jpeg
  return 'image/jpeg';
}

class PhotoUploadException implements Exception {
  final String message;
  const PhotoUploadException(this.message);
  @override
  String toString() => 'PhotoUploadException: $message';
}
