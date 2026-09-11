/// DRF serialises DecimalField as a JSON string ("50.00"); tolerate both.
double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

/// One vehicle the farmer owns, for the vehicle-tax estimate.
class TaxVehicle {
  final String type;
  final int count;
  const TaxVehicle(this.type, this.count);

  factory TaxVehicle.fromJson(Map<String, dynamic> j) => TaxVehicle(
        j['type']?.toString() ?? '',
        (j['count'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {'type': type, 'count': count};

  /// "power tiller" -> "Power tiller"
  String get label {
    final t = type.replaceAll('_', ' ');
    return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
  }
}

/// The farmer's saved tax situation (drives the estimate).
class TaxProfile {
  final Map<String, dynamic> raw;
  const TaxProfile(this.raw);

  static const landUnits = ['katha', 'bigha', 'decimal', 'shotangsho', 'acre', 'kani'];
  static const landUses = ['agricultural', 'residential', 'commercial'];
  static const locations = ['rural', 'urban'];
  static const incomeTypes = ['agricultural', 'business', 'mixed'];

  /// Vehicle types the backend rate table knows about.
  static const vehicleTypes = [
    'motorcycle', 'power_tiller', 'tractor', 'cng_autorickshaw', 'pickup', 'van',
    'car_upto_1500cc', 'car_1501_2000cc', 'car_2001_2500cc', 'car_above_2500cc',
    'microbus', 'jeep', 'truck', 'bus',
  ];

  double get landArea => asDouble(raw['land_area']);
  String get landUnit => raw['land_unit']?.toString() ?? 'katha';
  String get landUse => raw['land_use']?.toString() ?? 'agricultural';
  String get location => raw['location']?.toString() ?? 'rural';
  String get incomeType => raw['income_type']?.toString() ?? 'agricultural';
  double get exemptions => asDouble(raw['exemptions']);
  double get rebates => asDouble(raw['rebates']);
  bool get isSenior => raw['is_senior'] == true;
  String get district => raw['district']?.toString() ?? '';
  String get upazila => raw['upazila']?.toString() ?? '';

  List<TaxVehicle> get vehicles => ((raw['vehicles'] as List?) ?? const [])
      .map((e) => TaxVehicle.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  factory TaxProfile.fromJson(Map<String, dynamic> j) => TaxProfile(j);

  Map<String, dynamic> toUpdateJson({
    double? landArea,
    String? landUnit,
    String? landUse,
    String? location,
    String? incomeType,
    double? exemptions,
    double? rebates,
    bool? isSenior,
    String? district,
    String? upazila,
    List<TaxVehicle>? vehicles,
  }) =>
      {
        'land_area': landArea ?? this.landArea,
        'land_unit': landUnit ?? this.landUnit,
        'land_use': landUse ?? this.landUse,
        'location': location ?? this.location,
        'income_type': incomeType ?? this.incomeType,
        'exemptions': exemptions ?? this.exemptions,
        'rebates': rebates ?? this.rebates,
        'is_senior': isSenior ?? this.isSenior,
        'district': district ?? this.district,
        'upazila': upazila ?? this.upazila,
        'vehicles':
            (vehicles ?? this.vehicles).map((v) => v.toJson()).toList(),
      };
}
