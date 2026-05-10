import '../models/real_estate.dart';
import 'api_service.dart';

class ContractService {
  final ApiService _api;
  ContractService(this._api);

  Future<List<RealEstate>> listContracts() async {
    final data = await _api.get('/real-estates') as List<dynamic>;
    return data.map((e) => RealEstate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RealEstate> getContractDetail(int id) async {
    final data = await _api.get('/real-estates/$id') as Map<String, dynamic>;
    return RealEstate.fromJson(data);
  }

  Future<RealEstate> createContract({
    required String address,
    required DateTime contractStartDate,
    DateTime? contractEndDate,
    String? memo,
  }) async {
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
