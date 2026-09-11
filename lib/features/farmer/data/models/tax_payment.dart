import 'tax_profile.dart' show asDouble;

/// A tax payment the farmer recorded (self-reported, not enforced).
class TaxPayment {
  final Map<String, dynamic> raw;
  const TaxPayment(this.raw);

  static const types = ['income', 'land', 'vehicle', 'other'];

  static String typeLabel(String t) => switch (t) {
        'income' => 'Income / business tax',
        'land' => 'Land development tax',
        'vehicle' => 'Vehicle tax',
        _ => 'Other',
      };

  String get id => raw['id']?.toString() ?? '';
  String get taxType => raw['tax_type']?.toString() ?? 'other';
  String get taxTypeLabel => typeLabel(taxType);
  double get amount => asDouble(raw['amount']);
  String get paymentDate => raw['payment_date']?.toString() ?? '';
  String get referenceNumber => raw['reference_number']?.toString() ?? '';
  String get notes => raw['notes']?.toString() ?? '';
  String get receiptUrl => raw['receipt_url']?.toString() ?? '';

  factory TaxPayment.fromJson(Map<String, dynamic> j) => TaxPayment(j);

  static Map<String, dynamic> toCreateJson({
    required String taxType,
    required double amount,
    required String paymentDate,
    String referenceNumber = '',
    String notes = '',
    String receiptUrl = '',
    bool logAsExpense = false,
  }) =>
      {
        'tax_type': taxType,
        'amount': amount,
        'payment_date': paymentDate,
        'reference_number': referenceNumber,
        'notes': notes,
        'receipt_url': receiptUrl,
        'log_as_expense': logAsExpense,
      };
}
