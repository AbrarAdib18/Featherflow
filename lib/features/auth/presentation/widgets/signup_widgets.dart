import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../data/password_policy.dart';
import '../../data/signup_form_cache.dart';

const _kAccent = Color(0xFF1DB584);
const _kInk = Color(0xFF01291E);
const _kError = Color(0xFFFF5C6A);
const _kAllowedExt = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
const _kMaxBytes = 5 * 1024 * 1024;

/// Route to the right screen after a registration (or verify-confirm) result:
/// email/phone OTP, the pending-approval screen, or the role dashboard.
Future<void> routeAfterRegistration(
    BuildContext context, RegistrationResult result) async {
  // The forms have been accepted by the server — drop the in-memory drafts so a
  // later signup starts clean (and no plaintext password lingers in memory).
  SignupFormCache.instance.clearAll();
  if (result.verificationRequired) {
    context.go(AppRoutes.verifyContact, extra: {
      'email': result.email,
      'channel': result.channel,
      'message': result.message,
      'debug_code': result.debugCode,
      'dev_delivery': result.devDelivery,
    });
    return;
  }
  if (result.session != null) {
    final roles = result.session!.user.roles;
    final dest = await AuthService.instance
        .getRoleDestination(roles.isNotEmpty ? roles.first : 'farmer');
    if (context.mounted) context.go(dest);
    return;
  }
  context.go(AppRoutes.registrationPending, extra: result.message);
}

/// Full-width submit button that shows a spinner and blocks re-entry while
/// [submitting] is true.
class SignupSubmitButton extends StatelessWidget {
  const SignupSubmitButton({
    super.key,
    required this.label,
    required this.submitting,
    required this.onPressed,
  });

  final String label;
  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: submitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _kAccent.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ),
    );
  }
}

/// A document/photo picker wired to `POST /api/auth/registration-upload/`.
/// Validates type + size locally, uploads immediately, shows the filename,
/// and lets the user replace or remove the file. Calls [onUploaded] with the
/// stored URL (or `null` when cleared).
class SignupUploadField extends StatefulWidget {
  const SignupUploadField({
    super.key,
    required this.label,
    required this.kind,
    required this.onUploaded,
    this.imageOnly = false,
    this.required = false,
    this.initialUrl,
  });

  final String label;
  final String kind;
  final bool imageOnly;
  final bool required;

  /// A previously-uploaded URL (e.g. restored from [SignupFormCache]) so the
  /// field shows as already filled when the user returns to the form.
  final String? initialUrl;
  final ValueChanged<String?> onUploaded;

  @override
  State<SignupUploadField> createState() => _SignupUploadFieldState();
}

class _SignupUploadFieldState extends State<SignupUploadField> {
  String? _filename;
  String? _url;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _url = widget.initialUrl;
      _filename = 'Attached file';
    }
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    final exts = widget.imageOnly ? ['jpg', 'jpeg', 'png', 'webp'] : _kAllowedExt;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: exts,
        withData: true,
      );
    } catch (e) {
      setState(() => _error = 'Could not open the file picker.');
      return;
    }
    if (result == null || result.files.isEmpty) return; // user cancelled
    final file = result.files.first;
    final bytes = file.bytes;
    final ext = (file.extension ?? '').toLowerCase();
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }
    if (!exts.contains(ext)) {
      setState(() => _error = 'Allowed: ${exts.join(', ').toUpperCase()}.');
      return;
    }
    if (bytes.length > _kMaxBytes) {
      setState(() => _error = 'File must be 5 MB or smaller.');
      return;
    }
    setState(() {
      _busy = true;
      _filename = file.name;
    });
    try {
      final url = await AuthService.instance.uploadRegistrationDoc(
        bytes: bytes, filename: file.name, kind: widget.kind);
      if (!mounted) return;
      setState(() => _url = url);
      widget.onUploaded(url);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _filename = null;
      });
      widget.onUploaded(null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Upload failed. Check your connection and try again.';
        _filename = null;
      });
      widget.onUploaded(null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    setState(() {
      _filename = null;
      _url = null;
      _error = null;
    });
    widget.onUploaded(null);
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _url != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _busy ? null : _pick,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _error != null
                    ? _kError
                    : (hasFile ? _kAccent : Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                if (_busy)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(hasFile ? Icons.check_circle : Icons.upload_file_outlined,
                      color: hasFile ? _kAccent : Colors.grey.shade400, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _filename ?? widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasFile ? _kInk : Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (hasFile) ...[
                  TextButton(
                    onPressed: _busy ? null : _pick,
                    child: const Text('Replace'),
                  ),
                  IconButton(
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove',
                  ),
                ] else
                  Icon(Icons.add_circle_outline, color: Colors.grey.shade400, size: 18),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(_error!,
                style: const TextStyle(color: _kError, fontSize: 12)),
          ),
      ],
    );
  }
}

