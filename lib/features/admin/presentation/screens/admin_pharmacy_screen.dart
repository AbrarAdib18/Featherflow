import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';

class AdminPharmacyScreen extends StatefulWidget {
  const AdminPharmacyScreen({super.key});

  @override
  State<AdminPharmacyScreen> createState() => _AdminPharmacyScreenState();
}

class _AdminPharmacyScreenState extends State<AdminPharmacyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_MedData> _medicines;
  late List<_PharmacyData> _pharmacies;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _medicines = List.of(_kMedicines);
    _pharmacies = List.of(_kPharmacies);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _approveProduct(String id) {
    final med = _medicines.firstWhere((m) => m.id == id);
    setState(() {
      final i = _medicines.indexOf(med);
      _medicines[i] = med.copyWith(status: 'Approved');
    });
    AuditService.instance
        .log('Pharmacy Management', 'Approve Product', med.name);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Product approved'),
        backgroundColor: AColors.green,
        duration: Duration(seconds: 2)));
  }

  void _removeProduct(String id) {
    final med = _medicines.firstWhere((m) => m.id == id);
    setState(() {
      final i = _medicines.indexOf(med);
      _medicines[i] = med.copyWith(status: 'Removed');
    });
    AuditService.instance
        .log('Pharmacy Management', 'Remove Product', med.name);
  }

  void _approvePharmacy(String id) {
    final ph = _pharmacies.firstWhere((p) => p.id == id);
    setState(() {
      final i = _pharmacies.indexOf(ph);
      _pharmacies[i] = ph.copyWith(status: 'Verified');
    });
    AuditService.instance
        .log('Pharmacy Management', 'Approve Pharmacy', ph.name);
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Pharmacy Management',
      module: AdminModule.pharmacyManagement,
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Pharmacies'),
                Tab(text: 'Medicines'),
                Tab(text: 'Expiring Soon'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _PharmacyList(
                    pharmacies: _pharmacies,
                    onApprove: _approvePharmacy),
                _MedicineList(
                    medicines: _medicines,
                    onApprove: _approveProduct,
                    onRemove: _removeProduct),
                _ExpiryList(medicines: _medicines
                    .where((m) => m.expiresInDays <= 30)
                    .toList()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pharmacies tab ────────────────────────────────────────────────────────────

class _PharmacyList extends StatelessWidget {
  final List<_PharmacyData> pharmacies;
  final void Function(String) onApprove;

  const _PharmacyList(
      {required this.pharmacies, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: pharmacies.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) =>
          _PharmacyCard(pharmacy: pharmacies[i], onApprove: onApprove),
    );
  }
}

class _PharmacyCard extends StatelessWidget {
  final _PharmacyData pharmacy;
  final void Function(String) onApprove;

  const _PharmacyCard(
      {required this.pharmacy, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    final statusColor = pharmacy.status == 'Verified'
        ? AColors.green
        : pharmacy.status == 'Pending'
            ? AColors.amber
            : AColors.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: pharmacy.status == 'Pending'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AColors.blueLight,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.local_pharmacy_outlined,
                    color: AColors.blue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pharmacy.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AColors.textPrimary)),
                    Text(pharmacy.location,
                        style: const TextStyle(
                            fontSize: 12, color: AColors.textSecondary)),
                  ],
                ),
              ),
              aChip(pharmacy.status, statusColor, statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Pill(Icons.inventory_2_outlined,
                  '${pharmacy.productCount} products', AColors.blue),
              const SizedBox(width: 10),
              _Pill(Icons.shopping_cart_outlined,
                  '${pharmacy.monthlyOrders} orders/mo', AColors.secondary),
              const SizedBox(width: 10),
              _Pill(Icons.star_outline, pharmacy.rating.toString(),
                  AColors.amber),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (pharmacy.status == 'Pending')
                PermissionGuard(
                  module: AdminModule.pharmacyManagement,
                  permission: AdminPermission.approve,
                  child: _Chip('Approve', AColors.green,
                      () => onApprove(pharmacy.id)),
                ),
              const SizedBox(width: 8),
              PermissionGuard(
                module: AdminModule.pharmacyManagement,
                permission: AdminPermission.edit,
                child: _Chip('View Details', AColors.blue, () {}),
              ),
              const SizedBox(width: 8),
              if (pharmacy.status == 'Verified')
                PermissionGuard(
                  module: AdminModule.pharmacyManagement,
                  permission: AdminPermission.delete,
                  child: _Chip('Suspend', AColors.red, () {}),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Medicines tab ─────────────────────────────────────────────────────────────

class _MedicineList extends StatelessWidget {
  final List<_MedData> medicines;
  final void Function(String) onApprove;
  final void Function(String) onRemove;

  const _MedicineList(
      {required this.medicines,
      required this.onApprove,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: medicines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _MedicineCard(
          med: medicines[i],
          onApprove: onApprove,
          onRemove: onRemove),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final _MedData med;
  final void Function(String) onApprove;
  final void Function(String) onRemove;

  const _MedicineCard(
      {required this.med, required this.onApprove, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final statusColor = med.status == 'Approved'
        ? AColors.green
        : med.status == 'Pending'
            ? AColors.amber
            : AColors.red;
    final expiryWarning = med.expiresInDays <= 30;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: expiryWarning || med.status == 'Pending'),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AColors.greenLight,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.medication_outlined,
                color: AColors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AColors.textPrimary)),
                Text('${med.pharmacy} · ৳${med.price}',
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    aChip(med.status, statusColor, statusColor, fontSize: 10),
                    if (expiryWarning) ...[
                      const SizedBox(width: 6),
                      aChip('Exp in ${med.expiresInDays}d', AColors.orange,
                          AColors.orange, fontSize: 10),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (med.status == 'Pending')
                PermissionGuard(
                  module: AdminModule.pharmacyManagement,
                  permission: AdminPermission.approve,
                  child: _Chip(
                      'Approve', AColors.green, () => onApprove(med.id)),
                ),
              const SizedBox(height: 4),
              PermissionGuard(
                module: AdminModule.pharmacyManagement,
                permission: AdminPermission.delete,
                child: _Chip(
                    'Remove', AColors.red, () => onRemove(med.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Expiry tab ────────────────────────────────────────────────────────────────

class _ExpiryList extends StatelessWidget {
  final List<_MedData> medicines;

  const _ExpiryList({required this.medicines});

  @override
  Widget build(BuildContext context) {
    if (medicines.isEmpty) {
      return const Center(
          child: Text('No medicines expiring soon.',
              style:
                  TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: medicines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.all(14),
        decoration: aCard(highlight: true),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AColors.orangeLight,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AColors.orange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(medicines[i].name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AColors.textPrimary)),
                  Text(medicines[i].pharmacy,
                      style: const TextStyle(
                          fontSize: 11, color: AColors.textSecondary)),
                ],
              ),
            ),
            aChip('Exp ${medicines[i].expiresInDays}d', AColors.orange,
                AColors.orange),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Pill(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Chip(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

class _PharmacyData {
  final String id, name, location, status;
  final int productCount, monthlyOrders;
  final double rating;

  const _PharmacyData({
    required this.id,
    required this.name,
    required this.location,
    required this.status,
    required this.productCount,
    required this.monthlyOrders,
    required this.rating,
  });

  _PharmacyData copyWith({String? status}) => _PharmacyData(
        id: id,
        name: name,
        location: location,
        status: status ?? this.status,
        productCount: productCount,
        monthlyOrders: monthlyOrders,
        rating: rating,
      );
}

const _kPharmacies = [
  _PharmacyData(
      id: 'P001',
      name: 'MedPlus Veterinary Rx',
      location: 'Rajshahi',
      status: 'Verified',
      productCount: 142,
      monthlyOrders: 380,
      rating: 4.7),
  _PharmacyData(
      id: 'P002',
      name: 'AgroVet Supplies',
      location: 'Dhaka',
      status: 'Pending',
      productCount: 78,
      monthlyOrders: 0,
      rating: 0.0),
  _PharmacyData(
      id: 'P003',
      name: 'PoultryMed Store',
      location: 'Chittagong',
      status: 'Verified',
      productCount: 94,
      monthlyOrders: 210,
      rating: 4.4),
];

class _MedData {
  final String id, name, pharmacy, status;
  final int price, expiresInDays;

  const _MedData({
    required this.id,
    required this.name,
    required this.pharmacy,
    required this.status,
    required this.price,
    required this.expiresInDays,
  });

  _MedData copyWith({String? status}) => _MedData(
        id: id,
        name: name,
        pharmacy: pharmacy,
        status: status ?? this.status,
        price: price,
        expiresInDays: expiresInDays,
      );
}

const _kMedicines = [
  _MedData(
      id: 'M001',
      name: 'Oxytetracycline 20%',
      pharmacy: 'MedPlus Veterinary Rx',
      status: 'Approved',
      price: 420,
      expiresInDays: 90),
  _MedData(
      id: 'M002',
      name: 'Newcastle Vaccine',
      pharmacy: 'MedPlus Veterinary Rx',
      status: 'Pending',
      price: 680,
      expiresInDays: 25),
  _MedData(
      id: 'M003',
      name: 'Vitamin AD3E Supplement',
      pharmacy: 'PoultryMed Store',
      status: 'Approved',
      price: 290,
      expiresInDays: 180),
  _MedData(
      id: 'M004',
      name: 'Coccidiostat Premix',
      pharmacy: 'PoultryMed Store',
      status: 'Approved',
      price: 550,
      expiresInDays: 18),
];
