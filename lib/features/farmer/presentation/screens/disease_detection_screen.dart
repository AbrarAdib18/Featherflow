import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/app_localizations.dart';
import '../../data/disease_detection_service.dart';

class DiseaseDetectionScreen extends StatefulWidget {
  const DiseaseDetectionScreen({super.key});

  @override
  State<DiseaseDetectionScreen> createState() => _DiseaseDetectionScreenState();
}

class _DiseaseDetectionScreenState extends State<DiseaseDetectionScreen> {
  PlatformFile? _picked;
  bool _analyzing = false;
  DiseaseResult? _result;
  String? _error;

  List<DiseaseResult> _recent = const [];
  bool _loadingRecent = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final rows = await DiseaseDetectionService.recentScans(limit: 8);
      if (mounted) setState(() => _recent = rows);
    } catch (_) {
      // recent cases are non-critical — leave the empty state
    } finally {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() {
      _picked = file;
      _result = null;
      _error = null;
    });
  }

  void _clearImage() => setState(() {
        _picked = null;
        _result = null;
        _error = null;
      });

  Future<void> _analyze() async {
    final file = _picked;
    if (file == null || file.bytes == null) return;
    setState(() {
      _analyzing = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await DiseaseDetectionService.analyze(
          file.bytes!, file.name.isEmpty ? 'scan.jpg' : file.name);
      if (!mounted) return;
      setState(() => _result = result);
      _loadRecent();
    } on DiseaseDetectionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _bookVet(DiseaseResult r) {
    final q = Uri(queryParameters: {
      if (!r.isHealthy && !r.uncertain) 'disease': r.disease,
      'urgency': r.urgency,
    }).query;
    context.push('/farmer/vet-map${q.isEmpty ? '' : '?$q'}');
  }

  void _openAssistant(DiseaseResult r) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AssistantSheet(result: r),
    );
  }

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
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/farmer'),
        ),
        title: Text(
          l.diseaseDetection,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
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
            const _DisclaimerBanner(),
            const SizedBox(height: AppSpacing.md),
            _UploadSection(
                picked: _picked, onPick: _pickImage, onClear: _clearImage),
            const SizedBox(height: AppSpacing.md),
            if (_picked != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _analyzing ? null : _analyze,
                  icon: _analyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.biotech_outlined, size: 18),
                  label: Text(_analyzing ? l.analyzingImage : l.analyzeImage),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.mdAll),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_error != null) ...[
              _ErrorCard(message: _error!, onRetry: _analyze),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_result != null) ...[
              _ResultCard(
                result: _result!,
                onAskAssistant: () => _openAssistant(_result!),
                onBookVet: () => _bookVet(_result!),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _RecentCasesSection(
              loading: _loadingRecent,
              cases: _recent,
              onTap: (r) => _openAssistant(r),
            ),
            const SizedBox(height: AppSpacing.md),
            const _PaywallBanner(),
            const SizedBox(height: AppSpacing.md),
            _FindVetButton(onTap: () => context.push('/farmer/vet-map')),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ── Severity helpers ─────────────────────────────────────────────────────────

Color _severityColor(String? severity) {
  switch (severity) {
    case 'critical':
      return const Color(0xFFB71C1C);
    case 'high':
      return AppColors.error;
    case 'medium':
      return const Color(0xFFF57C00);
    case 'low':
      return const Color(0xFF2E7D32);
    default:
      return AppColors.secondary;
  }
}

String _severityLabel(String? severity) {
  switch (severity) {
    case 'critical':
      return 'Critical';
    case 'high':
      return 'High';
    case 'medium':
      return 'Moderate';
    case 'low':
      return 'Mild';
    default:
      return 'Healthy';
  }
}

// ── Disclaimer ───────────────────────────────────────────────────────────────

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: const Color(0xFFFFB300)),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF57F17), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.aiEstimateOnly,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6D4C00)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Upload Section ───────────────────────────────────────────────────────────

