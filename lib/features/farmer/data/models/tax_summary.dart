import 'tax_calculation_result.dart';

/// One row of the tax summary — estimated vs paid vs pending for a tax type.
class TaxSummaryLine {
  final String taxType;
  final String label;
  final double estimated;
  final double paid;
  final double pending;

  const TaxSummaryLine({
    required this.taxType,
    required this.label,
    required this.estimated,
    required this.paid,
    required this.pending,
  });

  factory TaxSummaryLine.fromJson(Map<String, dynamic> j) => TaxSummaryLine(
        taxType: j['tax_type']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        estimated: (j['estimated'] as num?)?.toDouble() ?? 0,
        paid: (j['paid'] as num?)?.toDouble() ?? 0,
        pending: (j['pending'] as num?)?.toDouble() ?? 0,
      );
}

/// Result of GET /api/farmers/tax/summary/.
class TaxSummary {
  final int year;
  final String taxYear;
  final double estimatedTotal;
  final double totalPaid;
  final double pending;
  final List<TaxSummaryLine> lines;
  final TaxCalculationResult estimate;
  final String disclaimer;

  const TaxSummary({
    required this.year,
    required this.taxYear,
    required this.estimatedTotal,
    required this.totalPaid,
    required this.pending,
    required this.lines,
    required this.estimate,
    required this.disclaimer,
  });

  factory TaxSummary.fromJson(Map<String, dynamic> j) => TaxSummary(
        year: (j['year'] as num?)?.toInt() ?? DateTime.now().year,
        taxYear: j['tax_year']?.toString() ?? '',
        estimatedTotal: (j['estimated_total'] as num?)?.toDouble() ?? 0,
        totalPaid: (j['total_paid'] as num?)?.toDouble() ?? 0,
        pending: (j['pending'] as num?)?.toDouble() ?? 0,
        lines: ((j['lines'] as List?) ?? const [])
            .map((e) => TaxSummaryLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        estimate: TaxCalculationResult(
            Map<String, dynamic>.from((j['estimate'] as Map?) ?? const {})),
        disclaimer: j['disclaimer']?.toString() ?? '',
      );
}
