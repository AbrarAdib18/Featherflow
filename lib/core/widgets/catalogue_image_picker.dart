import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'catalogue_image.dart';
import 'error_state.dart';

const _maxBytes = 5 * 1024 * 1024;
const _allowedExt = {'jpg', 'jpeg', 'png', 'webp'};

String? _validate(String name, Uint8List bytes) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (!_allowedExt.contains(ext)) return 'Choose a JPG, PNG or WebP image.';
  if (bytes.length > _maxBytes) {
    final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
    return 'That image is $mb MB. The limit is 5 MB.';
  }
  bool startsWith(List<int> sig) {
    if (bytes.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[i] != sig[i]) return false;
    }
    return true;
  }

  final okJpg = startsWith([0xFF, 0xD8, 0xFF]);
  final okPng = startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final okWebp = bytes.length >= 12 &&
      startsWith([0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
  if (!(okJpg || okPng || okWebp)) {
    return 'That file does not look like a valid image. Re-export it and try again.';
  }
  return null;
}

/// Generic rectangular image-upload control for catalogue/marketplace admin
/// screens (feed product photo, company logo/cover) — the same client-side
/// validation as [ProfilePhotoField] (extension + size + magic-byte sniff),
/// but a rectangle with a configurable aspect ratio instead of a circular
/// avatar, and the actual upload call is supplied by the caller since each
/// use targets a different multipart endpoint.
class CatalogueImagePicker extends StatefulWidget {
  const CatalogueImagePicker({
    super.key,
    required this.currentUrl,
    required this.onUpload,
    this.aspectRatio = 16 / 9,
    this.label = 'Add image',
    this.fallbackIcon = Icons.grass,
  });

  final String? currentUrl;
  final Future<String> Function(Uint8List bytes, String filename) onUpload;
  final double aspectRatio;
  final String label;
  final IconData fallbackIcon;

  @override
  State<CatalogueImagePicker> createState() => _CatalogueImagePickerState();
}

class _CatalogueImagePickerState extends State<CatalogueImagePicker> {
  Uint8List? _preview;
  bool _busy = false;
  String? _error;
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = widget.currentUrl;
  }

  @override
  void didUpdateWidget(covariant CatalogueImagePicker old) {
    super.didUpdateWidget(old);
    if (old.currentUrl != widget.currentUrl && _preview == null && !_busy) {
      _url = widget.currentUrl;
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
    } catch (_) {
      res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    }
    final file = res?.files.isNotEmpty == true ? res!.files.first : null;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    final invalid = _validate(file.name, bytes);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() {
      _preview = bytes;
      _busy = true;
      _error = null;
    });
    try {
      final newUrl = await widget.onUpload(bytes, file.name);
      if (!mounted) return;
      setState(() {
        _url = newUrl;
        _preview = null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _busy = false;
        _error = ErrorStateView.humanize(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _preview != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_preview!, fit: BoxFit.cover),
                    )
                  : CatalogueImage(url: _url, fallbackIcon: widget.fallbackIcon),
              if (_busy)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(color: Colors.white),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _busy ? null : _pick,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.camera_alt, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.upload_outlined, size: 16),
          label: Text(_busy ? 'Uploading…' : (_url == null || _url!.isEmpty ? widget.label : 'Replace image')),
          style: TextButton.styleFrom(minimumSize: const Size(0, 28)),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
          ),
      ],
    );
  }
}