class _UploadSection extends StatelessWidget {
  final PlatformFile? picked;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _UploadSection(
      {required this.picked, required this.onPick, required this.onClear});

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
        if (picked != null && picked!.bytes != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.lgAll,
                child: Image.memory(picked!.bytes!,
                    width: double.infinity, height: 220, fit: BoxFit.cover),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(picked!.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ),
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(l.removeImage),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.error),
                  ),
                ],
              ),
            ],
          )
        else
          GestureDetector(
            onTap: onPick,
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
                          onPressed: onPick,
                          icon: const Icon(Icons.camera_alt_outlined,
                              color: AppColors.primary, size: 28),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        IconButton(
                          onPressed: onPick,
                          icon: const Icon(Icons.photo_library_outlined,
                              color: AppColors.primary, size: 28),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(l.dropChickenImage,
                        style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: onPick,
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
              child: Text(l.clearImagesHint,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500)),
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
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(AppRadius.lg)));
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
            metric.extractPath(distance, distance + dashWidth), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Error card ───────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.analysisFailed,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.error)),
                Text(message,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l.retry)),
        ],
      ),
    );
  }
}

// ── Result card ──────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final DiseaseResult result;
  final VoidCallback onAskAssistant;
  final VoidCallback onBookVet;

  const _ResultCard({
    required this.result,
    required this.onAskAssistant,
    required this.onBookVet,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = result.isHealthy
        ? const Color(0xFF2E7D32)
        : _severityColor(result.severity);
    final title = result.uncertain
        ? 'Needs a closer look'
        : (result.isHealthy ? l.healthyResult : result.disease);

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
              offset: const Offset(0, 2)),
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
                    Text(l.detectionResult,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(title,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: color)),
                  ],
                ),
              ),
              if (!result.isHealthy)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: color),
                  ),
                  child: Text(_severityLabel(result.severity),
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          if (result.requiresImmediateVet || result.notifiable) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (result.requiresImmediateVet)
                _tag('See a vet urgently', const Color(0xFFB71C1C)),
              if (result.notifiable)
                _tag('Reportable disease', const Color(0xFF6A1B9A)),
            ]),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Text(l.confidence,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
            Text('${(result.confidence * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ClipRRect(
                borderRadius: AppRadius.smAll,
                child: LinearProgressIndicator(
                  value: result.confidence.clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFFE0E8E4),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
            ),
          ]),
          if (result.uncertain) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(l.lowConfidenceNote,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFF57C00),
                    fontWeight: FontWeight.w500)),
          ],
          if (result.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(result.description,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
          if (result.symptoms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _BulletList(
                title: l.symptomsToWatch,
                titleColor: Colors.black87,
                icon: Icons.remove_red_eye_outlined,
                iconColor: Colors.black54,
                items: result.symptoms),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Color(0xFFE0E8E4)),
          const SizedBox(height: AppSpacing.sm),
          _BulletList(
              title: l.whatToDo,
              titleColor: AppColors.secondary,
              icon: Icons.check_circle_outline,
              iconColor: AppColors.secondary,
              items: result.recommendations),
          if (result.avoid.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _BulletList(
                title: l.doNotDo,
                titleColor: AppColors.error,
                icon: Icons.cancel_outlined,
                iconColor: AppColors.error,
                items: result.avoid),
          ],
          if (result.allPredictions.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            _OtherPredictions(predictions: result.allPredictions),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAskAssistant,
                  icon: const Icon(Icons.smart_toy_outlined, size: 16),
                  label: Text(l.askChatbot),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.smAll),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onBookVet,
                  icon: const Icon(Icons.medical_services_outlined, size: 16),
                  label: Text(l.bookVet),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.smAll),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: AppRadius.fullAll,
            border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}

class _OtherPredictions extends StatelessWidget {
  final List<DiseasePrediction> predictions;
  const _OtherPredictions({required this.predictions});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(l.otherPossibilities,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54)),
      children: [
        for (final p in predictions.skip(1))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                  child: Text(p.disease,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black87))),
              Text('${(p.confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black45)),
            ]),
          ),
      ],
    );
  }
}

class _BulletList extends StatelessWidget {
  final String title;
  final Color titleColor;
  final IconData icon;
  final Color iconColor;
  final List<String> items;

  const _BulletList({
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
        Text(title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: titleColor)),
        const SizedBox(height: AppSpacing.xs),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15, color: iconColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87)),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

