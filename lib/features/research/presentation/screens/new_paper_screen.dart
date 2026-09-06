import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_api_service.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/tag_picker.dart';

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
  late List<String> _selectedTagIds;
  late String? _pdfUrl;
  bool _saving = false;
  bool _uploadingPdf = false;

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
    _selectedTagIds = p?.catalogTags.map((t) => t['id'].toString()).toList() ?? [];
    _pdfUrl = p?.pdfUrl;
  }

  Future<void> _pickAndUploadPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'], withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.bytes == null) return;
    if (picked.size > 25 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF must be 25 MB or smaller.')),
      );
      return;
    }
    setState(() => _uploadingPdf = true);
    try {
      final url = await ResearchApiService.instance.uploadPdf(picked.bytes!, picked.name);
      if (!mounted) return;
      setState(() {
        _pdfUrl = url;
        _uploadingPdf = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingPdf = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: RColors.needsRevision),
      );
    }
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
      catalogTags: _selectedTagIds.map((id) => {'id': id}).toList(),
      pdfUrl: _pdfUrl,
    );

    try {
      await ResearchSession.instance.savePaper(paper);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: RColors.needsRevision),
      );
      return;
    }

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
                subtitle: 'Select up to $kMaxResearchTags catalog tags used for search and filtering',
                child: TagPicker(
                  initialTags: _existingPaper?.catalogTags ?? const [],
                  onChanged: (ids) => _selectedTagIds = ids,
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Free-text Labels',
                subtitle: 'Additional descriptive labels (not used for filtering)',
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
                child: _PdfUploadField(
                  pdfUrl: _pdfUrl,
                  uploading: _uploadingPdf,
                  onTap: _pickAndUploadPdf,
                  onRemove: () => setState(() => _pdfUrl = null),
                ),
              ),
              if (!_isNew) ...[
                const SizedBox(height: 20),
                _Section(
                  title: 'Version History',
                  subtitle: 'Snapshots taken on submission and publication',
                  child: _VersionHistorySection(paperId: widget.paperId!),
                ),
              ],
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

class _VersionHistorySection extends StatefulWidget {
  final String paperId;
  const _VersionHistorySection({required this.paperId});

  @override
  State<_VersionHistorySection> createState() => _VersionHistorySectionState();
}

class _VersionHistorySectionState extends State<_VersionHistorySection> {
  List<Map<String, dynamic>>? _versions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final versions = await ResearchSession.instance.paperVersions(widget.paperId);
      if (!mounted) return;
      setState(() => _versions = versions);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: RColors.needsRevision, fontSize: 12));
    }
    if (_versions == null) {
      return const SizedBox(
          height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_versions!.isEmpty) {
      return const Text('No submissions yet.',
          style: TextStyle(fontSize: 12, color: RColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _versions!.reversed.map((v) {
        final changedAt = DateTime.tryParse(v['changed_at']?.toString() ?? '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: RColors.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text('v${v['version']}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: RColors.secondary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v['change_note']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: RColors.textPrimary)),
                    Text(
                      [
                        if (v['changed_by'] != null) v['changed_by'].toString(),
                        if (changedAt != null) changedAt.toString().split('.').first,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: RColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PdfUploadField extends StatelessWidget {
  final String? pdfUrl;
  final bool uploading;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PdfUploadField({
    required this.pdfUrl,
    required this.uploading,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: RColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: RColors.cardBorder),
        ),
        child: const Column(
          children: [
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: RColors.secondary),
            ),
            SizedBox(height: 10),
            Text('Uploading…',
                style: TextStyle(fontSize: 13, color: RColors.textSecondary)),
          ],
        ),
      );
    }

    if (pdfUrl != null) {
      final filename = Uri.tryParse(pdfUrl!)?.pathSegments.last ?? pdfUrl!;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: RColors.secondary.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf_outlined, color: RColors.secondary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(filename,
                  style: const TextStyle(fontSize: 13, color: RColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            TextButton(onPressed: onTap, child: const Text('Replace')),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: RColors.needsRevision),
              onPressed: onRemove,
              tooltip: 'Remove PDF',
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
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
