import '../models/real_estate.dart';
import 'api_service.dart';

class ContractService {
  final ApiService _api;
  ContractService(this._api);

  // 관리자 전용 인메모리 계약 목록
  static final List<RealEstate> _mockContracts = [];
  static int _mockNextId = 100;

  Future<List<RealEstate>> listContracts() async {
    if (await _api.isAdminToken) {
      return List.from(_mockContracts);
    }
    final data = await _api.get('/real-estates') as List<dynamic>;
    return data.map((e) => RealEstate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RealEstate> getContractDetail(int id) async {
    if (await _api.isAdminToken) {
      return _mockContracts.firstWhere(
        (c) => c.id == id,
        orElse: () => throw ApiException(404, '계약을 찾을 수 없습니다.'),
      );
    }
    final data = await _api.get('/real-estates/$id') as Map<String, dynamic>;
    return RealEstate.fromJson(data);
  }

  Future<RealEstate> createContract({
    required String address,
    required DateTime contractStartDate,
    DateTime? contractEndDate,
    String? memo,
  }) async {
    if (await _api.isAdminToken) {
      final mock = RealEstate(
        id: _mockNextId++,
        ownerId: 0,
        address: address,
        contractStartDate: contractStartDate,
        contractEndDate: contractEndDate,
        memo: memo,
        createdAt: DateTime.now(),
        damageImages: const [],
        repairEstimates: const [],
      );
      _mockContracts.add(mock);
      return mock;
    }
    final data = await _api.post('/real-estates', {
      'address': address,
      'contract_start_date': _dateStr(contractStartDate),
      if (contractEndDate != null) 'contract_end_date': _dateStr(contractEndDate),
      if (memo != null && memo.isNotEmpty) 'memo': memo,
    }) as Map<String, dynamic>;
    return RealEstate.fromJson(data);
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
