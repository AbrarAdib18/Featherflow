import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/disease_update.dart';
import '../../data/models/research_paper.dart' show PaperStatus;
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/tag_picker.dart';
import 'shared_form_widgets.dart';

class NewDiseaseUpdateScreen extends StatefulWidget {
  final String? updateId;
  const NewDiseaseUpdateScreen({super.key, this.updateId});

  @override
  State<NewDiseaseUpdateScreen> createState() => _NewDiseaseUpdateScreenState();
}

class _NewDiseaseUpdateScreenState extends State<NewDiseaseUpdateScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _symptomsCtrl;
  late final TextEditingController _treatmentCtrl;
  late final TextEditingController _preventionCtrl;
  late final TextEditingController _summaryCtrl;
  late List<String> _selectedTagIds;
  bool _saving = false;

  DiseaseUpdate? get _existing =>
      widget.updateId != null ? ResearchSession.instance.findDiseaseUpdate(widget.updateId!) : null;

  bool get _isNew => _existing == null;

  @override
  void initState() {
    super.initState();
    final u = _existing;
    _nameCtrl = TextEditingController(text: u?.diseaseName ?? '');
    _symptomsCtrl = TextEditingController(text: u?.symptoms ?? '');
    _treatmentCtrl = TextEditingController(text: u?.treatments ?? '');
    _preventionCtrl = TextEditingController(text: u?.preventionMethods ?? '');
    _summaryCtrl = TextEditingController(text: u?.farmerSummary ?? '');
    _selectedTagIds = u?.catalogTags.map((t) => t['id'].toString()).toList() ?? [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symptomsCtrl.dispose();
    _treatmentCtrl.dispose();
    _preventionCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool submit}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final existing = _existing;
    final update = DiseaseUpdate(
      id: existing?.id ?? '',
      diseaseName: _nameCtrl.text.trim(),
      causativeAgent: existing?.causativeAgent ?? '',
      symptoms: _symptomsCtrl.text.trim(),
      treatments: _treatmentCtrl.text.trim(),
      preventionMethods: _preventionCtrl.text.trim(),
      farmerSummary: _summaryCtrl.text.trim(),
      authorId: existing?.authorId ?? '',
      authorName: existing?.authorName ?? ResearchSession.instance.profile.name,
      publishedAt: existing?.publishedAt ?? DateTime.now(),
      severity: existing?.severity ?? DiseaseSeverity.medium,
      status: existing?.status ?? PaperStatus.draft,
      views: existing?.views ?? 0,
      bookmarks: existing?.bookmarks ?? 0,
      version: existing?.version ?? 1,
      catalogTags: _selectedTagIds.map((id) => {'id': id}).toList(),
    );
    try {
      await ResearchSession.instance.saveDiseaseUpdate(update, submit: submit);
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
    context.go('/research/diseases');
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = existingIsEditable(_existing?.status);
    return ResearchScaffold(
      title: _isNew ? 'New Disease/Cure Update' : 'Edit Disease/Cure Update',
      module: ResearchModule.diseases,
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
                title: 'Disease Details',
                child: Column(
                  children: [
                    ResearchTextField(
                      controller: _nameCtrl,
                      label: 'Disease Name',
                      hint: 'e.g. Newcastle Disease',
                      validator: requiredValidator('Disease name'),
                    ),
                    const SizedBox(height: 16),
                    ResearchTextField(
                      controller: _symptomsCtrl,
                      label: 'Symptoms',
                      hint: 'Observable clinical signs',
                      maxLines: 4,
                      validator: requiredValidator('Symptoms'),
                    ),
                    const SizedBox(height: 16),
                    ResearchTextField(
                      controller: _treatmentCtrl,
                      label: 'Treatment',
                      hint: 'Recommended treatment protocol',
                      maxLines: 4,
                      validator: requiredValidator('Treatment'),
                    ),
                    const SizedBox(height: 16),
                    ResearchTextField(
                      controller: _preventionCtrl,
                      label: 'Prevention',
                      hint: 'Prevention and biosecurity measures',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FormSection(
                title: 'Farmer-Friendly Summary',
                subtitle: 'Plain-language guidance shown in the public portal',
                child: ResearchTextField(
                  controller: _summaryCtrl,
                  label: 'Practical Summary',
                  hint: 'What should a farmer do right now?',
                  maxLines: 3,
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