/// Shown after a professional/staff signup that needs admin approval.
class RegistrationPendingScreen extends StatelessWidget {
  const RegistrationPendingScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      color: _kAccent, size: 46),
                ),
                const SizedBox(height: 24),
                const Text('Application submitted',
                    style: TextStyle(
                        color: _kInk, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => context.go(AppRoutes.login),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Back to sign in',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A confirm dialog for stepping back out of a partly-filled form. Returns true
/// to leave. Leaving does **not** discard anything — the entered data stays in
/// [SignupFormCache] and repopulates the step when the user comes back; it is
/// only cleared when signup completes (or the app restarts).
Future<bool> confirmLeaveSignupStep(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Leave this step?'),
      content: const Text(
          'Your answers on this step are saved on this device and will be here '
          'when you come back. Nothing is submitted until you finish signing up.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Go back')),
      ],
    ),
  );
  return leave ?? false;
}

/// Back-compat alias — older call sites used this name.
Future<bool> confirmDiscardSignup(BuildContext context) =>
    confirmLeaveSignupStep(context);

/// Shared back-navigation handler for every signup screen.
///
/// Empty form → navigate straight to [destination]. Form with data → confirm,
/// then navigate. Either way the draft for [cacheKey] is **kept** so returning
/// to this step restores it (Issue: "last page data lost on back navigation").
Future<void> handleSignupLeave(
  BuildContext context, {
  required bool hasData,
  required String cacheKey,
  required String destination,
}) async {
  if (!hasData) {
    context.go(destination);
    return;
  }
  final leave = await confirmLeaveSignupStep(context);
  if (!leave || !context.mounted) return;
  context.go(destination);
}

/// Binds a signup screen's fields to [SignupFormCache] so a half-filled form
/// survives navigating away and back (every screen is rebuilt fresh by
/// `context.go`, so its `State` is otherwise lost).
///
/// [fields] maps a cache key → text controller. [readExtra] contributes the
/// non-text state (dropdown values, picked dates as ISO strings, consent bools,
/// uploaded URLs); [writeExtra] applies a restored map back onto that state and
/// is called from [restore] before the first build.
class SignupFormDraft {
  SignupFormDraft({
    required this.cacheKey,
    required this.fields,
    this.readExtra,
    this.writeExtra,
  });

  final String cacheKey;
  final Map<String, TextEditingController> fields;
  final Map<String, dynamic> Function()? readExtra;
  final void Function(Map<String, dynamic> data)? writeExtra;

  /// Load cached values onto the controllers + non-text state. Call in initState
  /// *before* `bind()` so restoring doesn't immediately re-save.
  void restore() {
    final data = SignupFormCache.instance.read(cacheKey);
    if (data == null) return;
    data.forEach((key, value) {
      final controller = fields[key];
      if (controller != null && value is String) controller.text = value;
    });
    writeExtra?.call(data);
  }

  void bind() {
    for (final controller in fields.values) {
      controller.addListener(save);
    }
  }

  void unbind() {
    for (final controller in fields.values) {
      controller.removeListener(save);
    }
  }

  /// Snapshot current state into the cache. Wired to every controller by
  /// [bind]; call manually after changing a dropdown / date / checkbox / upload.
  void save() {
    SignupFormCache.instance.save(cacheKey, {
      for (final entry in fields.entries) entry.key: entry.value.text,
      ...?readExtra?.call(),
    });
  }

  bool get hasData => SignupFormCache.instance.hasData(cacheKey);
}

