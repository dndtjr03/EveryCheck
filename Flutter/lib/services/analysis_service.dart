import 'package:image_picker/image_picker.dart';
import '../models/damage_image.dart';
import 'api_service.dart';

class AnalysisService {
  final ApiService _api;
  AnalysisService(this._api);

  Future<DamageImage> uploadImage({
    required int realEstateId,
    required XFile imageFile,
    required DamageType damageType,
  }) async {
    // 관리자 모드: 실제 업로드 없이 성공 처리
    if (await _api.isAdminToken) {
      return DamageImage(
        id: DateTime.now().millisecondsSinceEpoch,
        realEstateId: realEstateId,
        s3Url: imageFile.path,
        damageType: damageType,
        fileHash: 'mock_${DateTime.now().millisecondsSinceEpoch}',
        uploadedAt: DateTime.now(),
      );
    }

    final bytes = await imageFile.readAsBytes();
    final data = await _api.postMultipart(
      '/real-estates/$realEstateId/images',
      fields: {'damage_type': damageType.value},
      fileBytes: bytes,
      fileName: imageFile.name,
      fileField: 'file',
    ) as Map<String, dynamic>;
    return DamageImage.fromJson(data);
  }
}
