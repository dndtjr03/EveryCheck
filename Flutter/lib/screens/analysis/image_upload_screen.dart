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

/// 한 장의 선택된 사진 (파일 + 디코딩된 바이트).
class _PickedPhoto {
  final XFile file;
  final Uint8List bytes;
  const _PickedPhoto(this.file, this.bytes);
}

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
      appBar: AppBar(
        title: const Text('사진 업로드',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderOf(context)),
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
                        fontSize: 15, fontWeight: FontWeight.w700),
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
                            color: surfaceOf(context),
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
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(
                                      _fmt(c.contractStartDate),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.n500),
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
          children: const [
            Text('📋', style: TextStyle(fontSize: 48)),
            SizedBox(height: 16),
            Text(
              '등록된 계약이 없어요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              '계약 탭에서 계약을 먼저 등록해주세요',
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
  static const int _maxPerGroup = 30;

  final _picker          = ImagePicker();
  final _analysisService = AnalysisService(ApiService());

  final List<_PickedPhoto> _moveInPhotos  = [];
  final List<_PickedPhoto> _moveOutPhotos = [];

  bool _uploading = false;
  int  _uploadProgress = 0;
  int  _uploadTotal    = 0;

  List<_PickedPhoto> _group(bool isMoveIn) =>
      isMoveIn ? _moveInPhotos : _moveOutPhotos;

  /// 카메라/갤러리 선택 BottomSheet
  Future<void> _showSourceSheet(bool isMoveIn) async {
    final group = _group(isMoveIn);
    if (group.length >= _maxPerGroup) {
      _showSnack('최대 $_maxPerGroup장까지 추가할 수 있어요.', AppColors.danger);
      return;
    }
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
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
                Navigator.pop(sheetCtx);
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
                Navigator.pop(sheetCtx);
                await _pickFrom(ImageSource.gallery, isMoveIn);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 실제 picker 호출 + 사진 추가 + 추가 촬영 다이얼로그
  /// - 카메라: 한 장씩 촬영 → 다이얼로그
  /// - 갤러리: 한 번에 여러 장 선택 가능 (남은 슬롯만큼만 추가) → 다이얼로그
  Future<void> _pickFrom(ImageSource source, bool isMoveIn) async {
    final group = _group(isMoveIn);
    final remaining = _maxPerGroup - group.length;
    if (remaining <= 0) {
      _showSnack('최대 $_maxPerGroup장에 도달했어요.', AppColors.danger);
      return;
    }

    final List<XFile> picked;
    if (source == ImageSource.gallery) {
      // 앨범에서 여러 장 한 번에 선택
      final files = await _picker.pickMultiImage(
        imageQuality: 85, maxWidth: 1920,
      );
      if (files.isEmpty) return;
      picked = files.take(remaining).toList();
      if (files.length > remaining) {
        _showSnack(
          '최대 $_maxPerGroup장 제한으로 ${picked.length}장만 추가했어요.',
          AppColors.accent,
        );
      }
    } else {
      // 카메라는 한 번에 한 장
      final f = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1920,
      );
      if (f == null) return;
      picked = [f];
    }

    // 선택된 파일 모두 디코딩 후 그룹에 추가
    final newPhotos = <_PickedPhoto>[];
    for (final f in picked) {
      final bytes = await f.readAsBytes();
      newPhotos.add(_PickedPhoto(f, bytes));
    }
    if (!mounted) return;
    setState(() => _group(isMoveIn).addAll(newPhotos));

    final updated = _group(isMoveIn);
    if (updated.length >= _maxPerGroup) {
      _showSnack('최대 $_maxPerGroup장에 도달했어요.', AppColors.primary);
      return;
    }

    // 한 번의 추가 동작이 끝날 때마다 "추가로 촬영하시겠습니까?" 안내
    await _askAddMore(isMoveIn);
  }

  Future<void> _askAddMore(bool isMoveIn) async {
    final addMore = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('추가로 촬영하시겠습니까?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          '${isMoveIn ? "입주" : "퇴거"} 사진 ${_group(isMoveIn).length}장이 추가됐어요.\n'
          '더 추가하시면 카메라/앨범 선택지가 다시 나타납니다.',
          style: const TextStyle(fontSize: 14, color: AppColors.n500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('그만하기',
                style: TextStyle(color: AppColors.n500)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('추가 촬영'),
          ),
        ],
      ),
    );
    if (addMore == true && mounted) {
      await _showSourceSheet(isMoveIn);
    }
  }

  void _removePhoto(bool isMoveIn, int index) {
    setState(() => _group(isMoveIn).removeAt(index));
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _saveImages() async {
    final total = _moveInPhotos.length + _moveOutPhotos.length;
    if (total == 0) {
      _showSnack('사진을 최소 1장 선택해주세요.', AppColors.danger);
      return;
    }

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _uploadTotal = total;
    });

    try {
      for (final p in _moveInPhotos) {
        await _analysisService.uploadImage(
          realEstateId: widget.contract.id,
          imageFile: p.file,
          damageType: DamageType.other,
        );
        if (!mounted) return;
        setState(() => _uploadProgress++);
      }
      for (final p in _moveOutPhotos) {
        await _analysisService.uploadImage(
          realEstateId: widget.contract.id,
          imageFile: p.file,
          damageType: DamageType.other,
        );
        if (!mounted) return;
        setState(() => _uploadProgress++);
      }

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadProgress = 0;
        _uploadTotal = 0;
        _moveInPhotos.clear();
        _moveOutPhotos.clear();
      });
      _showSnack('사진 $total장이 저장됐어요 ✓', AppColors.secondary);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _showSnack(e.message, AppColors.danger);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _showSnack(e.toString(), AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _moveInPhotos.length + _moveOutPhotos.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.contract.address,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderOf(context)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            const _StepIndicator(current: 0),
            const SizedBox(height: 20),
            const Text(
              '어떤 사진을 올리시겠어요?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '각 그룹당 최대 $_maxPerGroup장까지 추가할 수 있어요.',
              style: const TextStyle(fontSize: 12, color: AppColors.n500),
            ),
            const SizedBox(height: 14),
            _UploadGroupCard(
              emoji: '📦',
              label: '입주 시 사진',
              desc: '임대 계약 시작일 기준',
              photos: _moveInPhotos,
              max: _maxPerGroup,
              onAdd: () => _showSourceSheet(true),
              onRemove: (i) => _removePhoto(true, i),
            ),
            const SizedBox(height: 10),
            _UploadGroupCard(
              emoji: '🚪',
              label: '퇴거 시 사진',
              desc: '계약 만료 후 현재 상태',
              photos: _moveOutPhotos,
              max: _maxPerGroup,
              onAdd: () => _showSourceSheet(false),
              onRemove: (i) => _removePhoto(false, i),
            ),
            const SizedBox(height: 32),
            if (_uploading) ...[
              LinearProgressIndicator(
                value: _uploadTotal == 0
                    ? null
                    : _uploadProgress / _uploadTotal,
                color: AppColors.primary,
                backgroundColor: AppColors.primaryLight,
              ),
              const SizedBox(height: 8),
              Text(
                '$_uploadProgress / $_uploadTotal 업로드 중...',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.n500),
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: totalCount == 0 || _uploading ? null : _saveImages,
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
                  : Text(
                      totalCount == 0
                          ? '📁 사진 저장하기'
                          : '📁 사진 $totalCount장 저장하기',
                      style: const TextStyle(
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

// ── Upload Group Card (썸네일 가로 스크롤 + 추가 버튼) ────────────────────────

class _UploadGroupCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String desc;
  final List<_PickedPhoto> photos;
  final int max;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  const _UploadGroupCard({
    required this.emoji,
    required this.label,
    required this.desc,
    required this.photos,
    required this.max,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = photos.isEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEmpty ? surfaceOf(context) : AppColors.secondaryLight,
        border: Border.all(
          color: isEmpty
              ? borderOf(context)
              : AppColors.secondary,
          width: isEmpty ? 1 : 2,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      isEmpty
                          ? desc
                          : '${photos.length}장 선택됨 (최대 $max장)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isEmpty
                            ? AppColors.n500
                            : const Color(0xFF2A9060),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isEmpty)
                const Icon(Icons.check_circle,
                    color: AppColors.secondary, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          // 썸네일 + 추가 타일
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i == photos.length) {
                  // 추가 타일
                  final disabled = photos.length >= max;
                  return GestureDetector(
                    onTap: disabled ? null : onAdd,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: disabled
                            ? AppColors.n100
                            : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: disabled
                              ? AppColors.n200
                              : AppColors.primary,
                          width: 1.5,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          disabled
                              ? Icons.block
                              : Icons.add_a_photo_outlined,
                          color: disabled
                              ? AppColors.n400
                              : AppColors.primary,
                          size: 28,
                        ),
                      ),
                    ),
                  );
                }
                final p = photos[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        p.bytes,
                        width: 80, height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2, right: 2,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