// ── Assistant sheet (disease info) ───────────────────────────────────────────

class _AssistantSheet extends StatelessWidget {
  final DiseaseResult result;
  const _AssistantSheet({required this.result});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = result.isHealthy
        ? const Color(0xFF2E7D32)
        : _severityColor(result.severity);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Row(children: [
            Icon(Icons.smart_toy_outlined, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.uncertain
                    ? 'Needs a closer look'
                    : (result.isHealthy ? l.healthyResult : result.disease),
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color),
              ),
            ),
          ]),
          if (!result.isHealthy && !result.uncertain)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_severityLabel(result.severity)} severity • '
                '${(result.confidence * 100).toStringAsFixed(0)}% confidence',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 12),
          if (result.description.isNotEmpty)
            Text(result.description,
                style: const TextStyle(fontSize: 14, color: Colors.black87)),
          if (result.symptoms.isNotEmpty) ...[
            const SizedBox(height: 16),
            _BulletList(
                title: l.symptomsToWatch,
                titleColor: Colors.black87,
                icon: Icons.remove_red_eye_outlined,
                iconColor: Colors.black54,
                items: result.symptoms),
          ],
          const SizedBox(height: 16),
          _BulletList(
              title: l.whatToDo,
              titleColor: AppColors.secondary,
              icon: Icons.check_circle_outline,
              iconColor: AppColors.secondary,
              items: result.recommendations),
          if (result.avoid.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BulletList(
                title: l.doNotDo,
                titleColor: AppColors.error,
                icon: Icons.cancel_outlined,
                iconColor: AppColors.error,
                items: result.avoid),
          ],
          if (result.prevention.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BulletList(
                title: 'Prevention',
                titleColor: AppColors.primary,
                icon: Icons.shield_outlined,
                iconColor: AppColors.primary,
                items: result.prevention),
          ],
          const SizedBox(height: 16),
          Text(result.disclaimer.isEmpty ? l.aiEstimateOnly : result.disclaimer,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black45,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

// ── Recent cases ─────────────────────────────────────────────────────────────

class _RecentCasesSection extends StatelessWidget {
  final bool loading;
  final List<DiseaseResult> cases;
  final void Function(DiseaseResult) onTap;

  const _RecentCasesSection({
    required this.loading,
    required this.cases,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.recentCases,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87)),
        const SizedBox(height: AppSpacing.md),
        Material(
          type: MaterialType.card,
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.lgAll,
            side: BorderSide(color: Color(0xFFDEEAE5)),
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()))
              : cases.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 32, horizontal: 16),
                      child: Column(children: [
                        Icon(Icons.history_toggle_off,
                            size: 32,
                            color: Colors.black.withValues(alpha: 0.3)),
                        const SizedBox(height: AppSpacing.sm),
                        Text(l.noPreviousScans,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500)),
                      ]),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < cases.length; i++) ...[
                          _RecentRow(result: cases[i], onTap: () => onTap(cases[i])),
                          if (i < cases.length - 1)
                            const Divider(height: 1, color: Color(0xFFDEEAE5)),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  final DiseaseResult result;
  final VoidCallback onTap;
  const _RecentRow({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = result.isHealthy
        ? const Color(0xFF2E7D32)
        : _severityColor(result.severity);
    final date = (result.createdAt ?? '').split('T').first;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
            result.isHealthy
                ? Icons.check
                : (result.uncertain
                    ? Icons.help_outline
                    : Icons.coronavirus_outlined),
            size: 16,
            color: color),
      ),
      title: Text(
          result.uncertain
              ? 'Uncertain'
              : (result.isHealthy ? 'Healthy' : result.disease),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(
          '$date • ${(result.confidence * 100).toStringAsFixed(0)}% confidence',
          style: const TextStyle(fontSize: 11)),
      trailing: Text(_severityLabel(result.severity),
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Paywall banner ───────────────────────────────────────────────────────────

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
          const Icon(Icons.workspace_premium_outlined,
              color: Colors.white, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.freeScansUsedUp,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text(l.upgradeToContinue,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            onPressed: () => context.push('/subscription'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              shape:
                  const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
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

// ── Find Vet Button ──────────────────────────────────────────────────────────

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
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
