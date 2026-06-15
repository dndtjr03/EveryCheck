import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

/// 사용자가 선택/촬영한 사진 1장 (파일 경로 + 디코딩된 바이트).
/// 업로드·분석 파이프라인에 넘기는 단순 컨테이너.
class PickedPhoto {
  final XFile file;
  final Uint8List bytes;
  const PickedPhoto(this.file, this.bytes);
}
