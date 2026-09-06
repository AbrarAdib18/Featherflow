import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:featherflow/core/theme/theme.dart';

import '../../data/community_api_service.dart';

const _maxLength = 2000;

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _api = CommunityApiService.instance;
  final _content = TextEditingController();
  final _title = TextEditingController();
  final _hashtag = TextEditingController();
  final _pollControllers = <TextEditingController>[TextEditingController(), TextEditingController()];

  String _type = 'text';
  String? _category;
  final _tags = <String>[];
  final _media = <Map<String, String>>[]; // {url, name, kind}
  bool _anonymous = false;
  bool _pollMulti = false;
  bool _uploading = false;
  bool _submitting = false;
  List<String> _categories = const [];

  @override
  void initState() {
    super.initState();
    _api.categories().then((rows) {
      if (mounted) setState(() => _categories = rows.map((r) => r['name'].toString()).toList());
    }).catchError((_) {});
    _content.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _content.dispose();
    _title.dispose();
    _hashtag.dispose();
    for (final c in _pollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _addTag() {
    final raw = _hashtag.text.trim().replaceAll('#', '').toLowerCase();
    if (raw.isEmpty) return;
    setState(() {
      if (!_tags.contains(raw)) _tags.add(raw);
      _hashtag.clear();
    });
  }

  Future<void> _pickMedia() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'pdf'],
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      for (final f in picked.files) {
        if (f.bytes == null) continue;
        final result = await _api.uploadMedia(f.bytes!, f.name);
        _media.add({
          'url': result['media_url']?.toString() ?? result['url']?.toString() ?? '',
          'name': f.name,
          'kind': result['kind']?.toString() ?? 'file',
        });
      }
    } on CommunityApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    final content = _content.text.trim();
    if (_type == 'question' && _title.text.trim().isEmpty) {
      _toast('Give your question a title.');
      return;
    }
    if (_type != 'poll' && content.isEmpty) {
      _toast('Write something to share.');
      return;
    }
    List<String>? pollOptions;
    if (_type == 'poll') {
      pollOptions = _pollControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
      if (pollOptions.length < 2) {
        _toast('A poll needs at least 2 options.');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await _api.createPost({
        'post_type': _type,
        'content': content,
        if (_type == 'question') 'title': _title.text.trim(),
        if (_category != null) 'category': _category,
        'tags': _tags,
        'media_urls': _media.map((m) => m['url']).toList(),
        'is_anonymous': _anonymous,
        if (pollOptions != null) 'poll_options': pollOptions,
        if (_type == 'poll') 'poll_multi': _pollMulti,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on CommunityApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _maxLength - _content.text.length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('New post'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton(
              onPressed: _submitting || _uploading ? null : _submit,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
              child: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'text', label: Text('Post'), icon: Icon(Icons.article_outlined, size: 16)),
              ButtonSegment(value: 'question', label: Text('Question'), icon: Icon(Icons.help_outline, size: 16)),
              ButtonSegment(value: 'poll', label: Text('Poll'), icon: Icon(Icons.bar_chart, size: 16)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_type == 'question')
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Question title *',
                  hintText: 'e.g. Why are my layers off feed this week?',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          TextField(
            controller: _content,
            maxLines: 6,
            maxLength: _maxLength,
            textCapitalization: TextCapitalization.sentences,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                Text('$remaining left', style: TextStyle(fontSize: 11, color: remaining < 0 ? AppColors.error : Colors.grey)),
            decoration: InputDecoration(
              labelText: _type == 'poll' ? 'Poll question / context' : 'Share a price, ask, or post an update',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_type == 'poll') ...[
            const Text('Options', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: AppSpacing.xs),
            for (var i = 0; i < _pollControllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _pollControllers[i],
                      decoration: InputDecoration(
                          isDense: true, border: const OutlineInputBorder(), hintText: 'Option ${i + 1}'),
                    ),
                  ),
                  if (_pollControllers.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: () => setState(() => _pollControllers.removeAt(i).dispose()),
                    ),
                ]),
              ),
            if (_pollControllers.length < 6)
              TextButton.icon(
                onPressed: () => setState(() => _pollControllers.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add option'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Allow multiple choices'),
              value: _pollMulti,
              onChanged: (v) => setState(() => _pollMulti = v),
            ),
            const Divider(),
          ],
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Topic', border: OutlineInputBorder(), isDense: true),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _hashtag,
            onSubmitted: (_) => _addTag(),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: InputDecoration(
              labelText: 'Add hashtag',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixText: '#',
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addTag),
            ),
          ),
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.xs,
                children: _tags
                    .map((t) => Chip(
                          label: Text('#$t'),
                          onDeleted: () => setState(() => _tags.remove(t)),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickMedia,
            icon: _uploading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file, size: 16),
            label: Text(_uploading ? 'Uploading…' : 'Add photos, video, or PDF'),
          ),
          if (_media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: _media
                    .map((m) => Chip(
                          avatar: Icon(
                            m['kind'] == 'image'
                                ? Icons.image
                                : m['kind'] == 'video'
                                    ? Icons.videocam
                                    : Icons.description,
                            size: 16,
                          ),
                          label: Text(m['name']!, overflow: TextOverflow.ellipsis),
                          onDeleted: () => setState(() => _media.remove(m)),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Post anonymously'),
            subtitle: const Text('Shown as "Anonymous Farmer". Moderators can still see it was you.',
                style: TextStyle(fontSize: 11)),
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
          ),
        ],
      ),
    );
  }
}
