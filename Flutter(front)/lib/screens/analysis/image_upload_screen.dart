import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/damage_image.dart';
import '../../models/real_estate.dart';
import '../../providers/contract_provider.dart';
import '../../services/analysis_service.dart';
import '../../services/api_service.dart';

/// 분석 탭 진입점: 계약이 없으면 선택 화면, 있으면 사진 업로드 화면
class ImageUploadScreen extends StatelessWidget {
  final RealEstate? contract;
  const ImageUploadScreen({super.key, this.contract});

  @override
  Widget build(BuildContext context) {
    if (contract != null) {
      return _PhotoUploadScreen(contract: contract!);
    }
    return const _ContractSelectScreen();
  }
}

// ── 계약 선택 화면 ────────────────────────────────────────────────────────────

class _ContractSelectScreen extends StatelessWidget {
  const _ContractSelectScreen();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContractProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('사진 업로드',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: provider.contracts.isEmpty
          ? const _EmptyContracts()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Text(
                    '사진을 업로드할 계약을 선택하세요',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.n700),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: provider.contracts.length,
                    itemBuilder: (_, i) {
                      final c = provider.contracts[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _PhotoUploadScreen(contract: c),
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(kRadius),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text('🏠',
                                      style: TextStyle(fontSize: 22)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.n800)),
                                    const SizedBox(height: 3),
                                    Text(
                                      _fmt(c.contractStartDate),
                                      style: const TextStyle(
                                          fontSize: 12, color: AppColors.n500),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.n300),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

class _EmptyContracts extends StatelessWidget {
  const _EmptyContracts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              '등록된 계약이 없어요',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.n700),
            ),
            const SizedBox(height: 8),
            const Text(
              '기록 탭에서 계약을 먼저 등록해주세요',
              style: TextStyle(fontSize: 13, color: AppColors.n500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 사진 업로드 화면 ──────────────────────────────────────────────────────────

class _PhotoUploadScreen extends StatefulWidget {
  final RealEstate contract;
  const _PhotoUploadScreen({required this.contract});

  @override
  State<_PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<_PhotoUploadScreen> {
  final _picker          = ImagePicker();
  final _analysisService = AnalysisService(ApiService());

  XFile?    _moveInFile;
  Uint8List? _moveInBytes;
  XFile?    _moveOutFile;
  Uint8List? _moveOutBytes;
  bool _uploading = false;

  Future<void> _pick(bool isMoveIn) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.n300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.camera_alt_outlined,
                    color: AppColors.primary),
              ),
              title: const Text('카메라로 촬영',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                await _pickFrom(ImageSource.camera, isMoveIn);
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library_outlined,
                    color: AppColors.secondary),
              ),
              title: const Text('앨범에서 선택',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                await _pickFrom(ImageSource.gallery, isMoveIn);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFrom(ImageSource source, bool isMoveIn) async {
    final f = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1920);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (isMoveIn) {
        _moveInFile  = f;
        _moveInBytes = bytes;
      } else {
        _moveOutFile  = f;
        _moveOutBytes = bytes;
      }
    });
  }

  Future<void> _saveImages() async {
    if (_moveInFile == null && _moveOutFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('사진을 최소 1장 선택해주세요.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _uploading = true);

    try {
      int uploaded = 0;
      if (_moveInFile != null) {
        await _analysisService.uploadImage(
          realEstateId: widget.contract.id,
          imageFile: _moveInFile!,
          damageType: DamageType.other,
        );
        uploaded++;
      }
      if (_moveOutFile != null) {
        await _analysisService.uploadImage(
          realEstateId: widget.contract.id,
          imageFile: _moveOutFile!,
          damageType: DamageType.other,
        );
        uploaded++;
      }

      if (!mounted) return;
      setState(() {
        _uploading    = false;
        _moveInFile   = null;
        _moveInBytes  = null;
        _moveOutFile  = null;
        _moveOutBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('사진 $uploaded장이 저장됐어요 ✓'),
          backgroundColor: AppColors.secondary,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.danger),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          widget.contract.address,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            _StepIndicator(current: 0),
            const SizedBox(height: 20),
            const Text(
              '어떤 사진을 올리시겠어요?',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.n700),
            ),
            const SizedBox(height: 14),
            _UploadCard(
              emoji: '📦',
              label: '입주 시 사진',
              desc: '임대 계약 시작일 기준',
              imageBytes: _moveInBytes,
              done: _moveInFile != null,
              onTap: () => _pick(true),
            ),
            const SizedBox(height: 10),
            _UploadCard(
              emoji: '🚪',
              label: '퇴거 시 사진',
              desc: '계약 만료 후 현재 상태',
              imageBytes: _moveOutBytes,
              done: _moveOutFile != null,
              onTap: () => _pick(false),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: (_moveInFile == null && _moveOutFile == null) || _uploading
                  ? null
                  : _saveImages,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.n200,
                minimumSize: const Size(double.infinity, 52),
                shape: const StadiumBorder(),
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      '📁 사진 저장하기',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step Indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int current;
  const _StepIndicator({required this.current});

  static const _steps = ['사진 선택', '저장 완료'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Container(
            width: 32, height: 2,
            color: AppColors.n200,
            margin: const EdgeInsets.only(bottom: 14),
          );
        }
        final idx = i ~/ 2;
        final active = idx == current;
        return Column(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.n200,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('${idx + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : AppColors.n400)),
            ),
            const SizedBox(height: 4),
            Text(_steps[idx],
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? AppColors.primary : AppColors.n400)),
          ],
        );
      }),
    );
  }
}

// ── Upload Card ───────────────────────────────────────────────────────────────

class _UploadCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String desc;
  final Uint8List? imageBytes;
  final bool done;
  final VoidCallback onTap;

  const _UploadCard({
    required this.emoji,
    required this.label,
    required this.desc,
    required this.imageBytes,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: done ? AppColors.secondaryLight : AppColors.surface,
          border: Border.all(
            color: done ? AppColors.secondary : AppColors.n200,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageBytes != null
                  ? Image.memory(imageBytes!,
                      width: 60, height: 60, fit: BoxFit.cover)
                  : Container(
                      width: 60, height: 60,
                      color: done ? AppColors.secondary : AppColors.n100,
                      alignment: Alignment.center,
                      child: Text(
                        done ? '✅' : emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.n800)),
                  const SizedBox(height: 3),
                  Text(
                    done ? '사진이 선택됐어요 ✓' : desc,
                    style: TextStyle(
                      fontSize: 13,
                      color: done
                          ? const Color(0xFF2A9060)
                          : AppColors.n500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              done
                  ? Icons.check_circle
                  : Icons.add_photo_alternate_outlined,
              color: done ? AppColors.secondary : AppColors.n400,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