/// Password + confirm-password fields with real-time validation, an inline
/// error list and a strength meter. Rules come from [evaluatePassword] (a client
/// mirror of the backend validators). [onValidityChanged] fires whenever the
/// "both fields are filled and valid and match" state flips — screens use it to
/// enable/disable their submit button.
class SignupPasswordFields extends StatefulWidget {
  const SignupPasswordFields({
    super.key,
    required this.passwordController,
    required this.confirmController,
    this.emailController,
    this.nameController,
    this.phoneController,
    this.onValidityChanged,
    this.onChanged,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final TextEditingController? emailController;
  final TextEditingController? nameController;
  final TextEditingController? phoneController;
  final ValueChanged<bool>? onValidityChanged;
  final VoidCallback? onChanged;

  @override
  State<SignupPasswordFields> createState() => _SignupPasswordFieldsState();
}

class _SignupPasswordFieldsState extends State<SignupPasswordFields> {
  bool _obscure = true;
  bool _obscureConfirm = true;
  Timer? _debounce;
  PasswordEvaluation _eval = PasswordEvaluation.empty;
  String? _confirmError;
  bool _lastReportedValid = false;

  @override
  void initState() {
    super.initState();
    widget.passwordController.addListener(_onEdit);
    widget.confirmController.addListener(_onEdit);
    // Repopulated-from-cache values should evaluate immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.passwordController.removeListener(_onEdit);
    widget.confirmController.removeListener(_onEdit);
    super.dispose();
  }

  void _onEdit() {
    widget.onChanged?.call();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _recompute);
  }

  void _recompute() {
    if (!mounted) return;
    final pw = widget.passwordController.text;
    final confirm = widget.confirmController.text;
    final eval = evaluatePassword(
      pw,
      email: widget.emailController?.text ?? '',
      name: widget.nameController?.text ?? '',
      phone: widget.phoneController?.text ?? '',
    );
    final confirmError = confirmPasswordError(pw, confirm);
    setState(() {
      _eval = eval;
      _confirmError = confirmError;
    });
    final valid = pw.isNotEmpty &&
        eval.isValid &&
        confirm.isNotEmpty &&
        confirmError == null;
    if (valid != _lastReportedValid) {
      _lastReportedValid = valid;
      widget.onValidityChanged?.call(valid);
    }
  }

  Color get _strengthColor {
    switch (_eval.strength) {
      case PasswordStrength.empty:
      case PasswordStrength.weak:
        return const Color(0xFFE5484D);
      case PasswordStrength.fair:
        return const Color(0xFFF5A524);
      case PasswordStrength.good:
        return const Color(0xFF6DB33F);
      case PasswordStrength.strong:
        return _kAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pw = widget.passwordController.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PwLabel('Password'),
        const SizedBox(height: 6),
        _PwField(
          controller: widget.passwordController,
          hint: 'At least 8 characters',
          obscure: _obscure,
          onToggle: () => setState(() => _obscure = !_obscure),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Password is required';
            final e = evaluatePassword(
              v,
              email: widget.emailController?.text ?? '',
              name: widget.nameController?.text ?? '',
              phone: widget.phoneController?.text ?? '',
            );
            return e.errors.isEmpty ? null : e.errors.first;
          },
        ),
        if (pw.isNotEmpty) ...[
          const SizedBox(height: 8),
          _StrengthMeter(
              fraction: _eval.strength.fraction,
              color: _strengthColor,
              label: _eval.strength.label),
          for (final err in _eval.errors)
            _InlineNote(err, color: _kError, icon: Icons.error_outline),
          if (_eval.isValid && _eval.hints.isNotEmpty)
            _InlineNote('Stronger with: ${_eval.hints.join(' · ')}',
                color: Colors.grey.shade500, icon: Icons.tips_and_updates_outlined),
        ],
        const SizedBox(height: 16),
        const _PwLabel('Confirm Password'),
        const SizedBox(height: 6),
        _PwField(
          controller: widget.confirmController,
          hint: 'Re-enter password',
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Please confirm your password';
            if (v != widget.passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        if (_confirmError != null)
          _InlineNote(_confirmError!, color: _kError, icon: Icons.error_outline),
        if (_confirmError == null &&
            widget.confirmController.text.isNotEmpty &&
            pw.isNotEmpty)
          const _InlineNote('Passwords match',
              color: _kAccent, icon: Icons.check_circle_outline),
      ],
    );
  }
}

class _PwLabel extends StatelessWidget {
  const _PwLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(children: [
        TextSpan(
            text: text,
            style: const TextStyle(
                color: Color(0xFF2A2A2A),
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const TextSpan(
            text: ' *',
            style: TextStyle(
                color: _kError, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _PwField extends StatelessWidget {
  const _PwField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    required this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      autovalidateMode: AutovalidateMode.disabled,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        errorStyle: const TextStyle(color: _kError, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: Colors.grey.shade400,
              size: 20),
          onPressed: onToggle,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _kAccent, width: 1.5)),
        errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _kError)),
        focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _kError, width: 1.5)),
      ),
      validator: validator,
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter(
      {required this.fraction, required this.color, required this.label});
  final double fraction;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction == 0 ? 0.06 : fraction,
                minHeight: 5,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(label,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote(this.text, {required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

// Kept so screens can reference a debug-only assertion helper if needed.
const bool kSignupVerbose = kDebugMode;
