/// Result of POST /api/farmers/tax/calculate/ — the estimated tax + a
/// farmer-friendly, line-by-line breakdown.
class TaxCalculationResult {
  final Map<String, dynamic> raw;
  const TaxCalculationResult(this.raw);

  double get incomeTax => (raw['income_tax'] as num?)?.toDouble() ?? 0;
  double get landTax => (raw['land_tax'] as num?)?.toDouble() ?? 0;
  double get vehicleTax => (raw['vehicle_tax'] as num?)?.toDouble() ?? 0;
  double get total => (raw['total'] as num?)?.toDouble() ?? 0;
  double get totalRevenue => (raw['total_revenue'] as num?)?.toDouble() ?? 0;
  double get netIncome => (raw['net_income'] as num?)?.toDouble() ?? 0;
  String get taxYear => raw['tax_year']?.toString() ?? '';

  /// Whole-estimate breakdown (section headers + indented detail lines).
  List<String> get breakdown =>
      ((raw['breakdown'] as List?) ?? const []).map((e) => e.toString()).toList();

  List<String> _sub(String key) {
    final part = raw[key];
    if (part is Map && part['breakdown'] is List) {
      return (part['breakdown'] as List).map((e) => e.toString()).toList();
    }
    return const [];
  }

  List<String> get incomeBreakdown => _sub('income');
  List<String> get landBreakdown => _sub('land');
  List<String> get vehicleBreakdown => _sub('vehicle');

  factory TaxCalculationResult.fromJson(Map<String, dynamic> j) =>
      TaxCalculationResult(j);
}
