import 'package:flutter/material.dart';
import '../../data/models/research_paper.dart';
import '../research_theme.dart';

/// Shared building blocks for the researcher content-creation forms (papers,
/// disease updates, innovations) so each screen doesn't reinvent the same
/// section/field/submit-row chrome.

bool existingIsEditable(PaperStatus? status) =>
    status == null || status == PaperStatus.draft || status == PaperStatus.needsRevision;

String? Function(String?) requiredValidator(String label) =>
    (v) => v == null || v.trim().isEmpty ? '$label is required' : null;

class FormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const FormSection({super.key, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: const TextStyle(fontSize: 12, color: RColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class ResearchTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  const ResearchTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.validator,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, color: RColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: RColors.textSecondary, fontSize: 13),
        hintStyle: const TextStyle(color: RColors.grey, fontSize: 13),
        filled: true,
        fillColor: RColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RColors.secondary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RColors.needsRevision),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class ReviewNotesBanner extends StatelessWidget {
  final String note;
  const ReviewNotesBanner({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RColors.needsRevisionLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RColors.needsRevision.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.rate_review_outlined, color: RColors.needsRevision, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Revision Requested',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: RColors.needsRevision)),
                const SizedBox(height: 4),
                Text(note, style: const TextStyle(fontSize: 13, color: RColors.needsRevision)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SubmitRow extends StatelessWidget {
  final bool saving;
  final bool canSubmit;
  final VoidCallback onSaveDraft;
  final VoidCallback onSubmit;

  const SubmitRow({
    super.key,
    required this.saving,
    required this.canSubmit,
    required this.onSaveDraft,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final saveDraftBtn = OutlinedButton.icon(
      onPressed: saving ? null : onSaveDraft,
      icon: const Icon(Icons.save_outlined, size: 16),
      label: const Text('Save Draft'),
      style: OutlinedButton.styleFrom(
        foregroundColor: RColors.textSecondary,
        side: const BorderSide(color: RColors.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );

    final submitBtn = canSubmit
        ? ElevatedButton.icon(
            onPressed: saving ? null : onSubmit,
            icon: saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_outlined, size: 16),
            label: const Text('Submit for Review'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              saveDraftBtn,
              if (submitBtn != null) ...[const SizedBox(height: 10), submitBtn],
            ],
          );
        }
        return Row(
          children: [
            saveDraftBtn,
            if (submitBtn != null) ...[const SizedBox(width: 12), submitBtn],
          ],
        );
      },
    );
  }
}
