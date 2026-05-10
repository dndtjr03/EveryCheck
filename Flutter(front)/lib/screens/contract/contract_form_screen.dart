import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/contract_provider.dart';
import '../../widgets/common/app_button.dart';

class ContractFormScreen extends StatefulWidget {
  const ContractFormScreen({super.key});

  @override
  State<ContractFormScreen> createState() => _ContractFormScreenState();
}

class _ContractFormScreenState extends State<ContractFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isStart ? '입주일 선택' : '퇴거일 선택',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  String _fmt(DateTime d) =>
      '${d.year}년 ${d.month}월 ${d.day}일';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입주일을 선택하세요.')),
      );
      return;
    }
    setState(() => _loading = true);
    final contract = await context.read<ContractProvider>().createContract(
          address: _addressCtrl.text.trim(),
          startDate: _startDate!,
          endDate: _endDate,
          memo: _memoCtrl.text.trim(),
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (contract != null) {
      Navigator.pop(context, contract);
    } else {
      final err = context.read<ContractProvider>().error ?? '등록에 실패했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('계약 등록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 주소
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: '임대 주소 *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  hintText: '예: 서울시 마포구 공덕동 123',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? '주소를 입력하세요.' : null,
              ),
              const SizedBox(height: 20),
              // 입주일
              const Text('입주일 *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              _DatePickerTile(
                label: _startDate != null ? _fmt(_startDate!) : '입주일을 선택하세요',
                hasValue: _startDate != null,
                onTap: () => _pickDate(isStart: true),
              ),
              const SizedBox(height: 16),
              // 퇴거일 (선택)
              const Text('퇴거일 (선택)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              _DatePickerTile(
                label: _endDate != null ? _fmt(_endDate!) : '퇴거일을 선택하세요 (선택)',
                hasValue: _endDate != null,
                onTap: () => _pickDate(isStart: false),
                trailing: _endDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _endDate = null),
                      )
                    : null,
              ),
              const SizedBox(height: 20),
              // 메모
              TextFormField(
                controller: _memoCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '메모 (선택)',
                  prefixIcon: Icon(Icons.note_outlined),
                  hintText: '특이사항 등을 기록하세요.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 32),
              AppButton(label: '계약 등록', onPressed: _submit, loading: _loading),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final bool hasValue;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DatePickerTile({
    required this.label,
    required this.hasValue,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: hasValue ? const Color(0xFF3D7BFF) : Colors.black38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: hasValue ? Colors.black87 : Colors.black38,
                  fontSize: 14,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
