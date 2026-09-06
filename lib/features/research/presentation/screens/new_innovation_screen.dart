import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/innovation_post.dart';
import '../../data/models/research_paper.dart' show PaperStatus;
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/tag_picker.dart';
import 'shared_form_widgets.dart';

class NewInnovationScreen extends StatefulWidget {
  final String? innovationId;
  const NewInnovationScreen({super.key, this.innovationId});

  @override
  State<NewInnovationScreen> createState() => _NewInnovationScreenState();
}

class _NewInnovationScreenState extends State<NewInnovationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _sourceCtrl;
  late InnovationCategory _category;
  late final List<String> _mediaUrls;
  late final TextEditingController _mediaUrlCtrl;
  late List<String> _selectedTagIds;
  bool _saving = false;

  InnovationPost? get _existing =>
      widget.innovationId != null
          ? ResearchSession.instance.findInnovation(widget.innovationId!)
          : null;

  bool get _isNew => _existing == null;

  @override
  void initState() {
    super.initState();
    final p = _existing;
    _titleCtrl = TextEditingController(text: p?.title ?? '');
    _summaryCtrl = TextEditingController(text: p?.summary ?? '');
    _descriptionCtrl = TextEditingController(text: p?.details ?? '');
    _sourceCtrl = TextEditingController(text: p?.sourceDetails ?? '');
    _category = p?.category ?? InnovationCategory.automation;
    _mediaUrls = p != null ? List.from(p.mediaUrls) : [];
    _mediaUrlCtrl = TextEditingController();
    _selectedTagIds = p?.catalogTags.map((t) => t['id'].toString()).toList() ?? [];
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _descriptionCtrl.dispose();
    _sourceCtrl.dispose();
    _mediaUrlCtrl.dispose();
    super.dispose();
  }

  void _addMediaUrl() {
    final url = _mediaUrlCtrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Media URL must start with http:// or https://')),
      );
      return;
    }
    setState(() {
      _mediaUrls.add(url);
      _mediaUrlCtrl.clear();
    });
  }

  Future<void> _save({required bool submit}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final existing = _existing;
    final post = InnovationPost(
      id: existing?.id ?? '',
      title: _titleCtrl.text.trim(),
      summary: _summaryCtrl.text.trim(),
      details: _descriptionCtrl.text.trim(),
      sourceDetails: _sourceCtrl.text.trim(),
      category: _category,
      authorId: existing?.authorId ?? '',
      authorName: existing?.authorName ?? ResearchSession.instance.profile.name,
      publishedAt: existing?.publishedAt ?? DateTime.now(),
      status: existing?.status ?? PaperStatus.draft,
      views: existing?.views ?? 0,
      bookmarks: existing?.bookmarks ?? 0,
      version: existing?.version ?? 1,
      mediaUrls: _mediaUrls,
      catalogTags: _selectedTagIds.map((id) => {'id': id}).toList(),
    );
    try {
      await ResearchSession.instance.saveInnovation(post, submit: submit);
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
        content: Text(submit ? 'Submitted for review.' : 'Draft saved.'),
        backgroundColor: submit ? RColors.underReview : RColors.published,
      ),
    );
    context.go('/research/innovations');
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = existingIsEditable(_existing?.status);
    return ResearchScaffold(
      title: _isNew ? 'New Innovation Post' : 'Edit Innovation Post',
      module: ResearchModule.innovations,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isNew && _existing!.reviewNotes?.trim().isNotEmpty == true)
                ReviewNotesBanner(note: _existing!.reviewNotes!),
              FormSection(
                title: 'Innovation Details',
                child: Column(
                  children: [
                    ResearchTextField(
                      controller: _titleCtrl,
                      label: 'Title',
                      hint: 'e.g. Automated Feeding System',
                      validator: requiredValidator('Title'),
                    ),
                    const SizedBox(height: 16),
                    _CategoryDropdown(
                      value: _category,
                      onChanged: (c) => setState(() => _category = c!),
                    ),
                    const SizedBox(height: 16),
                    ResearchTextField(
                      controller: _summaryCtrl,
                      label: 'Summary',
                      hint: 'Short summary of the innovation',
                      maxLines: 3,
                      validator: requiredValidator('Summary'),
                    ),
                    const SizedBox(height: 16),
                    ResearchTextField(
                      controller: _descriptionCtrl,
                      label: 'Description',
                      hint: 'How it works, results, and expected impact',
                      maxLines: 8,
                      validator: requiredValidator('Description'),
                    ),
                    const SizedBox(height: 16),
                    ResearchTextField(
                      controller: _sourceCtrl,
                      label: 'Source Details',
                      hint: 'Where this innovation came from (trial, vendor, in-house)',
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FormSection(
                title: 'Media',
                subtitle: 'Optional image or video links',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ResearchTextField(
                            controller: _mediaUrlCtrl,
                            label: 'Media URL',
                            hint: 'https://...',
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(onPressed: _addMediaUrl, child: const Text('Add')),
                      ],
                    ),
                    if (_mediaUrls.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ..._mediaUrls.map((url) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: 14, color: RColors.textSecondary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(url,
                                      style: const TextStyle(fontSize: 12, color: RColors.textSecondary),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: RColors.needsRevision),
                                  onPressed: () => setState(() => _mediaUrls.remove(url)),
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FormSection(
                title: 'Tags',
                subtitle: 'Select up to $kMaxResearchTags catalog tags',
                child: TagPicker(
                  initialTags: _existing?.catalogTags ?? const [],
                  onChanged: (ids) => _selectedTagIds = ids,
                ),
              ),
              const SizedBox(height: 28),
              SubmitRow(
                saving: _saving,
                canSubmit: canEdit,
                onSaveDraft: () => _save(submit: false),
                onSubmit: () => _save(submit: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final InnovationCategory value;
  final ValueChanged<InnovationCategory?> onChanged;
  const _CategoryDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<InnovationCategory>(
      // ignore: deprecated_member_use
      value: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Category',
        labelStyle: const TextStyle(color: RColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: RColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RColors.cardBorder),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      style: const TextStyle(fontSize: 13, color: RColors.textPrimary),
      dropdownColor: Colors.white,
      items: InnovationCategory.values
          .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
          .toList(),
    );
  }
}
