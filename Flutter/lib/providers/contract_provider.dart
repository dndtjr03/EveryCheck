import 'package:flutter/material.dart';
import '../models/real_estate.dart';
import '../services/api_service.dart';
import '../services/contract_service.dart';

class ContractProvider extends ChangeNotifier {
  final ContractService _service;

  List<RealEstate> _contracts = [];
  bool _loading = false;
  String? _error;

  ContractProvider(this._service);

  List<RealEstate> get contracts => _contracts;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadContracts() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _contracts = await _service.listContracts();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = '계약 목록을 불러오지 못했습니다.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<RealEstate?> createContract({
    required String address,
    required DateTime startDate,
    DateTime? endDate,
    String? memo,
  }) async {
    try {
      final contract = await _service.createContract(
        address: address,
        contractStartDate: startDate,
        contractEndDate: endDate,
        memo: memo,
      );
      _contracts.insert(0, contract);
      notifyListeners();
      return contract;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }
}
