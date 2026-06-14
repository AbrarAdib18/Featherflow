import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';

class NewPaperScreen extends StatefulWidget {
  final String? paperId;
  const NewPaperScreen({super.key, this.paperId});

  @override
  State<NewPaperScreen> createState() => _NewPaperScreenState();
}

class _NewPaperScreenState extends State<NewPaperScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _abstractCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _keywordsCtrl;
  late final TextEditingController _referencesCtrl;
  late ResearchField _field;
  late final List<ResearchAuthor> _authors;
  late final List<String> _tags;
  bool _saving = false;

  ResearchPaper? get _existingPaper =>
      widget.paperId != null
          ? ResearchSession.instance.findPaper(widget.paperId!)
          : null;

  bool get _isNew => _existingPaper == null;

  @override
  void initState() {
    super.initState();
    final p = _existingPaper;
    _titleCtrl = TextEditingController(text: p?.title ?? '');
    _abstractCtrl = TextEditingController(text: p?.abstract ?? '');
    _bodyCtrl = TextEditingController(text: p?.body ?? '');
    _keywordsCtrl =
        TextEditingController(text: p?.keywords.join(', ') ?? '');
    _referencesCtrl = TextEditingController(text: p?.references ?? '');
    _field = p?.field ?? ResearchField.disease;
    _authors = p != null
        ? List.from(p.authors)
        : [ResearchSession.instance.profile.let(_profileToAuthor)];
    _tags = p != null ? List.from(p.tags) : [];
  }

  ResearchAuthor _profileToAuthor(dynamic profile) => ResearchAuthor(
        id: 'r1',
        name: profile.name,
        institution: profile.institution,
        email: profile.email,
        isCorresponding: true,
      );

  @override
  void dispose() {
    _titleCtrl.dispose();
    _abstractCtrl.dispose();
    _bodyCtrl.dispose();
    _keywordsCtrl.dispose();
    _referencesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool submit}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final existing = _existingPaper;
    final now = DateTime.now();
    final keywords = _keywordsCtrl.text
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    final paper = ResearchPaper(
      id: existing?.id ?? 'p${DateTime.now().millisecondsSinceEpoch}',
      title: _titleCtrl.text.trim(),
      abstract: _abstractCtrl.text.trim(),
      body: _bodyCtrl.text.trim(),
      keywords: keywords,
      references: _referencesCtrl.text.trim(),
      authors: _authors,
      status: submit ? PaperStatus.underReview : PaperStatus.draft,
      field: _field,
      tags: _tags,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      views: existing?.views ?? 0,
      downloads: existing?.downloads ?? 0,
      bookmarks: existing?.bookmarks ?? 0,
      reviewComments: existing?.reviewComments ?? [],
      versions: submit
          ? [
              ...(existing?.versions ?? []),
              PaperVersion(
                versionNumber: (existing?.versions.length ?? 0) + 1,
                submittedAt: now,
                changeNotes: existing == null ? 'Initial submission' : 'Resubmission',
              ),
            ]
          : existing?.versions ?? [],
      journal: existing?.journal,
      doi: existing?.doi,
    );

    ResearchSession.instance.savePaper(paper);
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          submit
              ? 'Paper submitted for review.'
              : 'Draft saved.',
        ),
        backgroundColor:
            submit ? RColors.underReview : RColors.published,
      ),
    );
    context.go('/research/papers');
  }

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: _isNew ? 'Submit New Paper' : 'Edit Paper',
      module: ResearchModule.submit,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isNew &&
                  _existingPaper!.status == PaperStatus.needsRevision)
                _RevisionBanner(paper: _existingPaper!),
              _Section(
                title: 'Paper Details',
                child: Column(
                  children: [
                    _Field(
                      controller: _titleCtrl,
                      label: 'Title',
                      hint: 'Full title of your research paper',
                      maxLines: 2,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),
                    _FieldDropdown<ResearchField>(
                      label: 'Research Field',
                      value: _field,
                      items: ResearchField.values,
                      labelOf: (f) => f.label,
                      onChanged: (f) => setState(() => _field = f!),
                    ),
                    const SizedBox(height: 16),
                    _Field(
                      controller: _abstractCtrl,
                      label: 'Abstract',
                      hint: 'Concise summary (150–300 words recommended)',
                      maxLines: 5,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Abstract is required' : null,
                    ),
                    const SizedBox(height: 16),
                    _Field(
                      controller: _keywordsCtrl,
                      label: 'Keywords',
                      hint: 'Comma-separated (e.g. Newcastle disease, broiler, vaccination)',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Paper Body',
                child: _Field(
                  controller: _bodyCtrl,
                  label: 'Full Paper Content',
                  hint:
                      'Introduction, methods, results, discussion, conclusions...',
                  maxLines: 20,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Body is required' : null,
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Tags',
                subtitle: 'Select all applicable categories',
                child: _TagsSelector(
                  selected: _tags,
                  onChanged: (tags) => setState(() {
                    _tags
                      ..clear()
                      ..addAll(tags);
                  }),
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Authors',
                child: _AuthorsEditor(
                  authors: _authors,
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'References',
                child: _Field(
                  controller: _referencesCtrl,
                  label: 'References',
                  hint:
                      'Numbered references list (e.g. 1. Author et al. (2023) Title. Journal.)',
                  maxLines: 8,
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'PDF Upload',
                child: _PdfUploadPlaceholder(),
              ),
              const SizedBox(height: 28),
              _SubmitRow(
                saving: _saving,
                isNew: _isNew,
                onSaveDraft: () => _save(submit: false),
                onSubmit: () => _save(submit: true),
                canSubmit: _existingPaper == null ||
                    _existingPaper!.status == PaperStatus.draft ||
                    _existingPaper!.status == PaperStatus.needsRevision,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevisionBanner extends StatelessWidget {
  final ResearchPaper paper;
  const _RevisionBanner({required this.paper});

  @override
  Widget build(BuildContext context) {
    final unresolved =
        paper.reviewComments.where((c) => !c.resolved).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RColors.needsRevisionLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: RColors.needsRevision.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rate_review_outlined,
                  color: RColors.needsRevision, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Revision Required',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: RColors.needsRevision,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/research/review'),
                child: const Text('View Comments'),
              ),
            ],
          ),
          if (unresolved.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${unresolved.length} unresolved reviewer comment${unresolved.length > 1 ? 's' : ''}.',
              style: const TextStyle(
                  fontSize: 13, color: RColors.needsRevision),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(
                  fontSize: 12, color: RColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(
        fontSize: 13,
        color: RColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
            color: RColors.textSecondary, fontSize: 13),
        hintStyle:
            const TextStyle(color: RColors.grey, fontSize: 13),
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
          borderSide:
              const BorderSide(color: RColors.secondary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: RColors.needsRevision),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _FieldDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _FieldDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // ignore: deprecated_member_use
      value: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            color: RColors.textSecondary, fontSize: 13),
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
          borderSide:
              const BorderSide(color: RColors.secondary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
      ),
      style: const TextStyle(
        fontSize: 13,
        color: RColors.textPrimary,
      ),
      dropdownColor: Colors.white,
      items: items
          .map((i) => DropdownMenuItem(
                value: i,
                child: Text(labelOf(i)),
              ))
          .toList(),
    );
  }
}

const _allTags = [
  'Broilers', 'Layers', 'Ducks', 'Turkeys', 'Chicks', 'Breeders',
  'Respiratory Disease', 'Digestive Disease', 'Viral Disease', 'Bacterial Disease',
  'Parasitic Disease', 'Feed Management', 'Vaccination', 'Biosecurity',
  'Free-Range', 'Small Farms', 'Nutrition', 'Gut Health', 'Welfare',
  'Automation', 'Economics', 'Epidemiology',
];

class _TagsSelector extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _TagsSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allTags.map((tag) {
        final isSelected = selected.contains(tag);
        return FilterChip(
          label: Text(tag),
          selected: isSelected,
          onSelected: (v) {
            final updated = List<String>.from(selected);
            if (v) {
              updated.add(tag);
            } else {
              updated.remove(tag);
            }
            onChanged(updated);
          },
          selectedColor: RColors.secondary.withValues(alpha: 0.12),
          checkmarkColor: RColors.secondary,
          labelStyle: TextStyle(
            fontSize: 12,
            color: isSelected ? RColors.secondary : RColors.textSecondary,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
          side: BorderSide(
            color: isSelected
                ? RColors.secondary.withValues(alpha: 0.5)
                : RColors.cardBorder,
          ),
          backgroundColor: RColors.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }
}

class _AuthorsEditor extends StatelessWidget {
  final List<ResearchAuthor> authors;
  final VoidCallback onChanged;

  const _AuthorsEditor(
      {required this.authors, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...authors.asMap().entries.map((e) {
          final i = e.key;
          final a = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: const Border.fromBorderSide(
                  BorderSide(color: RColors.cardBorder)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      RColors.secondary.withValues(alpha: 0.15),
                  child: Text(
                    a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: RColors.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            a.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: RColors.textPrimary,
                            ),
                          ),
                          if (a.isCorresponding) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: RColors.secondary
                                    .withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Corresponding',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: RColors.secondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        a.institution,
                        style: const TextStyle(
                          fontSize: 11,
                          color: RColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!a.isCorresponding)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 18, color: RColors.needsRevision),
                    onPressed: () {
                      authors.removeAt(i);
                      onChanged();
                    },
                    tooltip: 'Remove author',
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => _showAddAuthorDialog(context),
          icon: const Icon(Icons.person_add_outlined, size: 16),
          label: const Text('Add Co-Author'),
          style: OutlinedButton.styleFrom(
            foregroundColor: RColors.secondary,
            side: const BorderSide(color: RColors.secondary),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }

  void _showAddAuthorDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final instCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Co-Author'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'Dr. Jane Smith',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: instCtrl,
              decoration: const InputDecoration(
                labelText: 'Institution',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                authors.add(ResearchAuthor(
                  id: 'coauth_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  institution: instCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                ));
                onChanged();
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: RColors.secondary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _PdfUploadPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF upload requires the file_picker package. Add it to pubspec.yaml to enable.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: RColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: RColors.cardBorder,
            style: BorderStyle.solid,
          ),
        ),
        child: const Column(
          children: [
            Icon(Icons.upload_file_outlined,
                size: 32, color: RColors.grey),
            SizedBox(height: 8),
            Text(
              'Tap to upload PDF',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: RColors.textSecondary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Max 25 MB · PDF only',
              style: TextStyle(fontSize: 11, color: RColors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitRow extends StatelessWidget {
  final bool saving;
  final bool isNew;
  final bool canSubmit;
  final VoidCallback onSaveDraft;
  final VoidCallback onSubmit;

  const _SubmitRow({
    required this.saving,
    required this.isNew,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );

    final submitBtn = canSubmit
        ? ElevatedButton.icon(
            onPressed: saving ? null : onSubmit,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_outlined, size: 16),
            label: const Text('Submit for Review'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
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
              if (submitBtn != null) ...[
                const SizedBox(height: 10),
                submitBtn,
              ],
            ],
          );
        }
        return Row(
          children: [
            saveDraftBtn,
            if (submitBtn != null) ...[
              const SizedBox(width: 12),
              submitBtn,
            ],
          ],
        );
      },
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
