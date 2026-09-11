import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../network/auth_service.dart';
import '../network/authed_image.dart';
import '../theme/theme.dart';
import 'error_state.dart';

const _maxBytes = 5 * 1024 * 1024;
const _allowedExt = {'jpg', 'jpeg', 'png', 'webp'};

/// Result of client-side validation.
String? _validate(String name, Uint8List bytes) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (!_allowedExt.contains(ext)) {
    return 'Choose a JPG, PNG or WebP image.';
  }
  if (bytes.length > _maxBytes) {
    final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
    return 'That image is $mb MB. The limit is 5 MB.';
  }
  // Magic bytes — the real type check.
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
      startsWith([0x52, 0x49, 0x46, 0x46]) && // RIFF
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50; // WEBP
  if (!(okJpg || okPng || okWebp)) {
    return 'That file does not look like a valid image. Re-export it and try again.';
  }
  return null;
}

/// Reusable "change profile picture" avatar used on every role's profile
/// screen. Tap → pick → validate → local preview → secure multipart upload →
/// the stored session photo URL is updated (so avatars elsewhere refresh) and
/// [onChanged] fires with the new URL. On any failure the old photo is kept.
class ProfilePhotoField extends StatefulWidget {
  const ProfilePhotoField({
    super.key,
    required this.currentUrl,
    this.onChanged,
    this.radius = 42,
    this.fallbackInitial = 'U',
    this.editable = true,
    this.onLightSurface = false,
    this.showLabel = true,
  });

  final String currentUrl;
  final ValueChanged<String>? onChanged;
  final double radius;
  final String fallbackInitial;
  final bool editable;

  /// Set on a white/light card so the label + initials use dark text instead
  /// of the white text used on the green profile headers.
  final bool onLightSurface;

  /// Hide the "Change profile photo" text button — just the avatar + camera
  /// badge. For tight spots like an app-bar leading slot.
  final bool showLabel;

  @override
  State<ProfilePhotoField> createState() => _ProfilePhotoFieldState();
}

class _ProfilePhotoFieldState extends State<ProfilePhotoField> {
  Uint8List? _preview;
  bool _busy = false;
  String? _error;
  late String _url = widget.currentUrl;

  @override
  void didUpdateWidget(covariant ProfilePhotoField old) {
    super.didUpdateWidget(old);
    if (old.currentUrl != widget.currentUrl && _preview == null && !_busy) {
      _url = widget.currentUrl;
    }
  }

  Future<void> _pickAndUpload() async {
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
      if (mounted) setState(() => _error = invalid);
      return;
    }

    setState(() {
      _preview = bytes;
      _busy = true;
      _error = null;
    });

    final previousUrl = _url;
    try {
      final newUrl = await AuthService.instance
          .updateProfilePhoto(bytes: bytes, filename: file.name);
      if (previousUrl.isNotEmpty) {
        PaintingBinding.instance.imageCache
            .evict(AuthedNetworkImage(previousUrl));
      }
      PaintingBinding.instance.imageCache.evict(AuthedNetworkImage(newUrl));
      if (!mounted) return;
      setState(() {
        _url = newUrl;
        _preview = null;
        _busy = false;
      });
      widget.onChanged?.call(newUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null; // keep showing the old photo
        _busy = false;
        _error = ErrorStateView.humanize(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (_preview != null) {
      image = MemoryImage(_preview!);
    } else if (_url.isNotEmpty) {
      image = AuthedNetworkImage(_url);
    }
    final fg = widget.onLightSurface ? AppColors.primary : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              radius: widget.radius,
              backgroundColor: AppColors.secondaryContainer,
              backgroundImage: image,
              onBackgroundImageError: image == null ? null : (_, __) {},
              child: image == null
                  ? Text(
                      widget.fallbackInitial,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.radius * 0.7,
                          fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            if (_busy)
              SizedBox(
                width: widget.radius * 2,
                height: widget.radius * 2,
                child: const CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              ),
            if (widget.editable && !_busy)
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: AppColors.secondary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _pickAndUpload,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (widget.editable && widget.showLabel) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : _pickAndUpload,
            style: TextButton.styleFrom(
                foregroundColor: fg,
                textStyle: const TextStyle(fontSize: 12),
                minimumSize: const Size(0, 28)),
            child: Text(_busy
                ? 'Uploading…'
                : (_url.isEmpty ? 'Add profile photo' : 'Change profile photo')),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: widget.onLightSurface
                    ? AppColors.error
                    : const Color(0xFFFFD5D5),
                fontSize: 11),
          ),
          TextButton(
            onPressed: _busy ? null : _pickAndUpload,
            style: TextButton.styleFrom(
                foregroundColor: fg,
                minimumSize: const Size(0, 24),
                textStyle: const TextStyle(fontSize: 11)),
            child: const Text('Try again'),
          ),
        ],
      ],
    );
  }
}
