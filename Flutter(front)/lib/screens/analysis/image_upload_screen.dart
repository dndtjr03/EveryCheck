import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_config.dart';
import '../../models/real_estate.dart';
import '../../models/repair_estimate.dart';
import '../../services/analysis_service.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_button.dart';
import 'analysis_result_screen.dart';

class ImageUploadScreen extends StatefulWidget {
  final RealEstate contract;
  const ImageUploadScreen({super.key, required this.contract});

  @override
  State<ImageUploadScreen> createState() => _ImageUploadScreenState();
}

class _ImageUploadScreenState extends State<ImageUploadScreen> {
  final _picker = ImagePicker();
  final _analysisService = AnalysisService(ApiService());

  File? _image;
  bool _uploading = false;
  bool _analyzing = false;
  String? _error;
  double _progress = 0;

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920);
    if (picked == null) return;
    setState(() { _image = File(picked.path); _error = null; });
  }

  Future<void> _startAnalysis() async {
    if (_image == null) return;
    setState(() { _uploading = true; _error = null; _progress = 0.1; });

    try {
      // 1) 분석 요청 전송
      final job = await _analysisService.startAnalysis(
        realEstateId: widget.contract.id,
        imageFile: _image!,
      );
      final estimateId = job['repair_estimate_id'] as int;
      setState(() { _uploading = false; _analyzing = true; _progress = 0.3; });

      // 2) 완료될 때까지 폴링
      RepairEstimate? result;
      for (int i = 0; i < AppConfig.analysisPollMaxRetries; i++) {
        await Future.delayed(Duration(milliseconds: AppConfig.analysisPollIntervalMs));
        if (!mounted) return;

        final est = await _analysisService.getEstimate(widget.contract.id, estimateId);
        setState(() => _progress = 0.3 + (i / AppConfig.analysisPollMaxRetries) * 0.6);

        if (est.analysisStatus == AnalysisStatus.completed) {
          result = est;
          break;
        } else if (est.analysisStatus == AnalysisStatus.failed) {
          throw Exception('AI 분석에 실패했습니다.');
        }
      }

      if (!mounted) return;
      setState(() { _analyzing = false; _progress = 1.0; });

      if (result != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AnalysisResultScreen(
              contract: widget.contract,
              estimate: result!,
            ),
          ),
        );
      } else {
        setState(() => _error = '분석 시간이 초과됐습니다. 잠시 후 계약 상세에서 확인하세요.');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _uploading = false; _analyzing = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _uploading = false; _analyzing = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('손상 이미지 분석')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 이미지 미리보기
            _ImagePreview(image: _image, onPick: _pickImage),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),
            if (_analyzing || _uploading) ...[
              const SizedBox(height: 16),
              _AnalysisProgress(progress: _progress, uploading: _uploading),
            ],
            const Spacer(),
            // 안내 문구
            const Text(
              '📸 손상된 부위를 선명하게 촬영해주세요.\nAI가 손상 유형과 수리비를 자동 산정합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'AI 분석 시작',
              onPressed: (_image == null || _uploading || _analyzing) ? null : _startAnalysis,
              loading: _uploading || _analyzing,
              icon: Icons.auto_awesome,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final File? image;
  final void Function(ImageSource) onPick;

  const _ImagePreview({required this.image, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSourceSheet(context),
      child: Container(
        width: double.infinity,
        height: 260,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: image != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(image!, fit: BoxFit.cover),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 56, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('탭하여 사진 선택', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 4),
                  Text('카메라 또는 갤러리', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
      ),
    );
  }

  void _showSourceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () { Navigator.pop(context); onPick(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () { Navigator.pop(context); onPick(ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisProgress extends StatelessWidget {
  final double progress;
  final bool uploading;

  const _AnalysisProgress({required this.progress, required this.uploading});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[200],
          valueColor: const AlwaysStoppedAnimation(Color(0xFF3D7BFF)),
        ),
        const SizedBox(height: 8),
        Text(
          uploading ? '이미지 업로드 중...' : 'AI 분석 중... 잠시만 기다려주세요.',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ],
    );
  }
}
