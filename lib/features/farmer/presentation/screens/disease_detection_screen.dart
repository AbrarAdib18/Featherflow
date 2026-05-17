import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/app_localizations.dart';

class DiseaseDetectionScreen extends StatefulWidget {
  const DiseaseDetectionScreen({super.key});

  @override
  State<DiseaseDetectionScreen> createState() =>
      _DiseaseDetectionScreenState();
}

class _DiseaseDetectionScreenState extends State<DiseaseDetectionScreen> {
  bool _imageUploaded = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l.diseaseDetection,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.sm),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.18),
              borderRadius: AppRadius.fullAll,
              border: Border.all(color: AppColors.secondary),
            ),
            child: Text(
              l.freeScansBadge,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UploadSection(onUpload: () => setState(() => _imageUploaded = true)),
            const SizedBox(height: AppSpacing.md),
            if (_imageUploaded) ...[
              const _ResultCard(),
              const SizedBox(height: AppSpacing.md),
            ],
            const _RecentCasesSection(),
            const SizedBox(height: AppSpacing.md),
            const _PaywallBanner(),
            const SizedBox(height: AppSpacing.md),
            _FindVetButton(onTap: () => context.go('/farmer/vet-map')),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ── Upload Section ────────────────────────────────────────────────────────────

class _UploadSection extends StatelessWidget {
  final VoidCallback onUpload;

  const _UploadSection({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.uploadImage,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: onUpload,
          child: CustomPaint(
            painter: _DashedBorderPainter(),
            child: Container(
              width: double.infinity,
              height: 180,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: onUpload,
                        icon: const Icon(Icons.camera_alt_outlined,
                            color: AppColors.primary, size: 28),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      IconButton(
                        onPressed: onUpload,
                        icon: const Icon(Icons.photo_library_outlined,
                            color: AppColors.primary, size: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.dropChickenImage,
                    style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: onUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                      shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.smAll),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    child: Text(l.chooseFile),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                l.clearImagesHint,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 8.0;
    const dashSpace = 5.0;
    const radius = Radius.circular(AppRadius.lg);

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        radius,
      ));

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dashWidth), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Result Card ───────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  const _ResultCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.detectionResult,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Newcastle Disease',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: AppColors.error),
                ),
                child: Text(
                  l.severityHigh,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(l.confidence,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const Text(
                '92%',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: const LinearProgressIndicator(
                    value: 0.92,
                    backgroundColor: Color(0xFFE0E8E4),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.secondary),
                    minHeight: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Color(0xFFE0E8E4)),
          const SizedBox(height: AppSpacing.sm),
          _ActionList(
            title: l.whatToDo,
            titleColor: AppColors.secondary,
            icon: Icons.check_circle_outline,
            iconColor: AppColors.secondary,
            items: [
              l.actionIsolate,
              l.actionHydration,
              l.actionTemperature,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ActionList(
            title: l.doNotDo,
            titleColor: AppColors.error,
            icon: Icons.cancel_outlined,
            iconColor: AppColors.error,
            items: [l.actionNoSelfMed],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.smart_toy_outlined, size: 16),
                  label: Text(l.askChatbot),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.medical_services_outlined, size: 16),
                  label: Text(l.bookVet),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  final String title;
  final Color titleColor;
  final IconData icon;
  final Color iconColor;
  final List<String> items;

  const _ActionList({
    required this.title,
    required this.titleColor,
    required this.icon,
    required this.iconColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: titleColor),
        ),
        const SizedBox(height: AppSpacing.xs),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15, color: iconColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

// ── Recent Cases ──────────────────────────────────────────────────────────────

enum _CaseStatus { detected, suspected, clear }

class _CaseData {
  final String date;
  final String caseName;
  final String confidence;
  final _CaseStatus statusType;

  const _CaseData({
    required this.date,
    required this.caseName,
    required this.confidence,
    required this.statusType,
  });
}

const _cases = <_CaseData>[
  _CaseData(
      date: '10 May 2026',
      caseName: 'Newcastle Disease',
      confidence: '92%',
      statusType: _CaseStatus.detected),
  _CaseData(
      date: '07 May 2026',
      caseName: 'Avian Influenza',
      confidence: '78%',
      statusType: _CaseStatus.suspected),
  _CaseData(
      date: '02 May 2026',
      caseName: 'Healthy',
      confidence: '95%',
      statusType: _CaseStatus.clear),
];

class _RecentCasesSection extends StatelessWidget {
  const _RecentCasesSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.recentCases,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: const Color(0xFFDEEAE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              const _CaseTableHeader(),
              const Divider(height: 1, color: Color(0xFFDEEAE5)),
              ...List.generate(
                _cases.length,
                (i) => Column(
                  children: [
                    _CaseTableRow(data: _cases[i]),
                    if (i < _cases.length - 1)
                      const Divider(height: 1, color: Color(0xFFDEEAE5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaseTableHeader extends StatelessWidget {
  const _CaseTableHeader();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F7F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _HeaderCell(l.caseDate)),
          Expanded(flex: 3, child: _HeaderCell(l.caseCase)),
          Expanded(flex: 2, child: _HeaderCell(l.caseConfidence)),
          Expanded(flex: 2, child: _HeaderCell(l.caseStatus)),
          Expanded(flex: 2, child: _HeaderCell(l.caseAction)),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
    );
  }
}

class _CaseTableRow extends StatelessWidget {
  final _CaseData data;
  const _CaseTableRow({required this.data});

  Color get _statusColor {
    switch (data.statusType) {
      case _CaseStatus.detected:
        return AppColors.error;
      case _CaseStatus.suspected:
        return Colors.orange;
      case _CaseStatus.clear:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final statusColor = _statusColor;

    String statusLabel;
    switch (data.statusType) {
      case _CaseStatus.detected:
        statusLabel = l.statusDetected;
      case _CaseStatus.suspected:
        statusLabel = l.statusSuspected;
      case _CaseStatus.clear:
        statusLabel = l.statusClear;
    }

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(data.date,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              data.caseName,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.confidence,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () {},
              child: Text(
                l.caseView,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Paywall Banner ────────────────────────────────────────────────────────────

class _PaywallBanner extends StatelessWidget {
  const _PaywallBanner();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.white, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.freeScansUsedUp,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  l.upgradeToContinue,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            onPressed: () => context.go('/subscription'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.smAll),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            child: Text(l.viewPlans),
          ),
        ],
      ),
    );
  }
}

// ── Find Vet Button ───────────────────────────────────────────────────────────

class _FindVetButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FindVetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.location_on_outlined, size: 20),
        label: Text(l.findVetNearby),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
